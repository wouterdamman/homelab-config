# GitOps Deployment - ArgoCD Bootstrap

## Overview

The GitOps bootstrap solves the **chicken-and-egg problem** of deploying ArgoCD with secure GitHub access.

## The Problem

1. ArgoCD needs GitHub credentials to sync private repositories
2. GitHub credentials should be managed by External Secrets Operator (ESO)
3. ESO needs 1Password Connect to fetch secrets
4. But ArgoCD should manage both 1Password and ESO via GitOps

## The Solution

**Two-Phase Deployment:**

### Phase 1: Terraform Bootstrap (One-time)

Terraform deploys the minimal stack to break the circular dependency:

1. Create namespaces (onepassword, external-secrets, argocd, longhorn-system)
2. Deploy 1Password Connect credentials secret
3. Install 1Password Connect (Helm)
4. Install External Secrets Operator (Helm)
5. Create ClusterSecretStore (connects ESO to 1Password)
6. Deploy ExternalSecrets for GitHub credentials
7. Install ArgoCD (Helm) — can now access GitHub
8. Install ArgoCD Apps/Projects (Helm)
9. Deploy sync-app (root ArgoCD Application)

### Phase 2: ArgoCD Takes Over (GitOps)

Sync-app deploys ArgoCD Applications that manage:
- **Wave 0**: Longhorn, Cilium (infrastructure)
- **Wave 1**: 1Password Connect (replaces Terraform deployment)
- **Wave 2**: External Secrets (replaces Terraform deployment)
- **Wave 3**: Cert-manager, External-DNS
- ArgoCD itself (self-management)

## Prerequisites

### Required Tools
- OpenTofu or Terraform >= 1.0
- kubectl
- 1Password CLI

### Required Access
- Kubernetes cluster with kubeconfig (from bootstrap step)
- 1Password Connect credentials in **KubernetesSecrets** vault
- GitHub App credentials in **KubernetesSecrets** vault
- Hetzner Object Storage credentials in **Homelab** vault (for S3 backend)

### Cluster Requirements
- Talos Kubernetes cluster must be running
- Cilium CNI must be installed (via bootstrap)
- Gateway API CRDs must be present

## Deployment Steps

### Step 1: Generate Input Files

Automatically generate all input-files from 1Password:

```bash
cd resources/gitops-config

# Ensure you're signed in to 1Password CLI
eval $(op signin)

# Generate all input-files
./scripts/generate-input-files.sh
```

**Required secrets in 1Password "KubernetesSecrets" vault:**
- `op-connect-credentials` — 1Password Connect credentials JSON
- `op-connect-token` — 1Password Connect access token
- `github-client-secrets` — GitHub OAuth client secret (for ArgoCD SSO)
- `github-argo-app` — GitHub App credentials (for repo access)
- `longhorn-s3-backup` — Hetzner Object Storage credentials (for Longhorn backups)

### Step 2: Load S3 Credentials

```bash
source ./scripts/load-secrets.sh
```

### Step 3: Configure Kubeconfig

```bash
export TF_VAR_kube_config_path="$(pwd)/../bootstrap/output/kube-config.yaml"
```

### Step 4: Deploy GitOps Stack

```bash
tofu init
tofu plan
tofu apply

kubectl -n argocd get pods
kubectl -n argocd get applications
```

## Post-Deployment

### Access ArgoCD UI

**Get initial admin password:**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Port forward to ArgoCD:**

```bash
kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443
```

Then open: https://localhost:8080

### Verify Sync Status

```bash
kubectl -n argocd get applications
```

**Expected applications:**
- `sync-app` — Root application (App of Apps pattern)
- `longhorn` — Distributed block storage with S3 backups
- `cilium` — CNI and network policies
- `onepassword` — 1Password Connect server
- `external-secrets` — External Secrets Operator
- `cert-manager` — TLS certificate management
- `external-dns` — DNS record automation
- `argocd` — Self-managed ArgoCD
- `argocd-apps` — ArgoCD ApplicationSets and Projects

## Troubleshooting

### 1Password Connect Not Starting

```bash
kubectl -n onepassword get secret onepassword-connect-credentials
```

If missing, verify `input-files/secret.yaml` was generated correctly.

### External Secrets Not Syncing

```bash
kubectl get clustersecretstore onepassword-connect -o yaml
```

**Common issues:**
- 1Password Connect not ready
- Wrong credentials in secret
- Network connectivity to 1Password service

### ArgoCD Can't Access GitHub

```bash
kubectl -n argocd get externalsecret github-private-config-creds -o yaml
kubectl -n argocd get secret github-private-config-creds
```

**Verify:**
- ClusterSecretStore is ready
- 1Password item references are correct in KubernetesSecrets vault
- GitHub App has correct permissions (repo read)

### Sync-App Not Deploying

```bash
kubectl -n argocd get application sync-app
```

If missing, check Terraform null_resource:

```bash
tofu state list | grep deploy_root_app
```

## Configuration

### Versions

Default versions (can be overridden in `terraform.tfvars`):
- 1Password Connect: 2.1.1
- External Secrets: 2.4.1
- ArgoCD: 9.5.14 (app v3.4.2)
- ArgoCD Apps: 2.0.3

### Customization

```hcl
kube_config_path         = "../bootstrap/output/kube-config.yaml"
onepassword_version      = "2.1.1"
external_secrets_version = "2.4.1"
argocd_version           = "9.5.14"
```

## Changelog

### 2026-05-15
- External Secrets Operator: 1.2.1 → 2.4.1
- ArgoCD: chart 9.2.4 → 9.5.14 (app v3.4.2)

### 2026-01-09
- Updated versions: 1Password Connect 2.1.1, External Secrets 1.2.1, ArgoCD 9.2.4

### 2025-12-28
- Initial version
