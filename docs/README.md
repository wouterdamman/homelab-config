# 📚 Homelab Documentation

> **Note**: Primary documentation is maintained in Notion for better collaboration and organization.

## 📖 Documentation Location

All homelab documentation is available in the **Homelab** database in Notion:

### Main Documentation
- [Infrastructure Overview](https://www.notion.so/2d3b49ed6b9181ac8474fa2a2be73c1c) - Complete infrastructure stack overview
- [Deployment Plan](https://www.notion.so/2d3b49ed6b918145be33fa54e2e417bb) - Production cluster deployment guide
- [S3 Backend Setup](https://www.notion.so/2d3b49ed6b9181b3b6bfe2760e755dc9) - Backblaze B2 configuration
- [Talos Upgrade Procedure](https://www.notion.so/2d6b49ed6b91813ebe8bd18f4fb7a150) - Automated rolling upgrade guide
- [Networking Stack](https://www.notion.so/2d3b49ed6b9181d0a118de59312eadd0) - UniFi network configuration

## 🔧 Local Development Documentation

The following docs remain local as they contain development-specific information:

- [1Password Connect](./generate-1password-credentials.md) - Generate 1Password Connect credentials for External Secrets Operator
- [Secrets Management](./secrets.md) - Overview of secrets management using External Secrets Operator and 1Password Connect
- [TODOs](./todo.md) - Development tasks and ideas

## 🚀 Quick Start

1. **Deploy Cluster**: Follow the [Deployment Plan](https://www.notion.so/2d3b49ed6b918145be33fa54e2e417bb) in Notion
2. **Configure S3 Backend**: See [S3 Backend Setup](https://www.notion.so/2d3b49ed6b9181b3b6bfe2760e755dc9)
3. **Upgrade Talos**: Use the automated script from [Talos Upgrade Procedure](https://www.notion.so/2d6b49ed6b91813ebe8bd18f4fb7a150)

## 📁 Repository Structure

```
homelab-config/
├── resources/
│   ├── bootstrap/          # OpenTofu for VMs + Talos cluster
│   │   ├── scripts/        # Automation scripts
│   │   │   └── upgrade-talos.sh    # Automated Talos upgrade
│   │   ├── talos/          # Talos module
│   │   ├── output/         # Generated configs (gitignored)
│   │   └── *.tf            # Terraform/OpenTofu configuration
│   └── gitops-config/      # ArgoCD apps + operators
└── docs/                   # Documentation (see Notion for primary docs)
```

## 🔗 External Links

- [Talos Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Backblaze B2 Documentation](https://www.backblaze.com/b2/docs/)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
