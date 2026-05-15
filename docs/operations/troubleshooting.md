# Troubleshooting Guide

Common issues and solutions for the homelab Kubernetes environment.

---

## Quick Diagnostics

```bash
# Cluster health check
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl get pvc -A | grep -v Bound

# ArgoCD status
kubectl get applications -n argocd

# Longhorn status
kubectl get volumes -n longhorn-system
kubectl get nodes -n longhorn-system
```

---

## 1. Node Issues

### Node NotReady

```bash
# Check node conditions
kubectl describe node <node-name> | grep -A 10 Conditions

# Check Talos status
talosctl -n <node-ip> health
talosctl -n <node-ip> dmesg | tail -50
```

| Cause | Solution |
|-------|---------|
| Kubelet crashed | `talosctl -n <ip> service kubelet restart` |
| Network partition | Check physical network, switch, VLAN config |
| Disk full | Check disk usage, cleanup old snapshots |
| OOM killed | Check memory pressure, scale down workloads |
| etcd issues (CP) | Check etcd cluster health (see below) |

### etcd Cluster Unhealthy

```bash
# Check etcd status on all control plane nodes
talosctl --talosconfig <config> -n <cp1>,<cp2>,<cp3> etcd status

# Check for alarms
talosctl --talosconfig <config> -n <cp1> etcd alarm list

# Check etcd members
talosctl --talosconfig <config> -n <cp1> etcd members
```

**CORRUPT Cluster Alarm:**

If you see `alarm:CORRUPT` in the etcd status output:

```bash
# Step 1: Try to switch leader
talosctl --talosconfig <config> -n <current-leader-ip> etcd forfeit-leadership

# Step 2: Disarm the alarm on the new leader
talosctl --talosconfig <config> -n <new-leader-ip> etcd alarm disarm

# Step 3: Check if alarm is gone
talosctl --talosconfig <config> -n <cp1>,<cp2>,<cp3> etcd status
```

If the alarm returns, the corrupt member must be removed and re-added:

```bash
# Step 1: Identify the corrupt member (memberID in ERRORS column)
# Step 2: Remove the member from a healthy node
talosctl --talosconfig <config> -n <healthy-cp-ip> etcd remove-member <member-id>

# Step 3: Disarm alarm on remaining members
talosctl --talosconfig <config> -n <healthy-cp-ip> etcd alarm disarm

# Step 4: Reset the corrupt node (wipes etcd data, node restarts)
talosctl --talosconfig <config> -n <corrupt-node-ip> reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL

# Step 5: Wait for node to come back online and automatically rejoin (~1-2 minutes)
talosctl --talosconfig <config> -n <all-cp-ips> etcd status
```

### VM Memory Upgrades (Proxmox)

> **IMPORTANT:** VMs must be fully shut down (shutdown), not rebooted! Otherwise memory changes are not applied.

**Procedure:**

1. **Update Terraform configuration:**

```bash
cd resources/bootstrap

# Edit proxmox.auto.tfvars
vim proxmox.auto.tfvars

# Increase RAM values:
# - controlplane_specs.ram (e.g. 4096 -> 5120 for +1GB)
# - worker_specs.ram (e.g. 10240 -> 12288 for +2GB)
```

2. **Plan and apply Terraform changes:**

```bash
tofu plan
tofu apply
```

3. **Shutdown and restart nodes one by one:**

**For workers:**

```bash
# Drain node
kubectl drain prd-w-01 --ignore-daemonsets --delete-emptydir-data

# Shutdown node (NOT reboot!)
talosctl --talosconfig output/talos-config.yaml -n 10.0.10.133 shutdown

# Wait until VM is fully off, then start via Proxmox UI or:
ssh root@10.0.10.200 "qm start <vm-id>"

# Wait until node ready
kubectl get nodes -w

# Uncordon node
kubectl uncordon prd-w-01

# Verify memory
kubectl get node prd-w-01 -o jsonpath='{.status.capacity.memory}'
```

**For control planes:**

```bash
# Shutdown node (one at a time!)
talosctl --talosconfig output/talos-config.yaml -n 10.0.10.130 shutdown

# Start via Proxmox
ssh root@10.0.10.200 "qm start <vm-id>"

# Wait until node ready
kubectl get nodes -w

# Verify etcd quorum intact
talosctl --talosconfig output/talos-config.yaml -n 10.0.10.130,10.0.10.131,10.0.10.132 etcd status
```

| Issue | Cause | Solution |
|-------|-------|---------|
| Memory not increased after reboot | VM needs shutdown, not reboot | Use `talosctl shutdown`, then start VM |
| Terraform wants to replace VM | file_id change in disk config | Check lifecycle ignore_changes contains disk[0].file_id |
| Pods stay on wrong nodes | Pod distribution doesn't auto-update | Restart deployments to rebalance |

---

## 2. Pod Issues

