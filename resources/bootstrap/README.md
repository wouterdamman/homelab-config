# Bootstrap - Talos Kubernetes Cluster Infrastructure

This directory contains OpenTofu/Terraform configuration for bootstrapping a Talos Kubernetes cluster on Proxmox VE.

## Overview

The bootstrap configuration:
- Creates Proxmox VMs for Kubernetes nodes (control plane + workers)
- Generates Talos machine configurations
- Bootstraps the Talos Kubernetes cluster
- Installs Cilium CNI via inline manifests
- Deploys Gateway API CRDs
- Outputs kubeconfig and Talos client configuration

## Architecture

```
├── *.tf                    # Root Terraform configuration
├── proxmox.auto.tfvars     # Configuration values (non-sensitive)
├── .env.example            # Template for sensitive environment variables
├── talos/                  # Talos module (local)
│   ├── config.tf           # Talos cluster & machine configurations
│   ├── image.tf            # Talos image schematic & downloads
│   ├── virtual-machines.tf # Proxmox VM resources
│   ├── image/              # Talos system extensions
│   ├── inline-manifests/   # Cilium install job
│   └── machine-config/     # Talos config templates
├── scripts/                # Automation scripts
│   └── upgrade-talos.sh    # Rolling upgrade automation
└── output/                 # Generated configs (gitignored)
```

## Prerequisites

### Required Tools

