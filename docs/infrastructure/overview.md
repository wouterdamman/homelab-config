# Infrastructure Overview

Complete overview of the homelab infrastructure stack.

## Architecture Diagram

```
┌───────────────────────────────────────────────────────────────┐
│                     UniFi Dream Machine                       │
│                   (Router / Firewall / DNS)                   │
└───────────────────────────────┬───────────────────────────────┘
                                │
                ┌───────────────┴───────────────┐
                │                               │
        ┌───────┴───────┐             ┌───────┴───────┐
        │ dmn-sk-pve-01 │             │ dmn-sk-pve-02 │
        │   Proxmox     │             │   Proxmox     │
        │  10.0.10.200  │             │  10.0.10.201  │
        └──────┬────────┘             └──────┬────────┘
               │                              │
               │  PRD Cluster                 │  TST Cluster (future)
               ▼
        ┌───────────────────────┐
        │  Talos Kubernetes     │
        │  VIP: 10.0.10.140     │
        │                       │
        │  3x Control Plane     │
        │  3x Workers           │
        └───────────────────────┘
```

## Hardware

### Proxmox Hosts

| Host | IP | Role | Status |
|------|----|------|--------|
| dmn-sk-pve-01 | 10.0.10.200 | PRD cluster host | Active |
| dmn-sk-pve-02 | 10.0.10.201 | TST cluster host | Planned |

### Proxmox Cluster Infrastructure (ADR-027)

| Component | IP | Role | Status |
|-----------|----|------|--------|
| qdevice-primary (LXC 200) | 10.0.10.202 | Cluster quorum arbiter (corosync-qnetd) | Active |

### VLANs

| VLAN | Name | Subnet | Purpose |
|------|------|--------|---------|
| 1 | Default | 192.168.2.0/27 | Fallback/adoption |
| 10 | Client | 10.0.10.0/26 | Everyday devices |
| 11 | Kids | 10.0.10.64/29 | Kids' devices |
| 13 | Server | 10.0.10.128/25 | Kubernetes/NAS |
| 30 | IoT | 10.0.30.0/24 | IoT & cameras |
| 40 | Guest | 10.0.40.128/28 | Guests |
| 99 | MGMT | 10.0.99.0/24 | UniFi management |
| 255 | Xbox | 10.255.1.0/29 | Game console |

## Software Stack

### Infrastructure Layer

| Component | Purpose | Version |
|-----------|---------|---------|
| Proxmox VE | Hypervisor | 8.x |
| Talos Linux | Kubernetes OS | v1.13.2 |
| Kubernetes | Container Orchestration | v1.36.0 |
| Cilium | CNI + Gateway API | v1.19.3 |
| Longhorn | Distributed Storage | v1.11.2 |

### GitOps Layer

| Component | Purpose |
|-----------|---------|
| OpenTofu | Infrastructure as Code |
| ArgoCD | GitOps CD |
| External Secrets | Secrets from 1Password |
| cert-manager | TLS certificates |
| external-dns | DNS automation (UniFi) |

### Monitoring & Observability

| Component | Role | URL |
|-----------|------|-----|
| **Prometheus** | Metrics (TSDB) | Internal only |
| **Loki** | Log aggregation | Internal only |
| **Promtail** | Log collection (DaemonSet) | — |
| **Grafana** | Dashboards | grafana.svc.damman.tech |
| **Alertmanager** | Alert routing → Pushover | Internal only |

**Storage:** ~77Gi total (Prometheus 40Gi, Loki 30Gi, Grafana 5Gi, Alertmanager 2Gi)
**Retention:** Metrics 60 days, Logs 14 days

### Database Layer

| Cluster | Purpose | Instances | Storage | Backup |
|---------|---------|-----------|---------|--------|
| **cnpg-shared** | Authentik, NetBox, small apps | 2 | 5Gi | Daily @ 03:00, 14d retention |
| **cnpg-homeassistant** | Home Assistant recorder | 2 | 10Gi | Every 6h, 30d retention |

**Service Endpoints:**
- Read-Write: `cnpg-{cluster}-rw.cnpg-system.svc.cluster.local:5432`
- Read-Only: `cnpg-{cluster}-ro.cnpg-system.svc.cluster.local:5432`

### Workloads

| Application | Purpose | Access |
|-------------|---------|--------|
| Home Assistant | Home automation | home.app.damman.tech |
| EMQX | MQTT broker (3 replicas) | emqx.app.damman.tech (dashboard) |
| Zigbee2MQTT | Zigbee bridge | Internal |
| Authentik | SSO/Authentication | sso.svc.damman.tech |
| Grafana | Monitoring dashboards | grafana.svc.damman.tech |
| NetBox | IPAM/DCIM | Planned |

## Network Layout

### IP Ranges

| Range | Purpose |
|-------|---------|
| 10.0.10.130-135 | Kubernetes nodes |
| 10.0.10.140 | Cluster VIP |
| 10.0.10.193 | Gateway |
| 10.0.10.200-201 | Proxmox hosts |
| 10.0.10.202 | QDevice (LXC) |
| 10.0.10.240-250 | Cilium LB Pool |
| 10.0.10.241 | App Gateway (Cilium) |
| 10.0.10.242 | Home Assistant LoadBalancer |

## Ingress & DNS

### Traffic Flow

```
Client Request
      ↓
UniFi DNS (*.app.damman.tech → 10.0.10.241)
      ↓
Cilium Gateway (app-gateway)
      ↓
HTTPRoute (path/host matching)
      ↓
Kubernetes Service
      ↓
Application Pod
```

### DNS Domains

| Domain | Purpose | Example |
|--------|---------|---------|
| *.local.damman.tech | Internal services | proxmox.local.damman.tech |
| *.svc.damman.tech | Kubernetes services | argocd.svc.damman.tech |
| *.app.damman.tech | Applications | home.app.damman.tech |

## Backup Strategy

| Data | Target | Method |
|------|--------|--------|
| Terraform State | Hetzner Object Storage | S3 backend |
| Longhorn Volumes | Hetzner Object Storage | S3 backup target |
| CNPG Databases | Hetzner Object Storage | Native S3 backup |
| Proxmox VMs | Local | PBS (planned) |

## Repository Structure

```
homelab-config/
├── resources/
│   ├── bootstrap/          # OpenTofu for VMs + Talos
│   ├── gitops-config/      # ArgoCD apps + operators
│   └── infrastructure/     # QDevice LXC OpenTofu workspace
├── docs/                   # Documentation
└── renovate.json           # Dependency updates
```

## Changelog

### 2026-05-15
- Talos Linux: v1.12.2 → v1.13.2
- Kubernetes: v1.35.0 → v1.36.0
- Cilium: v1.18.5 → v1.19.3
- Longhorn: v1.10.1 → v1.11.2
- ArgoCD: chart 9.2.4 → 9.5.14 (app v3.4.2)
- External Secrets Operator: 1.2.1 → 2.4.1

### 2026-02-15
- Memory Upgrade: Control plane 4GB → 5GB, Workers 10GB → 12GB

### 2026-01-28
- Home Automation Migration Complete: Home Assistant fully migrated to Kubernetes

### 2026-01-12
- ADR-026: Added prometheus-pve-exporter for Proxmox hypervisor monitoring
- ADR-027: Deployed QDevice (LXC 200) for 2-node cluster quorum
