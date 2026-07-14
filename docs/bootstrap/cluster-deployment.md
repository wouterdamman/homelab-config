# Cluster Deployment - Bootstrap

Complete guide for deploying the Talos Kubernetes cluster from scratch on Proxmox infrastructure.

## Overview

This guide provides a high-level walkthrough of the cluster deployment process. For detailed technical implementation, refer to the [Bootstrap README](https://github.com/wouterdamman/homelab-config/blob/main/resources/bootstrap/README.md) in the repository.

## What Gets Deployed

The bootstrap process provisions a complete Kubernetes cluster:

> **Production Cluster Specification**
> - **Control Planes**: 3 nodes (2 CPU, 5GB RAM, 60GB disk each)
> - **Workers**: 3 nodes (3 CPU, 12GB RAM, 250GB disk each)
> - **Operating System**: Talos Linux v1.13.2
> - **CNI**: Cilium v1.19.3
> - **API Gateway**: Gateway API v1.2.0
> - **Infrastructure**: Proxmox VE with automated VM provisioning

## Prerequisites

### Tools Installed
- [OpenTofu](https://opentofu.org/) or Terraform >= 1.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/) — Kubernetes CLI
- [talosctl](https://www.talos.dev/) — Talos management CLI
- [1Password CLI](https://developer.1password.com/docs/cli/get-started/) — For secrets management

### Infrastructure Access
- Proxmox VE cluster access (API credentials stored in 1Password)
- Hetzner Object Storage bucket for Terraform state storage
- Network access to deployment subnet (10.0.10.0/24)

### 1Password Setup
Credentials must be stored in the **Homelab** vault:
- **Proxmox - Automation Account** item with fields: `username` (automation@pve), `api_key` (API token)
- **hetzner-homelab-prd** item with fields: `username` (access key), `password` (secret key)

> **Note (ADR-025)**: Since 2026-01-12, the homelab uses a dedicated `automation@pve` user instead of root for OpenTofu operations. This provides better security through privilege separation.

## Quick Start

Deploy the cluster in 4 simple steps:

### Step 1: Load Secrets from 1Password

```bash
cd resources/bootstrap

# Sign in to 1Password CLI (if not already signed in)
eval $(op signin)

# Load secrets into environment variables
source ./scripts/load-secrets.sh
```

This script automatically exports:
- `TF_VAR_proxmox_username` (automation@pve since ADR-025)
- `TF_VAR_proxmox_password` (empty — token auth only)
- `TF_VAR_proxmox_api_token` (automation@pve!tofu token)
- `TF_VAR_qdevice_root_password` (for QDevice LXC — ADR-027)
- `AWS_ACCESS_KEY_ID` (Hetzner Object Storage)
- `AWS_SECRET_ACCESS_KEY` (Hetzner Object Storage)

### Step 2: Review Configuration

Check `proxmox.auto.tfvars` for cluster settings:

```hcl
env = "prd"
controlplane_count = 3
worker_count = 3
cluster_cidr = "10.0.10"
ip_offset = 130
cluster_vip = "10.0.10.140"

talos_version = "v1.13.2"
cilium_version = "v1.19.3"
gateway_api_version = "v1.2.0"
```

### Step 3: Initialize and Deploy

```bash
# Initialize Terraform with S3 backend
tofu init

# Preview changes
tofu plan

# Deploy the cluster
tofu apply
```

**Deployment Timeline**: ~15-20 minutes total
- Image download and VM creation: ~7 minutes
- Talos configuration and cluster bootstrap: ~8 minutes
- Health checks and kubeconfig generation: ~5 minutes

### Step 4: Verify and Access

Once deployment completes, verify cluster health:

```bash
# Set environment variables
export KUBECONFIG=$(pwd)/output/kube-config.yaml
export TALOSCONFIG=$(pwd)/output/talos-config.yaml

# Check Kubernetes nodes
kubectl get nodes -o wide

# Check Talos health
talosctl --nodes 10.0.10.130 health

# Verify Cilium CNI
kubectl get pods -n kube-system -l k8s-app=cilium
```

> **Success Indicators**
> - All 6 nodes show STATUS="Ready"
> - Cluster VIP (10.0.10.140) is reachable
> - Cilium pods are Running on all nodes
> - Generated configs in `output/` directory

## Common Troubleshooting

### 1Password CLI Not Authenticated
**Symptom**: `load-secrets.sh` fails with authentication error

```bash
eval $(op signin)
source ./scripts/load-secrets.sh
```

### Terraform State Backend Issues
**Symptom**: `tofu init` fails to connect to S3 backend

**Possible Causes**:
- Hetzner Object Storage credentials not exported
- Bucket `homelab-prd` doesn't exist
- Network connectivity issues

**Solution**: Verify AWS credentials are loaded and bucket exists in Hetzner Cloud Console

### Cluster VIP Not Activating
**Symptom**: Cannot reach 10.0.10.140 after deployment

**Possible Causes**:
- VIP already in use by another device
- VIP not in same subnet as nodes
- Network interface misconfiguration

**Solution**: Check IP availability, verify subnet configuration, review Talos machine configs

### Node Not Joining Cluster
**Symptom**: Node stuck in "NotReady" state

```bash
talosctl -n <node-ip> service kubelet status
talosctl -n <node-ip> dmesg | grep -i error
```

## What Happens Next

After successful bootstrap:
1. **GitOps Setup**: Deploy ArgoCD for continuous deployment
2. **Storage**: Configure Longhorn CSI for persistent volumes
3. **Ingress**: Set up Gateway API and cert-manager for TLS
4. **Monitoring**: Deploy observability stack (Prometheus, Grafana)
5. **Applications**: Install homelab services via ArgoCD

## Key Files Reference

| File | Purpose |
|------|---------|
| `proxmox.auto.tfvars` | Cluster configuration (non-sensitive) |
| `scripts/load-secrets.sh` | 1Password secret loader |
| `output/kube-config.yaml` | Kubernetes cluster access |
| `output/talos-config.yaml` | Talos cluster management |
| `talos/machine-config/` | Talos node templates |
| `talos/inline-manifests/` | Cilium installation job |

## Changelog

### 2026-05-15
- Talos Linux: v1.12.2 → v1.13.2 (rolling upgrade via upgrade-talos.sh)
- Kubernetes: v1.35.0 → v1.36.0 (via talosctl upgrade-k8s)
- Cilium: v1.18.5 → v1.19.3

### 2026-01-12
- **ADR-025**: Updated to use dedicated automation@pve user instead of root
- **ADR-027**: Added TF_VAR_qdevice_root_password for QDevice LXC deployment

### 2025-12-27
- Initial version
