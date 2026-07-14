# Homelab Infrastructure

Infrastructure-as-Code and GitOps configuration for a production-grade homelab running on Proxmox with Talos Kubernetes.

## Documentation

Full documentation lives in [`docs/`](docs/README.md).

### Quick Links

- **[docs/README.md](docs/README.md)** — Full documentation index
- **[Architecture](docs/architecture/high-level-design.md)** — System overview and design decisions
- **[Bootstrap](docs/bootstrap/cluster-deployment.md)** — How to deploy the cluster
- **[Secrets Management](docs/bootstrap/secrets-management.md)** — 1Password → ESO → Kubernetes
- **[Longhorn DR Runbook](docs/operators/longhorn-dr-runbook.md)** — Disaster recovery procedures

## Quick Start

1. **Prerequisites**: Install OpenTofu, kubectl, talosctl, and 1Password CLI
2. **Load Secrets**: `source resources/bootstrap/scripts/load-secrets.sh`
3. **Deploy**: `cd resources/bootstrap && tofu apply`
4. **Verify**: `kubectl get nodes`

See [Cluster Deployment](docs/bootstrap/cluster-deployment.md) for detailed instructions.

## Repository Structure

```
homelab-config/
├── resources/
│   ├── bootstrap/              # OpenTofu for VMs + Talos cluster
│   │   ├── scripts/            # Automation scripts (1Password, upgrades)
│   │   ├── talos/              # Talos module
│   │   └── README.md           # Technical reference
│   ├── gitops-config/          # ArgoCD apps + operators
│   │   ├── operators/          # Longhorn, Cilium, External Secrets, ...
│   │   ├── applications/       # User-facing apps (Home Assistant, EVCC, ...)
│   │   ├── sync-app/           # Root App-of-Apps chart
│   │   ├── scripts/            # Helper scripts
│   │   └── README.md           # Technical reference
│   └── infrastructure/         # Proxmox-level infra (QDevice LXC)
└── docs/                       # Full documentation (architecture, operators, apps)
```

## Tech Stack

| Component | Technology | Version |
|-----------|------------|---------|
| **Virtualization** | Proxmox VE | Latest |
| **Kubernetes** | Talos Linux | v1.13.6 |
| **Kubernetes** | Kubernetes | v1.36.2 |
| **Networking** | Cilium + Gateway API | v1.19.5 |
| **GitOps** | ArgoCD | v3.4.5 |
| **Storage** | Longhorn | v1.12.0 |
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
- **Secret hygiene**: gitleaks scanning (pre-commit, CI, and GitHub push protection); no secrets in git — everything flows through 1Password

## Local Documentation

- [docs/README.md](docs/README.md) — Full documentation index
- [resources/bootstrap/README.md](resources/bootstrap/README.md) — Talos bootstrap technical reference
- [resources/gitops-config/README.md](resources/gitops-config/README.md) — ArgoCD and operators reference

## License

[MIT License](./LICENSE)
