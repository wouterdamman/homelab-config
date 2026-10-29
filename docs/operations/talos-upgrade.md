# Talos Upgrade Procedure

How to safely upgrade Talos Linux across the cluster using **talosctl upgrade** (Talos-native method).

## Overview

The infrastructure uses **talosctl upgrade** for rolling upgrades, which is the official Talos-recommended method. This provides:
- **Native Talos upgrades** using talosctl commands
- **A-B image scheme** with automatic rollback on boot failure
- **etcd quorum protection** built into Talos
- **Zero-downtime** rolling upgrades
- **Automated upgrade script** for hands-off upgrades
- **Health verification** between each node

## Quick Start - Automated Upgrade

The easiest and recommended way to upgrade is using the automated script:

```bash
cd resources/bootstrap

# Dry run first (see what would happen)
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0 --dry-run

# Run actual upgrade
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0
```

### Single Node Upgrade (for testing)

Test upgrades on a single node first:

```bash
# Test on specific node by name
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0 --node prd-cp-01

# Or by IP address
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0 --node-ip 10.0.10.130

# Dry run on single node
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0 --node prd-cp-01 --dry-run
```

### Script Options

```
--current <version>       Current Talos version (required)
--target <version>        Target Talos version (required)
--dry-run                 Preview changes without applying
--node <name>             Upgrade only this node (e.g., prd-cp-01)
--node-ip <ip>            Upgrade only this IP (e.g., 10.0.10.130)
--skip-workers            Only upgrade control planes
--skip-control-planes     Only upgrade workers
--auto-approve            Skip confirmation (use with caution!)
--worker-wait <seconds>   Custom wait time between workers (default: 120)
--cp-wait <seconds>       Custom wait time between CPs (default: 600)
```

### Examples

```bash
# Dry run to see what would happen
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0 --dry-run

# Test single node first (recommended)
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0 --node prd-cp-01

# Only upgrade workers
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0 --skip-control-planes

# Full automated upgrade
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0

# Faster upgrade (shorter wait times - use with caution)
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0 --worker-wait 120 --cp-wait 300
```

## How It Works

The upgrade script uses **talosctl upgrade** with Factory installer images:

1. **Builds installer image URL**: `factory.talos.dev/installer/<schematic-id>:<version>`
2. **Upgrades each node**: `talosctl upgrade --nodes <ip> --image <installer-url> --wait`
3. **Waits for Ready**: Verifies node returns to Ready state
4. **Health checks**: Verifies cluster health before proceeding to next node
5. **Sequential execution**: One node at a time, workers first, then control planes

### Installer Image Format

The script **dynamically computes the schematic ID** at runtime by posting `talos/image/schematic.yaml` to the Talos image factory — identical to what Terraform's `data.http.schematic_id` does. No hardcoded ID in the script.

```
factory.talos.dev/installer/<computed-schematic-id>:<version>
```

**Schematic includes** (defined in `talos/image/schematic.yaml`):
- `siderolabs/i915` (Intel GPU support)
- `siderolabs/intel-ucode`
- `siderolabs/qemu-guest-agent` (Proxmox integration)
- `siderolabs/iscsi-tools` (Longhorn storage)
- `siderolabs/util-linux-tools`

If you add or remove extensions from `schematic.yaml`, the script automatically picks up the new ID on the next run.

## Upgrade Strategy

### Recommended Order
1. **Workers first** (one at a time, 2 min wait)
2. **Control planes** (one at a time, 10 min wait)

This ensures:
- Workloads can be safely drained
- etcd quorum is maintained (need 2/3 CPs online)
- API server remains available

### Expected Timeline
- **Workers**: 3 nodes × (~5 min upgrade + 2 min wait) = ~21 minutes
- **Control Planes**: 3 nodes × (~5 min upgrade + 10 min wait) = ~45 minutes
- **Total**: ~65-80 minutes for full cluster upgrade

## Manual Upgrade (Advanced)

### Step 1: Set Environment Variables

```bash
export TALOSCONFIG=/path/to/resources/bootstrap/output/talos-config.yaml
export KUBECONFIG=/path/to/resources/bootstrap/output/kube-config.yaml
```

### Step 2: Build Installer Image URL

