# Secrets Management - 1Password

Comprehensive guide to managing secrets securely across the homelab infrastructure using 1Password CLI integration.

## Overview

This homelab uses **1Password** as the single source of truth for all sensitive credentials. Secrets are never stored in version control or configuration files — they are loaded dynamically at deployment time via the 1Password CLI.

> **Security Philosophy**
> Secrets exist in exactly one place: 1Password vault "Homelab".
> All infrastructure tools (OpenTofu, kubectl, scripts) fetch credentials at runtime using environment variables populated from 1Password.

## Why 1Password CLI?

### Benefits
- **Single Source of Truth:** All credentials centralized in encrypted vault
- **No Secrets in Git:** Zero risk of accidentally committing credentials
- **Audit Trail:** 1Password logs all secret access
- **Team Sharing:** Easy credential sharing with collaborators
- **Rotation Ready:** Update credentials in one place, no file edits needed
- **Cross-Platform:** Works on macOS, Linux, Windows

### Trade-offs
- Requires 1Password subscription
- Team members need 1Password CLI installed
- Adds dependency on 1Password infrastructure
- Requires manual sign-in for CLI sessions

## 1Password Setup

### Install 1Password CLI

```bash
# macOS
brew install 1password-cli

# Verify installation
op --version
```

### Sign In

```bash
# Interactive sign-in
eval $(op signin)

# Verify authentication
op whoami
```

## Vault Structure

All homelab secrets are stored in the **Homelab** vault:

| Item Name | Field Name | Description |
|-----------|-----------|-------------|
| Proxmox - Root Account | username | Proxmox root user (root@pam) |
| Proxmox - Root Account | password | Proxmox root password |
| Proxmox - Root Account | api_key | Proxmox API token |
| Backblaze-homelab-prd | username | Backblaze B2 Key ID |
| Backblaze-homelab-prd | credential | Backblaze B2 Application Key |

**Proxmox Credentials (ADR-025):**

| Item Name | Field Name | Description |
|-----------|-----------|-------------|
| Proxmox - Automation Account | username | automation@pve |
| Proxmox - Automation Account | api_key | API token (automation@pve!tofu=\<secret\>) |
| Proxmox - Monitoring Account | username | monitoring@pve |
| Proxmox - Monitoring Account | password | Password for monitoring@pve |
| Proxmox QDevice - Root Password | password | Root password for QDevice LXC |

## Using Secrets in Deployment

### Automated Loading with load-secrets.sh

```bash
cd resources/bootstrap

# Load all secrets into environment
source ./scripts/load-secrets.sh
```

**Environment variables exported:**

```bash
TF_VAR_proxmox_username      # For Proxmox provider
TF_VAR_proxmox_password      # For Proxmox provider
TF_VAR_proxmox_api_token     # For Proxmox provider
AWS_ACCESS_KEY_ID            # For S3 backend (Hetzner Object Storage)
AWS_SECRET_ACCESS_KEY        # For S3 backend (Hetzner Object Storage)
```

### Manual Secret Access

```bash
# Read a single secret
op read "op://Homelab/Proxmox/username"

# Use in a command
export MY_SECRET=$(op read "op://Homelab/Proxmox/api_token")
```

## Security Best Practices

### Do's
- ✅ Always use `source` to load secrets (never execute the script)
- ✅ Store ALL sensitive data in 1Password
- ✅ Keep 1Password CLI updated
- ✅ Enable 2FA on 1Password account
- ✅ Use Secret References in documentation (e.g., `op://Homelab/...`)
- ✅ Rotate credentials every 90 days

### Don'ts
- ❌ Never commit `.env` files
- ❌ Never hardcode credentials in `.tf` or `.tfvars` files
- ❌ Never share credentials via chat/email
- ❌ Never store secrets in plaintext files

## Troubleshooting

### "Please sign in to 1Password first"
```bash
eval $(op signin)
```

### "Item not found" errors
1. Verify item exists: `op item list --vault Homelab`
2. Check field names: `op item get "Proxmox" --vault Homelab --fields label`
3. Update `load-secrets.sh` with correct references