- [OpenTofu](https://opentofu.org/) or Terraform >= 1.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/)

### Required Access

- Proxmox VE cluster access (username + password/API token)
- Hetzner Object Storage bucket for S3 backend (or alternative S3-compatible storage)
- SSH access to Proxmox nodes (for VM provisioning)

## Quick Start

### 1. Set Environment Variables

#### Option A: Using 1Password (Recommended)

Load secrets directly from 1Password using the provided script:

```bash
# Ensure you're signed in to 1Password CLI
eval $(op signin)

# Load secrets into environment
source ./scripts/load-secrets.sh
```

**Prerequisites:**
- Install [1Password CLI](https://developer.1password.com/docs/cli/get-started/)
- Store credentials in 1Password with these references:
  - `op://Homelab/Proxmox/username`
  - `op://Homelab/Proxmox/password`
  - `op://Homelab/Proxmox/api_token`
  - `op://Homelab/hetzner-homelab-prd/username`
  - `op://Homelab/hetzner-homelab-prd/password`

Adjust item names in `scripts/load-secrets.sh` to match your 1Password vault structure.

#### Option B: Using .env File

Copy the example environment file and fill in your credentials:

```bash
cp .env.example .env
# Edit .env with your actual credentials
source .env
```

Required environment variables:
```bash
export TF_VAR_proxmox_username="root@pam"
export TF_VAR_proxmox_password="your-password"
export TF_VAR_proxmox_api_token="root@pam!tofu=your-token"

export AWS_ACCESS_KEY_ID="your-hetzner-access-key"
export AWS_SECRET_ACCESS_KEY="your-hetzner-secret-key"
```

### 2. Configure Cluster Settings

Edit `proxmox.auto.tfvars` to customize your cluster:

```hcl
# Environment
env = "prd"  # or "tst"

# Node counts
controlplane_count = 3
worker_count       = 3

# Networking
cluster_cidr  = "10.0.10"
ip_offset     = 130
cluster_vip   = "10.0.10.140"
cluster_gateway = "10.0.10.193"

# Node specifications
controlplane_specs = {
  cpu  = 2
  ram  = 4096  # MB
  disk = 60    # GB
}

worker_specs = {
  cpu  = 3
  ram  = 10240  # MB
  disk = 250    # GB
}

# Versions
talos_version  = "v1.13.2"
cilium_version = "v1.19.3"
gateway_api_version = "v1.1.0"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform with S3 backend
tofu init

# Review the plan
tofu plan

# Deploy the cluster
tofu apply

# Wait for cluster to be ready (~5-10 minutes)
```

### 4. Access the Cluster

Generated configurations are written to `output/`:

```bash
# Use generated kubeconfig
export KUBECONFIG=$(pwd)/output/kube-config.yaml
kubectl get nodes

# Use generated Talos config
export TALOSCONFIG=$(pwd)/output/talos-config.yaml
talosctl health --nodes <node-ip>
```

## Configuration Details

### IP Addressing

Nodes receive sequential IPs based on:
- `cluster_cidr`: First three octets (e.g., "10.0.10")
- `ip_offset`: Starting fourth octet (e.g., 130)

**Example with offset 130:**
- prd-cp-01: 10.0.10.130
- prd-cp-02: 10.0.10.131
- prd-cp-03: 10.0.10.132
- prd-w-01: 10.0.10.133
- prd-w-02: 10.0.10.134
- prd-w-03: 10.0.10.135

### Node Specifications

Separate specs for control plane and worker nodes:

**Control Plane (default):**
- CPU: 2 cores
- RAM: 4 GB
- Disk: 60 GB

**Workers (default):**
- CPU: 3 cores
- RAM: 10 GB
- Disk: 250 GB

### Talos Schematic

The Talos image includes these system extensions (see `talos/image/schematic.yaml`):
- iscsi-tools (for Longhorn/persistent storage)
- qemu-guest-agent (for Proxmox integration)
- util-linux-tools (general utilities)

### Cilium Configuration

Cilium is installed via a Kubernetes Job during cluster bootstrap:
- Version: Parametrized via `cilium_version` variable
- Values: Loaded from `../gitops-config/operators/cilium/values.yaml`
- Features: Gateway API, L2 announcements, Hubble observability

## Upgrading Talos

### Automated Rolling Upgrade

Use the provided script for safe, automated rolling upgrades:

```bash
cd scripts/

# Dry-run to see what would happen
./upgrade-talos.sh --current v1.13.2 --target v1.13.0 --dry-run

# Perform the upgrade (workers first, then control planes)
./upgrade-talos.sh --current v1.13.2 --target v1.13.0

# Skip workers (upgrade only control planes)
./upgrade-talos.sh --current v1.13.2 --target v1.13.0 --skip-workers

# Custom wait times between nodes
./upgrade-talos.sh \\
  --current v1.13.2 \\
  --target v1.13.0 \\
  --worker-wait 600 \\    # 10 min between workers
  --cp-wait 900           # 15 min between CPs
```

### Manual Upgrade

If you prefer manual control:

1. Update `talos_version` in `proxmox.auto.tfvars`
2. Update `talos_update_version` if needed
3. Set `nodes_to_upgrade = ["prd-w-01", "prd-cp-01"]`
4. Apply: `tofu apply`
5. Monitor: `kubectl get nodes -w`
6. Repeat for remaining nodes

## Scaling

### Adding Worker Nodes

```hcl
# In proxmox.auto.tfvars
worker_count = 4  # Increase from 3 to 4
```

Then apply:
```bash
tofu apply
```

### Adding Control Plane Nodes

```hcl
# In proxmox.auto.tfvars
controlplane_count = 5  # Increase from 3 to 5 (must be odd number)
```

**Important:** Update VIP if adding nodes to avoid IP conflicts.

### Removing Nodes

1. Drain the node:
   ```bash
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```

2. Update count in `proxmox.auto.tfvars`

3. Apply:
   ```bash
   tofu apply
   ```

## Troubleshooting

### VIP Not Coming Active

If the cluster VIP doesn't activate:
- Ensure `cluster_vip` is in the same subnet as nodes
- Check that VIP is not already in use
- Verify network interface configuration in templates

### Cilium Not Installing

Check the cilium-install job:
```bash
kubectl -n kube-system logs -l app=cilium-install
```

Common issues:
- Incorrect Cilium version specified
- Missing cilium values.yaml file
- Network connectivity to quay.io

### Node Not Joining Cluster

Check Talos service status:
```bash
talosctl -n <node-ip> service kubelet status
talosctl -n <node-ip> dmesg | grep -i error
```

### S3 Backend Issues

If `tofu init` fails with S3 errors:
- Verify AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set
- Check bucket exists in Hetzner Object Storage
- Confirm endpoint URL is correct for your region

## State Management

### S3 Backend

State is stored in Hetzner Object Storage (S3-compatible):
- Bucket: `homelab-prd`
- Key: `tofu/bootstrap.tfstate`
- Region: `nbg1`
- Endpoint: `https://nbg1.your-objectstorage.com`

### Local Testing

To test with local backend, comment out the `backend "s3"` block in `providers.tf`.

## Security Considerations

### Credentials

- **Never commit** `.env` file (it's gitignored)
- **Never commit** credentials to `proxmox.auto.tfvars`
- Use environment variables for all sensitive data
- Rotate Proxmox API tokens regularly

### Network Security

- Ensure Proxmox management network is isolated
- Use firewall rules to restrict access to cluster VIP
- Consider VPN for kubectl/talosctl access

## Files Reference

### Core Configuration Files

| File | Purpose |
|------|---------|
| `providers.tf` | Provider config, S3 backend, version constraints |
| `variables.tf` | Variable declarations with validation |
| `proxmox.auto.tfvars` | Configuration values (non-sensitive) |
| `locals.tf` | Computed values and node configuration |
| `main.tf` | Root module calling Talos module |
| `output.tf` | Output definitions for configs |

### Talos Module Files

| File | Purpose |
|------|---------|
| `talos/config.tf` | Talos machine configs and cluster bootstrap |
| `talos/image.tf` | Schematic resolution and image download |
| `talos/virtual-machines.tf` | Proxmox VM provisioning |
| `talos/variables.tf` | Module variable declarations |
| `talos/output.tf` | Module outputs |

### Templates

| File | Purpose |
|------|---------|
| `talos/machine-config/control-plane.yaml.tftpl` | Talos config for control plane nodes |
| `talos/machine-config/worker.yaml.tftpl` | Talos config for worker nodes |
| `talos/inline-manifests/cilium-install.yaml.tftpl` | Cilium installation job |
| `talos/image/schematic.yaml` | Talos system extensions definition |

## Variables Reference

### Required Variables (in proxmox.auto.tfvars)

- `env`: Environment identifier ("prd" or "tst")
- `controlplane_count`: Number of control plane nodes
- `worker_count`: Number of worker nodes
- `base_vm_id`: Starting VM ID for Proxmox
- `cluster_cidr`: IP prefix (e.g., "10.0.10")
- `ip_offset`: IP starting offset (1-254)
- `host_nodes`: List of Proxmox node names
- `proxmox`: Proxmox cluster configuration
- `talos_version`: Talos OS version (e.g., "v1.13.2")
- `talos_schematic_path`: Path to schematic.yaml
- `cilium_install_path`: Path to Cilium install manifest
- `cilium_values_path`: Path to Cilium values file
- `cluster_name`: Kubernetes cluster name
- `cluster_gateway`: Network gateway IP
- `proxmox_cluster`: Proxmox cluster name
- `cluster_vip`: Kubernetes control plane VIP
- `kube_config_path`: Path for kubeconfig output

### Optional Variables

- `cilium_version`: Cilium version (default: "v1.18.5")
- `gateway_api_version`: Gateway API CRD version (default: "v1.1.0")
- `talos_update_version`: Target version for upgrades
- `nodes_to_upgrade`: List of nodes to upgrade
- `controlplane_specs`: Control plane resource specs
- `worker_specs`: Worker resource specs

### Environment Variables (required)

- `TF_VAR_proxmox_username`: Proxmox username
- `TF_VAR_proxmox_password`: Proxmox password
- `TF_VAR_proxmox_api_token`: Proxmox API token
- `AWS_ACCESS_KEY_ID`: S3 backend access key
- `AWS_SECRET_ACCESS_KEY`: S3 backend secret key

## Additional Resources

- [Talos Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Proxmox Provider Documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Talos Provider Documentation](https://registry.terraform.io/providers/siderolabs/talos/latest/docs)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
