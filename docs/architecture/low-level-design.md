# Low-Level Design

Technical implementation details for all components in the homelab infrastructure.

---

## 1. Network Architecture

### VLAN Configuration

| VLAN ID | Name | Subnet | Purpose |
|---------|------|--------|---------|
| 1 | Management | 10.0.0.0/24 | Proxmox, UniFi, management access |
| 10 | Server | 10.0.10.0/24 | Kubernetes nodes, NAS |
| 20 | IoT | 10.0.20.0/24 | IoT devices (isolated) |
| 30 | Guest | 10.0.30.0/24 | Guest network |

### Kubernetes Network

```yaml
clusterPoolIPv4PodCIDRList: ["10.244.0.0/16"]
serviceCIDR: 10.96.0.0/12
# Features: eBPF datapath, Gateway API, network policies, Hubble observability
```

See [Networking Stack](../infrastructure/networking-stack.md) for full details.

---

## 2. Compute Layer

### Ingress Architecture (Cilium Gateway API)

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: app-gateway
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
spec:
  gatewayClassName: cilium
  addresses:
    - type: IPAddress
      value: "10.0.10.241"
  listeners:
    - name: app-https-listener
      protocol: HTTPS
      port: 443
      hostname: "*.app.damman.tech"
      tls:
        mode: Terminate
```

### TLS Certificates (cert-manager)

```yaml
# ClusterIssuer: Let's Encrypt + Cloudflare DNS-01
solvers:
  - dns01:
      cloudflare:
        apiTokenSecretRef:
          name: cert-manager-cloudflare
          key: cloudFlare
    selector:
      dnsZones: ["damman.tech"]
```

### Traffic Flow

```
Client Request (*.app.damman.tech)
         │
         ▼
UniFi DNS (external-dns) → resolves to 10.0.10.241
         │
         ▼
Cilium Gateway API (10.0.10.241:443) → TLS termination, HTTPRoute matching
         │
         ▼
Kubernetes Service → Load balancing to pods
```

### Proxmox VM Specifications

```hcl
control_plane:
  cpu_cores: 2
  memory: 5120 MB   # Upgraded 2026-02-15
  disk: 60 GB

worker:
  cpu_cores: 3
  memory: 12288 MB  # Upgraded 2026-02-15
  disk: 250 GB
```

### Node Layout

| Node | Role | IP | Resources |
|------|------|----|-----------|
| prd-cp-01 | Control Plane | 10.0.10.130 | 2 CPU, 5GB RAM |
| prd-cp-02 | Control Plane | 10.0.10.131 | 2 CPU, 5GB RAM |
| prd-cp-03 | Control Plane | 10.0.10.132 | 2 CPU, 5GB RAM |
| prd-w-01 | Worker | 10.0.10.133 | 3 CPU, 12GB RAM |
| prd-w-02 | Worker | 10.0.10.134 | 3 CPU, 12GB RAM |
| prd-w-03 | Worker | 10.0.10.135 | 3 CPU, 12GB RAM |

---

## 3. Storage Architecture

### Longhorn Storage Tiers

```yaml
longhorn-fast:
  replicas: 3
  useCase: Databases, critical data

longhorn-standard:  # DEFAULT
  replicas: 2
  useCase: General applications

longhorn-archive:
  replicas: 1
  useCase: Logs, temporary data
```

### Backup Strategy

```
Fast Tier:    Hourly snapshots (24h) + Daily backups (30d)
Standard Tier: Daily snapshots (7d) + Daily backups (14d)
Archive Tier:  Weekly snapshots (4w) + Weekly backups (4w)
All Tiers:     Monthly DR backups (12m)
```

See [Longhorn Production-Grade Plan](../operators/longhorn-production-plan.md) and [Longhorn DR Runbook](../operators/longhorn-dr-runbook.md).

---

## 4. GitOps Architecture

### ArgoCD App-of-Apps Pattern

```
sync-app (Root Application)
├── Wave 0 (tier-0): Core Infrastructure
│   ├── argocd (self-managed)
│   ├── argocd-apps (Projects)
│   ├── cilium (CNI)
│   └── longhorn (Storage)
├── Wave 1 (tier-1): Essential Operators
│   ├── onepassword-connect (Secrets backend)
│   ├── external-secrets (Secrets operator)
│   ├── cert-manager (TLS certificates)
│   ├── external-dns (DNS automation)
│   ├── kubelet-csr-approver (Certificate approval)
│   └── cloudnative-pg (PostgreSQL operator)
├── Wave 2 (tier-2): Monitoring & Auth
│   ├── kube-prometheus-stack (Metrics + Grafana)
│   ├── prometheus-pve-exporter (Proxmox metrics)
│   ├── loki (Log aggregation)
│   ├── promtail (Log shipping)
│   └── authentik (SSO/IdP)
└── Wave 3+: Applications
    ├── emqx, zigbee2mqtt, home-assistant
    ├── netbox, homarr, firefly-iii
    └── evcc
```

See [GitOps Bootstrap](../bootstrap/gitops-bootstrap.md).

---

## 5. Secrets Management

```
1Password Cloud (KubernetesSecrets vault)
         │
         ▼
