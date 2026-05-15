# High-Level Design

Executive overview of the homelab infrastructure, architecture and key components.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         UniFi Dream Machine Pro                              │
│                    Firewall / Router / VPN Gateway                          │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│       Management VLAN         │   │        Server VLAN            │
│         10.0.0.0/24           │   │       10.0.10.0/24            │
│                               │   │                               │
│  • Proxmox UI                 │   │  • Kubernetes Cluster         │
│  • UniFi Controller           │   │  • NAS Storage                │
│  • Management Access          │   │  • Application Workloads      │
└───────────────────────────────┘   └───────────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PROXMOX CLUSTER                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    TALOS KUBERNETES CLUSTER                          │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                    │   │
│  │  │ Control     │ │ Control     │ │ Control     │  High Availability │   │
│  │  │ Plane 1     │ │ Plane 2     │ │ Plane 3     │  etcd Cluster      │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘                    │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                    │   │
│  │  │ Worker 1    │ │ Worker 2    │ │ Worker 3    │  Workload Nodes    │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          EXTERNAL SERVICES                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  Hetzner Object │  │   1Password     │  │    GitHub       │             │
│  │  Storage        │  │  • Secrets      │  │  • GitOps Repo  │             │
│  │  • TF State     │  │  • Credentials  │  │  • CI/CD        │             │
│  │  • Backups      │  │                 │  │                 │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Core Principles

### 1. GitOps-First
All cluster configuration is managed via Git and automatically synchronized by ArgoCD.

### 2. Zero Secrets in Git
All credentials are stored in 1Password and dynamically loaded via External Secrets Operator.

### 3. Infrastructure as Code
Full cluster reproducibility via OpenTofu — from VM provisioning to application deployment.

### 4. Production-Grade Storage
Longhorn distributed storage with automated S3 backups to Hetzner Object Storage.

### 5. High Availability
3 control plane nodes for etcd quorum, 3 worker nodes for workload distribution.

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Virtualization** | Proxmox VE | VM hosting and management |
| **Operating System** | Talos Linux | Immutable, secure Kubernetes OS |
| **Container Orchestration** | Kubernetes v1.36.0 | Workload scheduling and management |
| **Networking** | Cilium + Gateway API | CNI, network policies, ingress |
| **Storage** | Longhorn | Distributed block storage |
| **GitOps** | ArgoCD | Continuous deployment |
| **Secrets** | 1Password + ESO | Secure credential management |
| **IaC** | OpenTofu | Infrastructure provisioning |
| **Backup** | Hetzner Object Storage | Off-site backup storage |
| **Database** | CloudNative-PG | PostgreSQL operator with HA |
| **Monitoring** | Prometheus + Loki | Metrics and logs aggregation |
| **Authentication** | Authentik | SSO and identity provider |
| **Home Automation** | HA + EMQX + Z2M | Smart home platform |

---

## Key Metrics & Targets

| Metric | Target | Current |
|--------|--------|---------|
| **RTO** (Recovery Time Objective) | < 4 hours | ✅ Achieved |
| **RPO** (Recovery Point Objective) | < 1 hour | ✅ Achieved |
| **Backup Retention** | 30 days daily, 12 months monthly | ✅ Configured |
| **Control Plane HA** | 3 nodes (etcd quorum) | ✅ Running |
| **Storage Replication** | 2-3 replicas per volume | ✅ Configured |

---

## Data Flow

### Deployment Flow
```
Developer → Git Push → GitHub → ArgoCD → Kubernetes → Application
```

### Secrets Flow
```
1Password → External Secrets Operator → Kubernetes Secret → Application
```

### Backup Flow
```
Longhorn Volume → Snapshot → S3 Backup → Hetzner Object Storage
```

### Ingress & DNS Flow
```
Client Request → UniFi DNS → Cilium Gateway → HTTPRoute → Service → Pod
                    ↑
            external-dns
                    ↑
          Kubernetes Resources
```

### Certificate Flow
```
Gateway Annotation → cert-manager → Let's Encrypt ACME → Cloudflare DNS-01 → Certificate
```

### Monitoring Flow
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          OBSERVABILITY STACK                                 │
│                                                                              │
│   METRICS                    LOGS                      ALERTING             │
│   ┌─────────────┐           ┌─────────────┐           ┌─────────────┐      │
│   │ Prometheus  │◄──────────│   Promtail  │           │Alertmanager │      │
│   │   (TSDB)    │  scrape   │ (DaemonSet) │           │  (route)    │      │
│   └──────┬──────┘           └──────┬──────┘           └──────┬──────┘      │
│          │                         │                         │             │
│          │ scrape                  │ push                    ▼             │
│          │                         ▼                  ┌─────────────┐      │
│   ┌──────┴──────┐           ┌─────────────┐          │  Pushover   │      │
│   │  PVE        │           │   Loki      │          │  (mobile)   │      │
│   │  Exporter   │           │  (store)    │          └─────────────┘      │
│   └─────────────┘           └──────┬──────┘                                │
│                                    │                                       │
│          ┌─────────────────────────┘                                       │
│          ▼                                                                  │
│   ┌─────────────┐                                                          │
│   │   Grafana   │ ◄─── HTTPS via Gateway API                               │
│   │ (dashboards)│     grafana.svc.damman.tech                              │
│   └─────────────┘                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Related Documentation

- [Low-Level Design](low-level-design.md) — Technical implementation details
- [Architecture Decision Records](adr.md) — Why decisions were made
- [Bootstrap: Cluster Deployment](../bootstrap/cluster-deployment.md)
- [Operations: Talos Upgrade](../operations/talos-upgrade.md)
