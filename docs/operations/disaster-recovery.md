# Complete Disaster Recovery Checklist

Single-page checklist for complete cluster recovery from scratch. Use this document when everything is broken.

---

## Prerequisites

| Item | Where to find | Check |
|------|---------------|-------|
| Laptop with internet | — | [ ] |
| 1Password account access | 1password.com | [ ] |
| GitHub account with repo access | github.com/TheIronRock95/homelab-config | [ ] |
| Proxmox VE host access | https://10.0.10.200:8006 | [ ] |
| Hetzner Object Storage backups intact | Hetzner Console — bucket `homelab-prd` | [ ] |

---

## Tool Installation

```bash
# macOS
brew install opentofu kubectl 1password-cli talosctl

# Verify
tofu version && kubectl version --client && op --version && talosctl version --client
```

---

## Phase 1: Clone Repository

```bash
git clone https://github.com/TheIronRock95/homelab-config.git
cd homelab-config
```

---

## Phase 2: Bootstrap Talos Cluster

**Time: ~20 minutes**

```bash
cd resources/bootstrap

# Sign in to 1Password and load credentials
eval $(op signin)
source ./scripts/load-secrets.sh

# Verify configuration (check proxmox.auto.tfvars)
cat proxmox.auto.tfvars

# Deploy cluster
tofu init && tofu plan && tofu apply
```

### Verify Cluster Health

```bash
export KUBECONFIG=$(pwd)/output/kube-config.yaml
export TALOSCONFIG=$(pwd)/output/talos-config.yaml

kubectl get nodes          # Expect: 6 nodes, all Ready
kubectl get pods -n kube-system -l k8s-app=cilium   # Expect: 6 pods Running
```

---

## Phase 3: Deploy GitOps Stack

**Time: ~15 minutes**

```bash
cd ../gitops-config

# Generate secrets from 1Password
./scripts/generate-input-files.sh

# Load S3 credentials
source ./scripts/load-secrets.sh

# Deploy ArgoCD stack
export TF_VAR_kube_config_path="$(pwd)/../bootstrap/output/kube-config.yaml"
tofu init && tofu plan && tofu apply

# Verify
kubectl get pods -n argocd
kubectl get applications -n argocd
```

---

## Phase 4: Wait for Auto-Sync

**Time: ~10-15 minutes**

ArgoCD deploys operators in wave order:

1. **Wave 0**: Cilium (pre-installed), Longhorn
2. **Wave 1**: 1Password Connect
3. **Wave 2**: External Secrets
4. **Wave 3**: cert-manager, external-dns, Prometheus stack

```bash
# Monitor progress
watch -n 5 'kubectl get applications -n argocd'
# All apps must become "Synced" and "Healthy"
```

---

## Phase 5: Restore Data from Backups

**Time: ~30-60 minutes (depending on data size)**

### Verify Longhorn Backup Target

```bash
kubectl get setting -n longhorn-system backup-target
# Expected: s3://homelab-prd@nbg1/longhorn-backup/
```

### Access Longhorn UI

```bash
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# Open: http://localhost:8080
```

### Restore Volumes

In Longhorn UI → Backup tab → for each critical volume:
1. Click volume name
2. Click **Restore Latest Backup**
3. Enter original PVC name and namespace
4. Click **OK**

**Critical volumes to restore:**

| Volume | Namespace | Priority |
|--------|-----------|----------|
| prometheus-db | monitoring | Medium |
| loki-storage | monitoring | Medium |
| grafana | monitoring | Low |

### Verify Restored Volumes

```bash
kubectl get pvc -A               # All PVCs must be Bound
kubectl get pods -A | grep -v Running   # No stuck pods
```

---

## Phase 6: Final Verification

```bash
# 1. All nodes ready
kubectl get nodes

# 2. All pods running
kubectl get pods -A | grep -v Running | grep -v Completed

# 3. All PVCs bound
kubectl get pvc -A | grep -v Bound

# 4. All ArgoCD apps synced
kubectl get applications -n argocd

# 5. Longhorn healthy
kubectl get volumes -n longhorn-system

# 6. External access works
curl -k https://argocd.svc.damman.tech
curl -k https://grafana.svc.damman.tech
```

---

## Quick Reference — IP Addresses

| Component | IP |
|-----------|----|
| Cluster VIP | 10.0.10.140 |
| Control Plane 1 | 10.0.10.130 |
| Control Plane 2 | 10.0.10.131 |
| Control Plane 3 | 10.0.10.132 |
| Worker 1 | 10.0.10.133 |
| Worker 2 | 10.0.10.134 |
| Worker 3 | 10.0.10.135 |
| Proxmox | 10.0.10.200 |
| Gateway | 10.0.10.193 |
| Cilium LB Pool | 10.0.10.240–250 |

---

## Quick Reference — 1Password Items

**Homelab vault:**
- `Proxmox` — username, password, api_token
- `hetzner-homelab-prd` — username (access key), password (secret key)

**KubernetesSecrets vault:**
- `op-connect-credentials` — 1Password Connect JSON
- `op-connect-token` — Connect access token
- `github-argo-app` — GitHub App credentials
- `github-client-secrets` — GitHub OAuth (ArgoCD SSO)
- `longhorn-s3-backup` — Backblaze credentials for Longhorn
- `grafana-admin` — Grafana admin password
- `pushover-credentials` — Alertmanager notifications

---

## Troubleshooting During Recovery

### Tofu init fails with S3 error

```bash
echo $AWS_ACCESS_KEY_ID   # Check credentials loaded
source ./scripts/load-secrets.sh
```

### Nodes not joining cluster

```bash
talosctl -n 10.0.10.130 health
talosctl -n 10.0.10.130 dmesg | tail -50
```

### ArgoCD apps stuck

```bash
kubectl get applications -n argocd -o name | \
  xargs -I {} kubectl patch {} -n argocd --type merge \
  -p '{"operation":{"sync":{"syncStrategy":{"hook":{}}}}}'
```

### Longhorn volumes degraded

```bash
kubectl get replicas -n longhorn-system
# Wait for auto-rebuild (10-30 min)
watch -n 10 'kubectl get volumes -n longhorn-system'
```
