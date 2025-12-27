# 📚 Homelab Documentation

> **All primary documentation is maintained in Notion.**

## 📖 Main Documentation (Notion)

Access the complete homelab documentation in the **[Homelab Database](https://www.notion.so/2d3b49ed6b91808e915de47613e29b3e)**:

### Infrastructure & Deployment
- **[Cluster Deployment - Bootstrap](https://www.notion.so/2d6b49ed6b9181b391cdca0718ee06c4)** - Complete deployment guide
- **[Infrastructure Overview](https://www.notion.so/2d3b49ed6b9181ac8474fa2a2be73c1c)** - Stack overview
- **[Deployment Plan](https://www.notion.so/2d3b49ed6b918145be33fa54e2e417bb)** - Production deployment checklist

### Operations & Maintenance
- **[Secrets Management - 1Password](https://www.notion.so/2d6b49ed6b9181b0b331f641f915b5b5)** - Credential management
- **[Talos Upgrade Procedure](https://www.notion.so/2d6b49ed6b91813ebe8bd18f4fb7a150)** - Rolling upgrades
- **[S3 Backend Setup](https://www.notion.so/2d3b49ed6b9181b3b6bfe2760e755dc9)** - Backblaze B2 configuration

### Network
- **[Networking Stack](https://www.notion.so/2d3b49ed6b9181d0a118de59312eadd0)** - UniFi configuration

## 🔧 Local Development Documentation

The following docs remain in this repo as they contain development-specific information:

- **[1Password Connect](./generate-1password-credentials.md)** - External Secrets Operator setup
- **[Secrets Management Patterns](./secrets.md)** - Development secrets practices
- **[Development TODOs](./todo.md)** - Tasks and ideas

## 📁 Technical Reference

For technical implementation details, see:
- **[Bootstrap README](../resources/bootstrap/README.md)** - OpenTofu/Terraform technical docs

## 🚀 Quick Start

1. Review **[Cluster Deployment - Bootstrap](https://www.notion.so/2d6b49ed6b9181b391cdca0718ee06c4)** in Notion
2. Load secrets: `source resources/bootstrap/scripts/load-secrets.sh`
3. Deploy: `cd resources/bootstrap && tofu apply`

## 🔗 External Resources

- [Talos Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Backblaze B2 Documentation](https://www.backblaze.com/b2/docs/)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