```bash
# Compute schematic ID dynamically from schematic.yaml
SCHEMATIC_FILE="resources/bootstrap/talos/image/schematic.yaml"
SCHEMATIC_ID=$(curl -sf -X POST https://factory.talos.dev/schematics \
  --data-binary @"$SCHEMATIC_FILE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
TARGET_VERSION="v1.15.0"
INSTALLER_IMAGE="factory.talos.dev/installer/${SCHEMATIC_ID}:${TARGET_VERSION}"
```

### Step 3: Upgrade Workers

```bash
# Upgrade prd-w-01 (10.0.10.133)
talosctl upgrade --nodes 10.0.10.133 --image $INSTALLER_IMAGE --wait

# Wait for Ready
kubectl get node prd-w-01 -w

# Verify health
kubectl get nodes
kubectl get pods -A | grep -v Running

# Wait 5 minutes before next worker
sleep 300

# Repeat for prd-w-02 (10.0.10.134) and prd-w-03 (10.0.10.135)
```

### Step 4: Upgrade Control Planes

> ⚠️ **CRITICAL**: Only one CP at a time to maintain etcd quorum!

```bash
# Upgrade prd-cp-01 (10.0.10.130)
talosctl upgrade --nodes 10.0.10.130 --image $INSTALLER_IMAGE --wait

# Wait for Ready
kubectl get node prd-cp-01 -w

# Verify etcd health
talosctl --nodes 10.0.10.130 service etcd status

# Verify cluster health
kubectl get nodes
kubectl get --raw /healthz

# Wait 10 minutes before next CP
sleep 600

# Repeat for prd-cp-02 (10.0.10.131) and prd-cp-03 (10.0.10.132)
```

### Step 5: Verify All Nodes

```bash
# Check all nodes on target version
talosctl version --nodes 10.0.10.130,10.0.10.131,10.0.10.132,10.0.10.133,10.0.10.134,10.0.10.135

# Check all nodes Ready
kubectl get nodes -o wide
```

### Step 6: Update Terraform State (Optional)

After successful upgrade, update `resources/bootstrap/proxmox.auto.tfvars`:

```hcl
talos_version = "v1.15.0"
```

Apply to sync Terraform state:

```bash
cd resources/bootstrap
tofu apply  # Only updates Terraform state, doesn't change VMs
```

## Verification

```bash
# Check all nodes running same version
kubectl get nodes -o wide
talosctl --nodes 10.0.10.130,10.0.10.131,10.0.10.132,10.0.10.133,10.0.10.134,10.0.10.135 version

# Check cluster health
kubectl get pods -A           # All pods Running
kubectl get pv                # All volumes Bound
kubectl get nodes             # All nodes Ready
kubectl top nodes             # Resource usage

# Verify Cilium
kubectl get pods -n kube-system -l k8s-app=cilium
```

## Kubernetes Upgrade

`upgrade-talos.sh` only upgrades the Talos OS. Kubernetes (kubelet, apiserver, controller-manager, scheduler) is upgraded separately with `talosctl upgrade-k8s`, which rolls the control plane components and kubelets one node at a time:

```bash
cd resources/bootstrap
talosctl --talosconfig output/talos-config.yaml -n 10.0.10.130 upgrade-k8s --to <version> --dry-run
talosctl --talosconfig output/talos-config.yaml -n 10.0.10.130 upgrade-k8s --to <version>
```

Before bumping the Kubernetes minor, check that Cilium and Longhorn list the target version as tested:
- Cilium: `https://docs.cilium.io/en/v<cilium-minor>/network/kubernetes/compatibility/`
- Longhorn: `https://longhorn.io/docs/<longhorn-version>/best-practices/`

Also check for deprecated API usage scheduled for removal:

```bash
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
```

## Talos 1.14 Notes

