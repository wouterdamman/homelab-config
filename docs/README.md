# Homelab Documentation

In-repo documentation for the homelab Kubernetes cluster (`talos-prd`) running on Proxmox VE.

---

## Architecture

| Document | Description |
|----------|-------------|
| [High-Level Design](architecture/high-level-design.md) | System overview, component map, design principles |
| [Low-Level Design](architecture/low-level-design.md) | VLANs, compute specs, storage tiers, GitOps waves |
| [Architecture Decision Records](architecture/adr.md) | ADR-001 through ADR-027 |

---

## Bootstrap

| Document | Description |
|----------|-------------|
| [Cluster Deployment](bootstrap/cluster-deployment.md) | Talos cluster bootstrap procedure |
| [GitOps Bootstrap](bootstrap/gitops-bootstrap.md) | ArgoCD bootstrap and app-of-apps setup |
| [Deployment Plan](bootstrap/deployment-plan.md) | Production deployment checklist |
| [Secrets Management](bootstrap/secrets-management.md) | 1Password → ESO → Kubernetes secrets flow |

---

## Infrastructure

| Document | Description |
|----------|-------------|
| [Infrastructure Overview](infrastructure/overview.md) | Full stack overview with software versions |
| [Networking Stack](infrastructure/networking-stack.md) | UniFi VLANs, Wi-Fi, firewall, WireGuard VPN |
| [S3 Backend](infrastructure/s3-backend.md) | Hetzner Object Storage for OpenTofu state |
| [Renovate Configuration](infrastructure/renovate.md) | Dependency update tiers and automation rules |

---

## Operators

| Document | Description |
|----------|-------------|
| [Cilium](operators/cilium.md) | CNI, Gateway API, Hubble, L2 announcements |
| [ArgoCD](operators/argocd.md) | GitOps, GitHub SSO, RBAC, notifications |
| [cert-manager](operators/cert-manager.md) | TLS certificates, Let's Encrypt, Cloudflare DNS-01 |
| [External DNS](operators/external-dns.md) | UniFi DNS automation via webhook provider |
| [External Secrets](operators/external-secrets.md) | ESO ClusterSecretStore, 1Password integration |
| [1Password Connect](operators/1password-connect.md) | Local 1Password API server for ESO |
| [Kubelet CSR Approver](operators/kubelet-csr-approver.md) | Automatic kubelet certificate approval (Talos) |
| [Longhorn](operators/longhorn.md) | Distributed block storage, S3 backup, storage tiers |
| [Longhorn Production Plan](operators/longhorn-production-plan.md) | Implementation plan, StorageClass tiers, alert rules |
| [Longhorn DR Runbook](operators/longhorn-dr-runbook.md) | Disaster recovery procedures and test scripts |
| [CloudNative-PG](operators/cloudnative-pg.md) | Shared PostgreSQL cluster, CNPG operator |
| [Proxmox VE Gateway](operators/proxmox-gateway.md) | TLS passthrough, Authentik OIDC, Let's Encrypt on Proxmox |

---

## Applications

| Document | Description |
|----------|-------------|
| [Authentik](applications/authentik.md) | SSO platform, OIDC provider, forward auth |
| [Home Assistant](applications/home-assistant.md) | Smart home hub, code-server sidecar, WebSocket fix |
| [EMQX](applications/emqx.md) | MQTT broker, 3-replica StatefulSet |
| [Zigbee2MQTT](applications/zigbee2mqtt.md) | Zigbee gateway, init container config pattern |
| [EVCC](applications/evcc.md) | Solar EV charging, Alfen/SolarEdge/DSMR integration |
| [NetBox](applications/netbox.md) | IPAM/DCIM, OIDC, custom pipeline |
| [Firefly III](applications/firefly-iii.md) | Personal finance, APP_KEY requirements, no OIDC |
| [Homarr](applications/homarr.md) | Dashboard |

---

## Monitoring

| Document | Description |
|----------|-------------|
| [Monitoring & Alerting](monitoring/monitoring-alerting.md) | Prometheus, Loki, Grafana, Alertmanager, Pushover, Proxmox PVE exporter |

---

## Operations

| Document | Description |
|----------|-------------|
| [Talos Upgrade](operations/talos-upgrade.md) | Rolling upgrade procedure for Talos and Kubernetes |
| [Disaster Recovery](operations/disaster-recovery.md) | Full cluster recovery checklist from scratch |
| [Troubleshooting](operations/troubleshooting.md) | Common issues and diagnostic commands |

---

## Quick Reference

```bash
# Bootstrap commands
eval $(op signin)
source resources/bootstrap/scripts/load-secrets.sh
cd resources/bootstrap && tofu init && tofu apply

# Talos operations
talosctl --talosconfig resources/bootstrap/output/talosconfig <subcommand>
kubectl --kubeconfig resources/bootstrap/output/kubeconfig <subcommand>

# ArgoCD (GitOps manages cluster state after bootstrap)
argocd app list
argocd app sync <app-name>

# Longhorn storage
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80

# Hubble network observability
kubectl port-forward -n kube-system svc/hubble-ui 8080:80
```

## External Resources

- [Talos Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Hetzner Object Storage](https://docs.hetzner.com/storage/object-storage/)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