### Pod stuck in Pending

```bash
kubectl describe pod <pod-name> -n <namespace>
# Check Events section at the bottom
```

| Event Message | Cause | Solution |
|---------------|-------|---------|
| `Insufficient cpu/memory` | Resource limits too high | Increase node resources or lower requests |
| `no nodes available to schedule` | Taints/tolerations mismatch | Check node taints, add tolerations |
| `persistentvolumeclaim not found` | PVC doesn't exist | Create PVC or fix name |
| `volume node affinity conflict` | Volume on different node | Delete PVC, let Longhorn re-schedule |

### Pod stuck in ContainerCreating

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

| Event Message | Cause | Solution |
|---------------|-------|---------|
| `FailedMount` | Volume mount failed | Check PVC status, Longhorn health |
| `ImagePullBackOff` | Image not available | Check image name, registry access |
| `secret not found` | Secret missing | Check ExternalSecret status |

### Pod CrashLoopBackOff

```bash
# Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check exit code
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Last State"
```

**Exit codes:**
- `Exit Code 1` — Application error (check logs)
- `Exit Code 137` — OOMKilled (increase memory limit)
- `Exit Code 143` — SIGTERM (graceful shutdown, usually OK)

---

## 3. Storage Issues

### PVC stuck in Pending

```bash
kubectl describe pvc <pvc-name> -n <namespace>
kubectl get storageclass
```

| Cause | Solution |
|-------|---------|
| StorageClass not found | Use `longhorn-standard` (default) |
| Longhorn not ready | `kubectl get pods -n longhorn-system` |
| Disk space too low | Cleanup old volumes/snapshots |

### Volume Degraded

```bash
# Via CLI
kubectl get volumes -n longhorn-system
kubectl describe volume <volume-name> -n longhorn-system

# Via UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# Open: http://localhost:8080
```

| Status | Action |
|--------|--------|
| Degraded (1/2 replicas) | Wait for auto-rebuild, check node health |
| Degraded (0/2 replicas) | **URGENT**: Check all nodes, possible data loss |
| Faulted | Volume unrecoverable, restore from backup needed |

### Backup Failed

```bash
kubectl get backup -n longhorn-system
kubectl describe backup <backup-name> -n longhorn-system

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100 | grep -i error
```

| Cause | Solution |
|-------|---------|
| S3 credentials expired | Check ExternalSecret, refresh 1Password |
| S3 bucket not reachable | Check network, Hetzner Object Storage status |
| Volume in use | Some backups fail during heavy I/O, retry later |

---

## 4. Secrets Issues

### ExternalSecret not syncing

```bash
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>

# Check ClusterSecretStore
kubectl get clustersecretstore
kubectl describe clustersecretstore onepassword-connect
```

| Status | Cause | Solution |
|--------|-------|---------|
| `SecretSyncedError` | 1Password item/field not found | Check item name and property in 1Password |
| `SecretStoreNotReady` | 1Password Connect down | `kubectl get pods -n onepassword` |
| Secret empty | Property name mismatch | Use `username`/`password` for standard fields |

### 1Password Connect not working

```bash
kubectl get pods -n onepassword
kubectl logs -n onepassword -l app=onepassword-connect
```

```bash
# Regenerate credentials if expired
cd resources/gitops-config
./scripts/generate-input-files.sh
tofu apply
```

### Double Base64-Encoded Credentials

**Symptoms:**
- ClusterSecretStore status: `InvalidProviderConfig`
- onepassword-connect pod logs show JSON parse errors: `invalid character 'e' looking for beginning of value`
- ExternalSecrets stuck in `SecretSyncedError`

**Solution:**

```bash
# 1. Get correct credentials from 1Password
op item get "<item-id>" --reveal --fields label=password | base64 -d > /tmp/credentials.json
cat /tmp/credentials.json | jq .  # Verify valid JSON

# 2. Delete old secret and create new one
kubectl delete secret -n onepassword onepassword-connect-credentials
kubectl create secret generic onepassword-connect-credentials \
  -n onepassword \
  --from-file=1password-credentials.json=/tmp/credentials.json
rm /tmp/credentials.json

# 3. Delete and reapply ClusterSecretStore
kubectl delete clustersecretstore onepassword-connect
kubectl apply -f resources/gitops-config/operators/external-secrets/templates/cluster-secret-store.yaml

# 4. Force-sync all ExternalSecrets
kubectl get externalsecret -A -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read ns name; do
    kubectl annotate externalsecret -n $ns $name \
      force-sync="$(date +%s)" --overwrite
  done
```

**Prevention:**
- **USE:** `kubectl create secret --from-file=<file>` (does base64 automatically)
- **NOT:** `kubectl apply -f` with YAML where you manually did base64
- **NOT:** `echo <base64-string> | kubectl create` (becomes double encoded)

---

## 5. ArgoCD Issues

### Application OutOfSync