- **etcd ports**: Talos 1.14 moves the etcd HTTP endpoints (`/metrics`, `/health`) from 2379 to 2383. We set `listen-metrics-urls: http://0.0.0.0:2381` explicitly in `control-plane.yaml.tftpl`, so the kube-prometheus-stack `kubeEtcd` scrape on 2381 is unaffected.
- **Filesystem trim**: clusters upgraded from older versions have no `FilesystemTrimConfig` document, so trim is off until added. Both machine-config templates carry a weekly `FilesystemTrimConfig`. VM disks have `discard = "on"`, so trimmed blocks return to Proxmox storage.
- **Workload isolation** (`SecurityProfileConfig`, `workloadIsolation: true`): default for new clusters only; upgraded clusters stay non-isolated. `sandboxd` always runs, but the runtime only moves into it after a reboot ("applied without a reboot" is misleading). Enabled per node via `local.workload_isolation_nodes` in `talos/config.tf`; prd-w-01 since 2026-10-26, where Longhorn iSCSI attach/detach and replica rebuild were verified; all nodes since 2026-10-27. Check a node with `talosctl -n <ip> read /proc/<kubelet-pid>/status | grep NSpid`: two values means kubelet runs inside the sandbox.
- **`apply-config --mode=reboot` removed**: use `talosctl reboot` explicitly.
- **Installer image**: `ghcr.io/siderolabs/installer` is no longer published. The upgrade script already uses the Image Factory installer.
- **Gateway API extraManifests**: `talosctl upgrade-k8s` re-applies the machine config `extraManifests`. The cluster runs the Gateway API standard channel, and its `safe-upgrades` ValidatingAdmissionPolicy rejects experimental CRDs on top, so all Gateway API URLs in `control-plane.yaml.tftpl` use `config/crd/standard/`. Run `tofu apply` before `upgrade-k8s` so the nodes carry the current URLs, otherwise old CRD versions get applied.

## Machine Config Contract (multi-document Kube* configs)

`local.config_contract` in `talos/config.tf` sets the contract per node type:

- **Control planes: v1.14.** Kubernetes settings live in `KubeletConfig`, `KubeNodeConfig`, `KubeControllerManagerConfig`, `KubeSchedulerConfig`, `KubeProxyConfig` (disabled), `KubeExternalManifestConfig` and `KubeInlineManifestConfig`. The generated `KubeFlannelCNIConfig` is removed with `$patch: delete`. Only `machine.network` and `cluster.etcd` stay in v1alpha1.
- **Workers: v1.13.** With v1.14, `machine.kubelet.extraMounts` is rejected ("kubelet config is already set in v1alpha1 config"). Since 2026-10-27 Longhorn runs on the Talos user volume `longhorn` (`/dev/sdb`, mounted at `/var/mnt/longhorn`, which the kubelet sees without extra mounts), so workers can now move to v1.14 as well.

Before applying a contract or template change, render and dry-run it on the node (read-only):

```bash
talosctl gen secrets --from-controlplane-config output/talos-machine-config-prd-cp-01.yaml -o /tmp/secrets.yaml
talosctl gen config talos-prd https://10.0.10.130:6443 --with-secrets /tmp/secrets.yaml \
  --talos-version v1.14 --kubernetes-version 1.37.0 --config-patch-control-plane @patch.yaml -o /tmp/out
talosctl validate --mode metal --strict -c /tmp/out/controlplane.yaml
talosctl -n <ip> apply-config --file /tmp/out/controlplane.yaml --dry-run
```

Behaviour that changes with contract v1.14 on the control planes: anonymous apiserver access is allowed for `/livez`, `/readyz` and `/healthz` only (it was `--anonymous-auth=false`). `VolumeConfig EPHEMERAL` is pinned to `secure: false` and `SecurityProfileConfig` is set per node from `local.workload_isolation_nodes` (now `true` on all nodes).

## Longhorn Disk Migration (user volume)

How a worker's Longhorn disk moved from `machine.disks` on `/var/lib/longhorn` to the `UserVolumeConfig` `longhorn` on `/var/mnt/longhorn` (2026-10-27). The same steps apply when rebuilding a worker disk:

1. Longhorn: on the node disk, set `allowScheduling: false` and `evictionRequested: true`. Wait until no replicas remain on the node. Lower 3-replica volumes to 2 first (only 3 workers, hard anti-affinity). Strict-local volumes (Loki, Prometheus) cannot move: cordon the node, delete their PVCs and pods, and they come back empty elsewhere.
2. Delete leftover "ghost" replica CRs (no node, disk or data directory) once the volume has enough running replicas. Longhorn 1.13 leaves them behind after evictions.
3. Drain the node, add it to `local.longhorn_uservolume_nodes`, then plan and apply only that node.
4. Reboot (the old mount stays active until then), then `talosctl -n <ip> wipe disk sdb --drop-partition`. Talos provisions and mounts `/var/mnt/longhorn`.
5. Longhorn node: replace the `default-disk` (`/var/lib/longhorn/`) with a disk at `/var/mnt/longhorn`, then uncordon.

