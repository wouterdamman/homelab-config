# Infrastructure Workspace

This Terraform/OpenTofu workspace manages Proxmox infrastructure components that are separate from the Talos cluster bootstrap.

## Contents

- **QDevice LXC Container** - External quorum arbiter for 2-node Proxmox cluster (VM ID: 200)

## Prerequisites

1. **1Password CLI** - For loading secrets
2. **OpenTofu** - Infrastructure as Code tool
3. **Proxmox automation user** - With appropriate permissions

## Setup

1. **Sign in to 1Password CLI**:
   ```bash
   eval $(op signin)
   ```

2. **Load secrets from 1Password**:
   ```bash
   source ../bootstrap/scripts/load-secrets.sh
   ```

3. **Initialize Terraform**:
   ```bash
   tofu init
   ```

4. **Copy example tfvars**:
   ```bash
   cp terraform.tfvars.example terraform.auto.tfvars
   # Edit terraform.auto.tfvars with your values
   ```

## Deployed Resources

### QDevice LXC Container (VM ID: 200)
- **IP**: 10.0.10.202
- **Purpose**: External quorum arbiter for 2-node Proxmox cluster
- **Resources**: 1 CPU core, 512MB RAM, 2GB disk
- **Template**: Debian 12 standard
- **Service**: corosync-qnetd for cluster quorum voting

## Usage

```bash
# Load secrets from 1Password
source ../bootstrap/scripts/load-secrets.sh

# Initialize workspace
tofu init

# Plan changes
tofu plan

# Apply changes
tofu apply
```

## Deployed Resources

- **QDevice LXC Container (VM ID 200)**
  - IP: 10.0.10.202
  - Purpose: External quorum device for 2-node Proxmox cluster
  - Service: corosync-qnetd
