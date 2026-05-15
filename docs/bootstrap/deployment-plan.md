# Deployment Plan - Production Talos Cluster

Step-by-step process to deploy the production Talos Kubernetes cluster.

## Cluster Specification

| Node | Type | VM ID | IP | CPU | RAM | Disk |
|------|------|-------|-----|-----|-----|------|
| prd-cp-01 | Control Plane | 500 | 10.0.10.130 | 2 | 5GB | 60GB |
| prd-cp-02 | Control Plane | 501 | 10.0.10.131 | 2 | 5GB | 60GB |
| prd-cp-03 | Control Plane | 502 | 10.0.10.132 | 2 | 5GB | 60GB |
| prd-w-01 | Worker | 503 | 10.0.10.133 | 3 | 12GB | 250GB |
| prd-w-02 | Worker | 504 | 10.0.10.134 | 3 | 12GB | 250GB |
| prd-w-03 | Worker | 505 | 10.0.10.135 | 3 | 12GB | 250GB |

**Cluster VIP**: 10.0.10.140
**Gateway**: 10.0.10.193
**Proxmox Host**: dmn-sk-pve-01

## Deployment Status

> **✅ Cluster Deployed Successfully!**
> The production Talos cluster is now running on Proxmox host dmn-sk-pve-01.

### Completed Steps
- ✅ S3 backend configured (Hetzner Object Storage)
- ✅ Proxmox infrastructure verified
- ✅ 6 VMs deployed (3 control planes + 3 workers)
- ✅ Talos v1.13.2 installed
- ✅ Kubernetes cluster bootstrapped
- ✅ Cilium CNI deployed
- ✅ Cluster VIP active (10.0.10.140)

### Access Configuration

```bash
# Talos
export TALOSCONFIG=resources/bootstrap/output/talos-config.yaml
talosctl --nodes 10.0.10.130 version

# Kubernetes
export KUBECONFIG=resources/bootstrap/output/kube-config.yaml
kubectl get nodes
```

## 1Password Secrets Setup

> **All credentials are managed via 1Password!**
> No manual editing of `.env` files or hardcoded credentials needed.

### Prerequisites
- Install [1Password CLI](https://developer.1password.com/docs/cli/get-started/)
- Sign in to 1Password: `eval $(op signin)`
- Verify access to **Homelab** vault

### Required Items in 1Password

**Proxmox Credentials**
- **Item**: `Proxmox - Automation Account`
- **Fields**: `username` (automation@pve), `api_key` (automation@pve!tofu=\<token\>)
- **Reference Path**: `op://Homelab/Proxmox - Automation Account/*`

**Hetzner Object Storage Credentials**
- **Item**: `hetzner-homelab-prd`
- **Fields**: `username` (Access Key ID), `password` (Secret Access Key)
- **Reference Path**: `op://Homelab/hetzner-homelab-prd/*`

### Loading Secrets

```bash
cd resources/bootstrap

# Sign in to 1Password (if not already)
eval $(op signin)

# Load all secrets into environment
source ./scripts/load-secrets.sh
```

This exports:
- `TF_VAR_proxmox_username`
- `TF_VAR_proxmox_password`
- `TF_VAR_proxmox_api_token`
- `AWS_ACCESS_KEY_ID` (for S3 backend)
- `AWS_SECRET_ACCESS_KEY` (for S3 backend)

## Deployment Steps

### Step 1: Initialize Backend

```bash
cd resources/bootstrap
tofu init
```

### Step 2: Validate Configuration

```bash
tofu validate
```

### Step 3: Plan Deployment

```bash
tofu plan -out=tfplan
```

**Verify in plan:**
- 6 VMs (3 control planes + 3 workers)
- MAC addresses auto-generated
- Talos machine configs created
- Cluster bootstrap resource

### Step 4: Apply Infrastructure

```bash
tofu apply tfplan
```

**Timeline:**
1. Image download (~5 min)
2. VM creation (~2 min)
3. Talos config apply (~3 min)
4. Cluster bootstrap (~5 min)
5. Health check (~3 min)
6. Kubeconfig generation (~1 min)

**Total: ~20 minutes**

### Step 5: Verify Deployment

```bash
# Check Talos nodes
export TALOSCONFIG=output/talos-config.yaml
talosctl --nodes 10.0.10.130 health

# Check Kubernetes cluster
export KUBECONFIG=output/kube-config.yaml
kubectl get nodes -o wide

# Verify Cilium
kubectl get pods -n kube-system -l k8s-app=cilium
```

### Step 6: Save Outputs

Outputs saved to:
- `resources/bootstrap/output/kube-config.yaml`
- `resources/bootstrap/output/talos-config.yaml`
- `resources/bootstrap/output/talos-machine-config-*.yaml`

**Backup these files to 1Password!**

## Rollback / Cleanup

```bash
# Destroy entire cluster
tofu destroy

# Remove specific node
tofu destroy -target=proxmox_virtual_environment_vm.this["prd-w-02"]
```

## Troubleshooting

### Talos config apply timeout
**Cause**: VM not reachable or slow boot
**Fix**: Verify VM network config in Proxmox console

### Bootstrap fails with "etcd cluster not healthy"
**Cause**: Control plane nodes can't reach each other
**Fix**: Check VIP configuration, verify network connectivity

### Cilium pods CrashLoopBackOff
**Cause**: values.yaml misconfiguration
**Fix**: Check `resources/gitops-config/operators/cilium/values.yaml`
