# 🏡 Homelab Infrastructure

Infrastructure-as-Code and GitOps configuration for a production-grade homelab running on Proxmox with Talos Kubernetes.

## 📚 Documentation

**All documentation is maintained in Notion for better collaboration and organization.**

### Quick Links

- **[Homelab Database](https://www.notion.so/2d3b49ed6b91808e915de47613e29b3e)** - Main documentation hub
- **[Cluster Deployment - Bootstrap](https://www.notion.so/2d6b49ed6b9181b391cdca0718ee06c4)** - How to deploy the cluster
- **[Infrastructure Overview](https://www.notion.so/2d3b49ed6b9181ac8474fa2a2be73c1c)** - Complete stack overview
- **[Secrets Management - 1Password](https://www.notion.so/2d6b49ed6b9181b0b331f641f915b5b5)** - How credentials are managed
- **[Deployment Plan](https://www.notion.so/2d3b49ed6b918145be33fa54e2e417bb)** - Production deployment guide

## 🚀 Quick Start

1. **Prerequisites**: Install OpenTofu, kubectl, talosctl, and 1Password CLI
2. **Load Secrets**: `source resources/bootstrap/scripts/load-secrets.sh`
3. **Deploy**: `cd resources/bootstrap && tofu apply`
4. **Verify**: `kubectl get nodes`

See [Cluster Deployment - Bootstrap](https://www.notion.so/2d6b49ed6b9181b391cdca0718ee06c4) for detailed instructions.

## 🗂️ Repository Structure

```
├── resources/
│   ├── bootstrap/          # OpenTofu for VMs + Talos cluster
│   │   ├── scripts/        # Automation scripts (1Password, upgrades)
│   │   ├── talos/          # Talos module
│   │   └── README.md       # Technical reference
│   └── gitops-config/      # ArgoCD apps + operators
└── docs/                   # Development-specific docs
```

## 🔧 Tech Stack

- **Infrastructure**: Proxmox VE
- **Kubernetes**: Talos Linux v1.12.0
- **Networking**: Cilium v1.18.5 + Gateway API v1.2.0
- **GitOps**: ArgoCD
- **IaC**: OpenTofu/Terraform
- **Secrets**: 1Password CLI
- **Storage**: Backblaze B2 (Terraform state)

## 📖 Local Documentation

Some development-specific docs remain in this repo:

- [resources/bootstrap/README.md](resources/bootstrap/README.md) - Technical implementation details
- [docs/generate-1password-credentials.md](docs/generate-1password-credentials.md) - 1Password Connect setup
- [docs/secrets.md](docs/secrets.md) - Secrets management patterns
- [docs/todo.md](docs/todo.md) - Development tasks

For all other documentation, see the [Homelab Database in Notion](https://www.notion.so/2d3b49ed6b91808e915de47613e29b3e).

## 🤝 Contributing

Issues and pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.

## 📄 License

[MIT License](./LICENSE)