```bash
kubectl get applications -n argocd
argocd app get <app-name> --show-diff
```

| Cause | Solution |
|-------|---------|
| Manual changes in cluster | `argocd app sync <app-name>` |
| Git repo not reachable | Check GitHub credentials ExternalSecret |
| Helm values invalid | Check Helm chart logs in ArgoCD UI |

### ArgoCD can't reach GitHub

```bash
kubectl get externalsecret -n argocd
kubectl get secret -n argocd github-private-repo-creds -o yaml
```

```bash
# Verify GitHub App credentials in 1Password
op item get "github-argo-app" --vault KubernetesSecrets

# Force refresh ExternalSecret
kubectl delete externalsecret -n argocd github-private-repo-creds
# ArgoCD will automatically resync
```

---

## 6. Network Issues

### Service not reachable

```bash
# Check service and endpoints
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>

# Check Cilium status
kubectl -n kube-system get pods -l k8s-app=cilium
cilium status
```

### DNS resolution failed

```bash
# Test DNS from a pod
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

---

## 7. Monitoring Issues

### Prometheus targets down

```bash
# Port-forward Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090
# Open http://localhost:9090/targets
```

| Issue | Cause | Solution |
|-------|-------|---------|
| Target down | Pod not running | Check pod status, fix deployment |
| Scrape error | Wrong port/path | Check ServiceMonitor spec |
| No targets found | Label mismatch | Check selector labels on ServiceMonitor |
| kube-controller-manager/scheduler down | Metrics bind on 127.0.0.1 (Talos default) | Add `bind-address: 0.0.0.0` to Talos machine config |

**Talos control plane metrics configuration:**

```yaml
# In control-plane.yaml.tftpl
cluster:
  controllerManager:
    extraArgs:
      bind-address: "0.0.0.0"
  scheduler:
    extraArgs:
      bind-address: "0.0.0.0"
```

### Promtail not ready

| Issue | Cause | Solution |
|-------|-------|---------|
| 0/1 Ready, 500 errors | Missing `__path__` in config | Use default scrapeConfigs, don't override snippets.common |
| "no path for target" | Scrape config missing path relabeling | Check values.yaml, use chart defaults |
| Connection refused to Loki | Loki not running | Check Loki pod status first |

### Alerts not firing/receiving

```bash
# Check Alertmanager
kubectl port-forward -n monitoring svc/prometheus-alertmanager 9093:9093
# Open http://localhost:9093

# Check Pushover secret
kubectl get secret -n monitoring alertmanager-pushover-secret
kubectl get externalsecret -n monitoring alertmanager-pushover-credentials
```

### Proxmox VE Exporter Issues

```bash
# Check exporter pod
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-pve-exporter

# Check logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-pve-exporter

# Test metrics endpoint
kubectl port-forward -n monitoring svc/prometheus-pve-exporter 9221:80
curl http://localhost:9221/pve?target=10.0.10.200
```

| Issue | Cause | Solution |
|-------|-------|---------|
| Target DOWN | Exporter pod crashed | Check logs, restart deployment |
| 401 Unauthorized | Credentials incorrect/expired | Check 1Password item "Proxmox - Monitoring Account" |
| SecretSyncedError | ExternalSecret can't sync | Check ClusterSecretStore, 1Password Connect |
| No metrics visible | ServiceMonitor not discovered | Check labels: `release=prometheus` |

---

## 8. Quick Recovery Commands

### Force delete stuck resources

```bash
# Stuck namespace
kubectl get namespace <ns> -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/<ns>/finalize" -f -

# Stuck PVC
kubectl patch pvc <pvc-name> -n <ns> -p '{"metadata":{"finalizers":null}}'

# Stuck pod
kubectl delete pod <pod-name> -n <ns> --force --grace-period=0
```

### Restart components

```bash
# Restart all pods in a deployment
kubectl rollout restart deployment/<name> -n <namespace>

# Restart Longhorn
kubectl rollout restart daemonset/longhorn-manager -n longhorn-system

# Restart ArgoCD
kubectl rollout restart deployment -n argocd
```

### Emergency backup

```bash
# Manual snapshot of critical volume
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: emergency-snapshot-$(date +%s)
  namespace: longhorn-system
spec:
  volume: <volume-name>
  createSnapshot: true
EOF
```

---

## When to Escalate

### Contact community/support if:
- ⚠️ Multiple control plane nodes down simultaneously
- ⚠️ etcd cluster lost quorum (2/3 nodes down)
- ⚠️ Longhorn volumes Faulted status
- ⚠️ Data corruption suspected
- ⚠️ Backup restore fails repeatedly

### Useful Resources
- [Talos GitHub Issues](https://github.com/siderolabs/talos/issues)
- [Longhorn GitHub Issues](https://github.com/longhorn/longhorn/issues)
- [Kubernetes Slack](https://kubernetes.slack.com)
