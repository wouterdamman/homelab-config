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
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0 --dry-run

# Run actual upgrade
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0
```

### Single Node Upgrade (for testing)

Test upgrades on a single node first:

```bash
# Test on specific node by name
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0 --node prd-cp-01

# Or by IP address
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0 --node-ip 10.0.10.130

# Dry run on single node
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0 --node prd-cp-01 --dry-run
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
--worker-wait <seconds>   Custom wait time between workers (default: 300)
--cp-wait <seconds>       Custom wait time between CPs (default: 600)
```

### Examples

```bash
# Dry run to see what would happen
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0 --dry-run

# Test single node first (recommended)
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0 --node prd-cp-01

# Only upgrade workers
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0 --skip-control-planes

# Full automated upgrade
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0

# Faster upgrade (shorter wait times - use with caution)
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0 --worker-wait 120 --cp-wait 300
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
1. **Workers first** (one at a time, 5 min wait)
2. **Control planes** (one at a time, 10 min wait)

This ensures:
- Workloads can be safely drained
- etcd quorum is maintained (need 2/3 CPs online)
- API server remains available

### Expected Timeline
- **Workers**: 3 nodes × (~5 min upgrade + 5 min wait) = ~30 minutes
- **Control Planes**: 3 nodes × (~5 min upgrade + 10 min wait) = ~45 minutes
- **Total**: ~75-90 minutes for full cluster upgrade

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
TARGET_VERSION="v1.14.0"
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
talos_version = "v1.14.0"
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
7. ✅ Plan maintenance window (75-90 minutes)

## Quick Reference

```bash
# Run automated upgrade (must run from resources/bootstrap/)
cd resources/bootstrap
./scripts/upgrade-talos.sh --current v1.13.2 --target v1.14.0

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
