# Homelab Documentation

> **All documentation is maintained in Notion.**

## Main Documentation (Notion)

Access the complete homelab documentation in the **[Homelab Database](https://www.notion.so/2d3b49ed6b91808e915de47613e29b3e)**:

### Infrastructure & Deployment
- **[Infrastructure Overview](https://www.notion.so/2d3b49ed6b9181ac8474fa2a2be73c1c)** - Complete stack overview
- **[Cluster Deployment - Bootstrap](https://www.notion.so/2d6b49ed6b9181b391cdca0718ee06c4)** - Talos cluster bootstrap
- **[GitOps Deployment - ArgoCD Bootstrap](https://www.notion.so/2d7b49ed6b91816dbb9cc3cdab067eeb)** - ArgoCD & operators setup
- **[Deployment Plan](https://www.notion.so/2d3b49ed6b918145be33fa54e2e417bb)** - Production deployment checklist

### Operations & Maintenance
- **[Secrets Management - 1Password](https://www.notion.so/2d6b49ed6b9181b0b331f641f915b5b5)** - Credential management & External Secrets
- **[Talos Upgrade Procedure](https://www.notion.so/2d6b49ed6b91813ebe8bd18f4fb7a150)** - Rolling upgrades
- **[S3 Backend Setup](https://www.notion.so/2d3b49ed6b9181b3b6bfe2760e755dc9)** - Backblaze B2 configuration

### Storage & Backup
- **[Longhorn Production-Grade Plan](https://www.notion.so/2d7b49ed6b918118be02fa588f4d2ec1)** - Storage configuration & backup strategy
- **[Longhorn Disaster Recovery Runbook](https://www.notion.so/2d7b49ed6b918115a374db661adfce74)** - DR procedures & automated testing

### Network
- **[Networking Stack](https://www.notion.so/2d3b49ed6b9181d0a118de59312eadd0)** - UniFi & Cilium configuration

## Technical Reference (In-Repo)

For technical implementation details, see:
- **[resources/bootstrap/README.md](../resources/bootstrap/README.md)** - Talos cluster bootstrap technical docs
- **[resources/gitops-config/README.md](../resources/gitops-config/README.md)** - ArgoCD bootstrap technical docs

## Quick Start

1. Review **[Cluster Deployment - Bootstrap](https://www.notion.so/2d6b49ed6b9181b391cdca0718ee06c4)** in Notion
2. Load secrets: `source resources/bootstrap/scripts/load-secrets.sh`
3. Deploy: `cd resources/bootstrap && tofu apply`

## External Resources

- [Talos Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Backblaze B2 Documentation](https://www.backblaze.com/b2/docs/)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