### Environment variables not persisting
```bash
# Wrong (creates subshell)
./scripts/load-secrets.sh

# Correct (runs in current shell)
source ./scripts/load-secrets.sh
```

---

## External Secrets Operator Integration

For Kubernetes workloads, secrets are managed via **External Secrets Operator (ESO)** integrated with **1Password Connect**.

### Components

| Component | Purpose |
|-----------|---------|
| **External Secrets Operator** | Syncs secrets from 1Password into Kubernetes Secrets |
| **1Password Connect** | Lightweight service deployed in-cluster for secure secret retrieval |
| **ClusterSecretStore** | Cluster-wide configuration pointing to 1Password Connect |
| **ExternalSecret** | Per-namespace secret definitions that reference 1Password items |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    1Password Cloud                          │
│                   (KubernetesSecrets Vault)                │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                          │
│  ┌────────────────────┐     ┌─────────────────────────────┐ │
│  │  1Password Connect │────▶│  External Secrets Operator  │ │
│  │  (onepassword ns)  │     │  (external-secrets ns)      │ │
│  └────────────────────┘     └──────────────┬──────────────┘ │
│                                            │                 │
│                                            ▼                 │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Kubernetes Secrets                         ││
│  │  - argocd/github-private-repo-creds                     ││
│  │  - longhorn-system/longhorn-s3-secret                   ││
│  └─────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
```

### 1Password Connect Setup

#### Step 1: Create Connect Server Credentials
1. Go to [1Password Developer Console](https://developer.1password.com/)
2. Click **Integrations** → **Infrastructure Secrets Management**
3. Click **Create Connect Server**
4. Download the generated `1password-credentials.json`
5. Copy the access token (shown only once!)

#### Step 2: Store Credentials in 1Password

Store both credentials in the **KubernetesSecrets** vault:

| Item Name | Field | Content |
|-----------|-------|---------|
| `op-connect-credentials` | `password` | Full JSON content from downloaded file |
| `op-connect-token` | `credential` | Access token string |

#### Step 3: Bootstrap Deployment

The GitOps bootstrap process automatically:
1. Creates `onepassword` and `external-secrets` namespaces
2. Deploys 1Password Connect via Helm
3. Deploys External Secrets Operator via Helm
4. Creates ClusterSecretStore pointing to Connect

### Example: ArgoCD GitHub Credentials

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-private-repo-creds
  namespace: argocd
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: github-private-repo-creds
    creationPolicy: Owner
    template:
      type: Opaque
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repository
      data:
        type: git
        url: https://github.com/your-org/homelab-config
        githubAppID: "{{ .appId }}"
        githubAppInstallationID: "{{ .installationId }}"
        githubAppPrivateKey: '{{ .privateKey }}'
  data:
  - secretKey: appId
    remoteRef:
      key: github-argo-app
      property: app-id
  - secretKey: installationId
    remoteRef:
      key: github-argo-app
      property: installation-id
  - secretKey: privateKey
    remoteRef:
      key: github-argo-app
      property: private-key
```

### Verifying Setup

```bash
# Check 1Password Connect is running
kubectl get pods -n onepassword

# Check External Secrets Operator is running
kubectl get pods -n external-secrets

# Check ClusterSecretStore status
kubectl get clustersecretstore

# Check ExternalSecret sync status
kubectl get externalsecret -A

# Verify secrets are created
kubectl get secrets -n argocd
```

### Troubleshooting ESO

**ExternalSecret shows "SecretSyncedError":**
```bash
# Check 1Password item exists
op item get "github-argo-app" --vault KubernetesSecrets

# Verify field names
op item get "github-argo-app" --vault KubernetesSecrets --format json | jq '.fields[].label'
```

**1Password Connect pod crashes:**
1. Regenerate credentials in 1Password Developer Console
2. Update `op-connect-credentials` item in 1Password
3. Delete and recreate the bootstrap secret:
```bash
kubectl delete secret op-credentials -n onepassword
cd resources/gitops-config && tofu apply
```