## Lessons from the 1.13 → 1.14 upgrade (2026-10-26)

- **etcd shares a disk with every VM.** All OS disks, etcd included, are raw files on one consumer NVMe on pve-01. A node reboot stalled etcd `fdatasync` for 1-6s. On the first worker this caused an etcd leader election and API timeouts, and the CNPG primaries shut themselves down (liveness isolation check). PR #579 made CNPG tolerate ~3 minutes; a Proxmox `mbps_wr` throttle on the rebooting VM did not help.
- **Wait for calm between nodes.** Before the next node, wait until Longhorn volumes are healthy, CNPG is healthy and etcd has logged no `heartbeat`/`slow fdatasync` warnings for 5 minutes:
  ```bash
  talosctl -n 10.0.10.130,10.0.10.131,10.0.10.132 logs etcd --tail 500 | grep -E "heartbeat|slow fdatasync|elected"
  ```
- **Upgrade the etcd leader last**, and move leadership off it first:
  ```bash
  talosctl -n <leader-ip> etcd forfeit-leadership
  ```
- **Strict-local volumes** (`longhorn-monitoring`) cannot move. Loki and Prometheus are down while their node reboots.
- **Use the VIP.** The kubeconfig now points at `10.0.10.140`; with `10.0.10.130` kubectl fails while prd-cp-01 reboots.

## Hardware Changes (RAM, iothread, devices)

`reboot_after_update = false` on the VMs: `tofu apply` only stages hardware changes in Proxmox (`qm pending <vmid>`). A guest reboot does not apply them, because the QEMU process stays the same. Roll them out node by node:

```bash
cd resources/bootstrap
./scripts/powercycle-node.sh prd-w-01 --dry-run
./scripts/powercycle-node.sh prd-w-01
```

The script waits until the cluster is calm (5 minutes without etcd warnings, etcd 3/3, CNPG and Longhorn healthy, all nodes Ready). It then:

1. Adds Alertmanager silences (90 minutes) for alerts with the node name, the node IP or the Proxmox VM ID, plus the cluster-wide symptoms of a missing node (`TargetDown`, `KubePodNotReady`, replica mismatches, etcd member alerts). The silences are expired when the script exits, also on failure, so a node left down still alerts.
2. Moves etcd leadership away (control planes).
3. Switches every CNPG primary on the node over to a ready replica on another node (`kubectl cnpg promote`). The primary PDB allows no disruption, so without this the drain times out and the shutdown forces an unplanned failover. No ready replica elsewhere stops the script.
4. Drains, runs `talosctl shutdown` and `qm start`, waits for Ready (and etcd 3/3 on control planes), and uncordons.
5. Waits up to 30 minutes until all Longhorn volumes and CNPG clusters are healthy again, and fails otherwise, so a loop over several nodes stops there.

Requires the `kubectl cnpg` plugin. Order: workers, then control planes, with the etcd leader last.

## Rollback

### Automatic Rollback
If a node fails to boot with the new version, Talos's A-B image scheme automatically rolls back to the previous version on the next boot attempt.

### Manual Rollback

```bash
talosctl rollback --nodes <node-ip>

# Example: Rollback prd-w-02
talosctl rollback --nodes 10.0.10.134
```

## Troubleshooting

### Node Stuck in Upgrade
**Symptom**: Node shows "NotReady" for >10 minutes

```bash
talosctl --nodes 10.0.10.133 dmesg
talosctl --nodes 10.0.10.133 logs controller-runtime
talosctl --nodes 10.0.10.133 logs kubelet

# Force reboot if needed
talosctl --nodes 10.0.10.133 reboot
```

### etcd Quorum Lost
**Symptom**: API server unavailable, `kubectl` commands timeout

**Cause**: Multiple CPs upgraded simultaneously or network issues

**Fix**: Wait for nodes to complete reboot. etcd will auto-recover if quorum is possible (2/3 nodes).

```bash
talosctl --nodes 10.0.10.130 etcd members
```

### Upgrade Command Fails
**Common causes:**
1. **Network issues**: Check node can reach factory.talos.dev
2. **Invalid version**: Verify version format (must be like `v1.14.0`)
3. **Wrong schematic ID**: Verify schematic file is correct

