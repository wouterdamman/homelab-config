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
# Pod and service CIDRs are set at Talos/Kubernetes level, not in Cilium Helm values.
# Cilium uses ipam.mode: kubernetes and inherits these ranges from the K8s API server.
# Example values (configured in Talos machine config):
#   podSubnets: 10.244.0.0/16
#   serviceSubnets: 10.96.0.0/12
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
  cpu_cores: 4
  memory: 8192 MB
  disk: 250 GB

worker:
  cpu_cores: 2
  memory: 4096 MB
  disk: 250 GB
  secondary_disk: 268 GB  # Longhorn data disk
```

### Node Layout

Node IPs are dynamically generated from the `cluster_cidr` and `ip_offset` Terraform variables (e.g. `cluster_cidr = "10.0.10"`, `ip_offset = 130`). The IPs below are examples for the production cluster, not hardcoded values.

| Node | Role | IP (example) | Resources |
|------|------|----|-----------|
| prd-cp-01 | Control Plane | 10.0.10.130 | 4 CPU, 8GB RAM |
| prd-cp-02 | Control Plane | 10.0.10.131 | 4 CPU, 8GB RAM |
| prd-cp-03 | Control Plane | 10.0.10.132 | 4 CPU, 8GB RAM |
| prd-w-01 | Worker | 10.0.10.133 | 2 CPU, 4GB RAM |
| prd-w-02 | Worker | 10.0.10.134 | 2 CPU, 4GB RAM |
| prd-w-03 | Worker | 10.0.10.135 | 2 CPU, 4GB RAM |

---

## 3. Storage Architecture

### Longhorn Storage Tiers

```yaml
longhorn-fast:
  replicas: 3
  dataLocality: best-effort
  reclaimPolicy: Retain
  useCase: Databases, critical data

longhorn-standard:  # DEFAULT
  replicas: 2
  dataLocality: best-effort
  reclaimPolicy: Retain
  useCase: General applications

longhorn-archive:
  replicas: 1
  dataLocality: disabled
  reclaimPolicy: Delete
  useCase: Logs, temporary data

longhorn-monitoring:
  replicas: 1
  dataLocality: strict-local
  reclaimPolicy: Delete
  recurringJobs: disabled
  useCase: Prometheus, Loki (monitoring data, no backups/snapshots)
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
├── Wave 0: Core Infrastructure
│   ├── argocd (self-managed)
│   ├── argocd-apps (Projects)
│   ├── cilium (CNI)
│   └── longhorn (Storage)
├── Wave 1: Essential Operators
│   ├── onepassword-connect (Secrets backend)
│   ├── external-secrets (Secrets operator)
│   ├── cert-manager (TLS certificates)
│   ├── external-dns (DNS automation)
│   ├── kubelet-csr-approver (Certificate approval)
│   ├── cloudnative-pg (PostgreSQL operator)
│   └── sync-app (self-managed root app)
├── Wave 2: Monitoring & Auth
│   ├── kube-prometheus-stack (Metrics + Grafana)
│   ├── prometheus-pve-exporter (Proxmox metrics)
│   ├── loki (Log aggregation)
│   ├── promtail (Log shipping)
│   └── authentik (SSO/IdP)
├── Wave 3: Infrastructure Apps
│   └── proxmox (Proxmox infrastructure)
├── Wave 4: Home Automation
│   ├── home-assistant
│   ├── emqx
│   └── zigbee2mqtt
└── Wave 5: Additional Apps
    └── evcc (solar charging)

# Not currently deployed via GitOps (commented out):
#   netbox, homarr, firefly-iii
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
  Wave 0: Longhorn, Cilium, ArgoCD (self-managed), argocd-apps
  Wave 1: 1Password Connect, ESO, cert-manager, external-dns, kubelet-csr-approver, cloudnative-pg, sync-app (self-managed)
  Wave 2: kube-prometheus-stack, prometheus-pve-exporter, loki, promtail, authentik
  Wave 3: proxmox (infrastructure)
  Wave 4: home-assistant, emqx, zigbee2mqtt
  Wave 5: evcc
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