1Password Connect (onepassword namespace)
         │
         ▼
External Secrets Operator
         │
         ▼
Kubernetes Secrets (per namespace)
```

| Vault | Purpose | Items |
|-------|---------|-------|
| Homelab | Infrastructure credentials | Proxmox, Hetzner (TF state) |
| KubernetesSecrets | Kubernetes workload secrets | GitHub App, 1Password Connect, Longhorn S3 |

See [Secrets Management](../bootstrap/secrets-management.md).

---

## 6. Deployment Pipeline

### Bootstrap Sequence

```
Phase 1: Infrastructure (OpenTofu)
  1. Load secrets: source scripts/load-secrets.sh
  2. Create Proxmox VMs
  3. Generate Talos configs
  4. Bootstrap Talos cluster
  5. Install Cilium CNI

Phase 2: GitOps (OpenTofu)
  1. Generate input-files from 1Password
  2. Deploy 1Password Connect
  3. Deploy External Secrets Operator
  4. Create ClusterSecretStore
  5. Deploy ArgoCD
  6. Deploy sync-app (ArgoCD takes over)

Phase 3: ArgoCD (GitOps)
  Wave 0: Longhorn, Cilium
  Wave 1: 1Password, ESO (self-managed)
  Wave 2: cert-manager, external-dns
  Wave 3: ArgoCD (self-managed)
```

---

## 7. Disaster Recovery

| Component | Backup Method | Location | Retention |
|-----------|--------------|----------|-----------|
| Terraform State | S3 Backend | Hetzner Object Storage | Versioned |
| Longhorn Volumes | Snapshot + S3 | Hetzner Object Storage | 30d/12m |
| Talos Configs | Git + 1Password | GitHub + 1Password | Versioned |
| Secrets | 1Password | 1Password Cloud | Unlimited |

- **RTO:** < 4 hours (full cluster rebuild)
- **RPO:** < 1 hour (hourly snapshots)

See [Longhorn DR Runbook](../operators/longhorn-dr-runbook.md) and [Disaster Recovery Checklist](../operations/disaster-recovery.md).

---

## 8. Monitoring Architecture

### Components

```yaml
kube-prometheus-stack:
  - Prometheus: Time-series DB, metrics scraping
  - Alertmanager: Alert routing (Pushover)
  - Grafana: Dashboards (grafana.svc.damman.tech)
  - node-exporter: Hardware/OS metrics (DaemonSet)
  - kube-state-metrics: Kubernetes object states

Loki Stack:
  - Loki: Log aggregation (label-based indexing)
  - Promtail: Log collection (DaemonSet)
```

### Storage

| Component | Storage | Retention |
|-----------|---------|-----------|
| Prometheus | 40Gi | 30 days |
| Loki | 30Gi | 14 days |
| Grafana | 5Gi | — |
| Alertmanager | 2Gi | — |

### Proxmox Monitoring (ADR-026, deployed 2026-01-12)

```yaml
# prometheus-pve-exporter
User: monitoring@pve (PVEAuditor role)
Targets: 10.0.10.200 (pve-01), 10.0.10.201 (pve-02)
Scrape interval: 60s

Alert Rules:
  Critical: ProxmoxNodeDown, ProxmoxClusterNoQuorum, ProxmoxStorageCritical (>95%)
  Warning: ProxmoxHighCPU (>90%), ProxmoxHighMemory (>90%), ProxmoxStorageFull (>85%), ProxmoxVMDown
```

### Alerting

```yaml
Critical (priority 1): Bypass DND, repeat until acknowledged
  - Node down, CrashLoopBackOff, PVC almost full (>85%), Longhorn volume degraded

Warning (priority 0): Normal notification
  - High CPU/memory, certificate expiring, ArgoCD sync failed
```

---

## 9. Home Automation Stack

```
Home Assistant (Kubernetes)
      │ MQTT (1883)
      ▼
EMQX Cluster (3 replicas, emqx.emqx:1883)
      │
      ├── Zigbee2MQTT (Kubernetes)
      │       │ TCP
      │       ▼
      │   Zigbee Coordinator (tcp://10.0.30.176:6638)
      │
      └── EVCC (solar charging)
```

| Component | Status | Date |
|-----------|--------|------|
| EMQX deployed | ✅ | 2026-01-17 |
| Zigbee2MQTT deployed | ✅ | 2026-01-17 |
| Home Assistant deployed in K8s | ✅ | 2026-01-28 |
| Old HA (10.0.10.165) decommissioned | ✅ | 2026-01-28 |

**Database:** `cnpg-homeassistant` cluster (10Gi, backups every 6h, 30-day retention)

---

## Related Documentation

- [High-Level Design](high-level-design.md) — Executive overview
- [Infrastructure Overview](../infrastructure/overview.md) — Stack overview
- [Cluster Deployment](../bootstrap/cluster-deployment.md) — Bootstrap guide
- [Networking Stack](../infrastructure/networking-stack.md) — UniFi & Cilium