```bash
# Check connectivity and retry
talosctl --nodes 10.0.10.133 get addresses
talosctl upgrade --nodes 10.0.10.133 --image $INSTALLER_IMAGE --wait
```

## Best Practices

**DO:**
- ✅ Use the automated upgrade script
- ✅ Run dry-run first to verify behavior
- ✅ Upgrade workers before control planes
- ✅ Wait 5-10 minutes between control plane upgrades
- ✅ Monitor cluster during upgrades: `kubectl get events --watch`
- ✅ Backup etcd before major upgrades: `talosctl etcd snapshot`
- ✅ Keep upgrade version close to current (max 1-2 minor versions)
- ✅ Test upgrades during low-traffic periods

**DON'T:**
- ❌ Upgrade multiple control planes simultaneously
- ❌ Skip dry-run testing
- ❌ Upgrade during peak hours
- ❌ Upgrade with pending cluster issues

## Pre-Upgrade Checklist

1. ✅ Backup etcd: `talosctl -n 10.0.10.130 etcd snapshot /tmp/etcd-backup.db`
2. ✅ Verify cluster health: `kubectl get nodes` and `kubectl get pods -A`
3. ✅ Check Talos version compatibility (max 2 minor versions jump)
4. ✅ Review Talos release notes for breaking changes
5. ✅ Ensure TALOSCONFIG and KUBECONFIG are set
6. ✅ Verify network connectivity to factory.talos.dev
7. ✅ Plan maintenance window (65-80 minutes)

## Quick Reference

```bash
# Run automated upgrade (must run from resources/bootstrap/)
cd resources/bootstrap
./scripts/upgrade-talos.sh --current v1.14.4 --target v1.15.0

# Check current versions
kubectl get nodes -o wide
talosctl version --nodes 10.0.10.130,10.0.10.131,10.0.10.132,10.0.10.133,10.0.10.134,10.0.10.135

# Monitor upgrade
watch -n 5 'kubectl get nodes'
kubectl get events --watch

# Check etcd health
talosctl --nodes 10.0.10.130 service etcd status

# Manual rollback if needed
talosctl rollback --nodes 10.0.10.133
```

## Node IPs Reference

| Node | Role | IP |
|------|------|----|
| prd-cp-01 | Control Plane | 10.0.10.130 |
| prd-cp-02 | Control Plane | 10.0.10.131 |
| prd-cp-03 | Control Plane | 10.0.10.132 |
| prd-w-01 | Worker | 10.0.10.133 |
| prd-w-02 | Worker | 10.0.10.134 |
| prd-w-03 | Worker | 10.0.10.135 |
| VIP | — | 10.0.10.140 |

## Technical Details

### Why talosctl upgrade instead of Terraform?

The previous Terraform-based approach had critical issues:
1. **VM disk changes blocked**: `lifecycle { ignore_changes = [disk[0].file_id] }` prevented new images from being applied
2. **Machine config version mismatch**: Configs always used base version, not update version
3. **No actual upgrade trigger**: Changing tfvars downloaded images but didn't trigger node upgrades

The **talosctl upgrade** approach:
- Uses Talos's native upgrade mechanism (official recommendation)
- Provides built-in rollback protection via A-B partitioning
- Handles etcd quorum protection automatically
- Clearer separation: Terraform manages infrastructure, talosctl manages OS

### Schematic Management

The schematic ID is stable across Talos versions because system extensions are version-independent. The same schematic works for v1.13.x, v1.14.x, etc.

The upgrade script **dynamically computes** the schematic ID at runtime — same approach as Terraform's `data.http.schematic_id`:

```bash
SCHEMATIC_ID=$(curl -sf -X POST https://factory.talos.dev/schematics \
  --data-binary @"$SCHEMATIC_FILE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
```

**Current computed ID**: `e37cea50363b49e1887745d13c0a9fcb282499ee982535f2369db3fa1ce770c1`
**Source**: `resources/bootstrap/talos/image/schematic.yaml`

## References
- [Talos Upgrade Documentation](https://docs.siderolabs.com/talos/v1.8/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
- [Talos Image Factory](https://www.talos.dev/v1.11/learn-more/image-factory/)
- Local script: `resources/bootstrap/scripts/upgrade-talos.sh`
