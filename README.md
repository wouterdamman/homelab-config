# Homelab Infrastructure

Infrastructure-as-Code and GitOps configuration for a production-grade homelab running on Proxmox with Talos Kubernetes.

## Documentation

**All documentation is maintained in Notion for better collaboration and organization.**

### Quick Links

- **[Homelab Database](https://www.notion.so/2d3b49ed6b91808e915de47613e29b3e)** - Main documentation hub
- **[Infrastructure Overview](https://www.notion.so/2d3b49ed6b9181ac8474fa2a2be73c1c)** - Complete stack overview
- **[Cluster Deployment - Bootstrap](https://www.notion.so/2d6b49ed6b9181b391cdca0718ee06c4)** - How to deploy the cluster
- **[GitOps Deployment - ArgoCD Bootstrap](https://www.notion.so/2d7b49ed6b91816dbb9cc3cdab067eeb)** - ArgoCD & operators setup
- **[Secrets Management - 1Password](https://www.notion.so/2d6b49ed6b9181b0b331f641f915b5b5)** - How credentials are managed
- **[Longhorn DR Runbook](https://www.notion.so/2d7b49ed6b918115a374db661adfce74)** - Disaster recovery procedures

## Quick Start

1. **Prerequisites**: Install OpenTofu, kubectl, talosctl, and 1Password CLI
2. **Load Secrets**: `source resources/bootstrap/scripts/load-secrets.sh`
3. **Deploy**: `cd resources/bootstrap && tofu apply`
4. **Verify**: `kubectl get nodes`

See [Cluster Deployment - Bootstrap](https://www.notion.so/2d6b49ed6b9181b391cdca0718ee06c4) for detailed instructions.

## Repository Structure

```
homelab-config/
├── resources/
│   ├── bootstrap/              # OpenTofu for VMs + Talos cluster
│   │   ├── scripts/            # Automation scripts (1Password, upgrades)
│   │   ├── talos/              # Talos module
│   │   └── README.md           # Technical reference
│   └── gitops-config/          # ArgoCD apps + operators
│       ├── operators/          # Longhorn, Cilium, External Secrets
│       ├── apps/               # ArgoCD application definitions
│       ├── scripts/            # Helper scripts
│       └── README.md           # Technical reference
└── docs/                       # Documentation index (links to Notion)
```

## Tech Stack

| Component | Technology | Version |
|-----------|------------|---------|
| **Virtualization** | Proxmox VE | Latest |
| **Kubernetes** | Talos Linux | v1.13.2 |
| **Kubernetes** | Kubernetes | v1.36.0 |
| **Networking** | Cilium + Gateway API | v1.19.3 |
| **GitOps** | ArgoCD | v3.4.2 |
| **Storage** | Longhorn | v1.11.2 |
| **IaC** | OpenTofu | Latest |
| **Secrets** | 1Password + External Secrets | Latest |
| **Backup** | Hetzner Object Storage | - |

## Key Features

- **GitOps-driven**: All cluster state managed through ArgoCD
- **Secure secrets**: 1Password integration via External Secrets Operator
- **Production storage**: Longhorn with S3 backups to Hetzner Object Storage
- **3-tier storage**: Fast (3 replicas), Standard (2 replicas), Archive (1 replica)
- **Automated DR**: Backup validation and restore testing scripts
- **Infrastructure as Code**: Full cluster reproducibility via OpenTofu

## Local Documentation

Technical implementation details are kept in-repo:

- [resources/bootstrap/README.md](resources/bootstrap/README.md) - Talos cluster bootstrap
- [resources/gitops-config/README.md](resources/gitops-config/README.md) - ArgoCD and operators
- [docs/README.md](docs/README.md) - Documentation index with all Notion links

## License

[MIT License](./LICENSE)
