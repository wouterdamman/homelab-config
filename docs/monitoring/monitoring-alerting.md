# Monitoring & Alerting

Complete monitoring and alerting setup using Prometheus, Loki, Grafana, and Pushover.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MONITORING ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  DATA COLLECTION                                                            │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                   │
│  │ Prometheus  │     │  Promtail   │     │    Node     │                   │
│  │  Scraping   │     │  DaemonSet  │     │  Exporter   │                   │
│  │  (pull)     │     │  (push)     │     │  (metrics)  │                   │
│  └──────┬──────┘     └──────┬──────┘     └──────┬──────┘                   │
│         │                   │                   │                           │
│  DATA STORAGE               │                   │                           │
│  ┌─────────────┐     ┌─────────────┐            │                           │
│  │ Prometheus  │     │    Loki     │◄───────────┘                           │
│  │   TSDB      │     │  Log Store  │                                        │
│  │  (40Gi)     │     │   (30Gi)    │                                        │
│  └──────┬──────┘     └──────┬──────┘                                        │
│         │                   │                                               │
│  VISUALIZATION              │                                               │
│         └──────────┬─────────┘                                              │
│                    ▼                                                         │
│             ┌─────────────┐                                                 │
│             │   Grafana   │ ◄─── HTTPS via Gateway API                      │
│             │ (dashboards)│     grafana.svc.damman.tech                     │
│             └─────────────┘                                                 │
│                                                                             │
│  ALERTING                                                                   │
│  Prometheus → AlertRules → Alertmanager → Pushover → Mobile                │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Data flow:**
1. **Metrics**: Prometheus scrapes endpoints → TSDB → Grafana/Alertmanager
2. **Logs**: Container stdout/stderr → Promtail → Loki → Grafana
3. **Alerts**: Prometheus evaluates rules → Alertmanager → Pushover

---

## Components

### Prometheus

```yaml
Retention: 14 days
Retention Size: 30GB (stops earlier if limit reached)
Storage: 40Gi PVC on longhorn-monitoring
Scrape Interval: 60s
Evaluation Interval: 60s
```

> **Trade-off:** 60s is a deliberate choice to keep cardinality/storage cost down on a single 40Gi PVC. It means spikes shorter than ~60s (brief CPU/latency/memory blips) are invisible in graphs and won't trigger alerts based on `rate()` over short windows. Accepted as-is — lower the interval only if a real incident gets missed because of it.

**Prometheus scrapes:**
- `kube-state-metrics` — Kubernetes object states
- `node-exporter` — Hardware/OS metrics
- `kubelet` — Container metrics via cAdvisor
- API server, etcd, scheduler, controller-manager — Control plane
- `ServiceMonitors` — App metrics (Longhorn, Cilium, ArgoCD)

### Loki

```yaml
Deployment Mode: SingleBinary (all in one pod)
Retention: 14 days (336h)
Storage: 30Gi PVC on longhorn-monitoring
Schema: v13 with TSDB store
Auth: Disabled (single-tenant)
```

### Promtail

```yaml
Deployment: DaemonSet (runs on every node)
Log Path: /var/log/pods/*/*.log
Format: CRI (Container Runtime Interface)
Labels: namespace, pod, container, node_name, app
```

### Alertmanager

**Routing:**
```yaml
route:
  group_by: ['alertname', 'namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'pushover-warning'
  routes:
    - receiver: 'null'
      matchers: [alertname = "Watchdog"]
    - receiver: 'null'
      matchers: [alertname = "InfoInhibitor"]
    - receiver: 'pushover-critical'
      matchers: [severity = "critical"]
    - receiver: 'pushover-warning'
      matchers: [severity = "warning"]
```

**Pushover integration:**
- **Critical** (priority 1): Bypass Do Not Disturb, repeats until acknowledged
- **Warning** (priority 0): Normal notification

### Grafana

```yaml
URL: https://grafana.svc.damman.tech
Auth: Admin credentials in 1Password (grafana-admin)
Storage: 5Gi (dashboards, settings)
Data Sources:
  - Prometheus (default): http://prometheus-prometheus:9090
  - Loki: http://loki.monitoring:3100
```

---

## Storage Layout

| Component | Storage | Retention | StorageClass | Replicas |
|-----------|---------|-----------|--------------|----------|
| Prometheus | 40Gi | 14 days (30GB limit) | longhorn-monitoring | 1 (ephemeral) |
| Loki | 30Gi | 14 days (336h) | longhorn-monitoring | 1 (ephemeral) |
| Grafana | 5Gi | — | longhorn-standard | 1 |
| Alertmanager | 2Gi | — | longhorn-standard | 2 |
| **Total** | **77Gi** | | | |

**`longhorn-monitoring` StorageClass**: 1 replica, strict-local data locality, no backups. Prometheus/Loki metrics are regenerated continuously — historical data loss is acceptable. Significantly reduces disk I/O and saturation.

**`longhorn-standard`** for Grafana/Alertmanager: dashboards and alert silences are not easily regenerated.

---

## Secrets Management

```yaml
# 1Password items
grafana-admin:
  vault: KubernetesSecrets
  fields: password

pushover-credentials:
  vault: KubernetesSecrets
  fields: username (user-key), password (api-token)
```

---

## Proxmox VE Monitoring

**Status:** Operational (deployed 2026-01-12)  
**Chart:** christianhuth/prometheus-pve-exporter v2.7.1 (app v3.8.0)  
**Authentication:** Password-based (`monitoring@pve` user with PVEAuditor role)  

**Prometheus Targets:**
- 10.0.10.200 (dmn-sk-pve-01) — UP
- 10.0.10.201 (dmn-sk-pve-02) — UP
- Scrape interval: 60s (Proxmox API performance consideration)

**Key metrics (45+ `pve_*` available):**
- `pve_up` — Node/VM/storage status
- `pve_cpu_usage_ratio` — CPU usage (0.0–1.0)
- `pve_memory_usage_bytes` / `pve_memory_size_bytes`
- `pve_cluster_quorate` — Cluster quorum status

**Grafana query pattern** (eliminates duplicate metrics during pod rollouts):

```promql
# Memory usage percentage
max by (id, instance) (
  pve_memory_usage_bytes / pve_memory_size_bytes * 100
  and on(id) pve_node_info
)
```

**Alert rules:**
- **ProxmoxNodeDown** (critical): Node offline >5min
- **ProxmoxClusterNoQuorum** (critical): Cluster lost quorum >2min
- **ProxmoxStorageCritical** (critical): Storage >95% for >5min
- **ProxmoxHighCPU** (warning): CPU >90% for >15min
- **ProxmoxHighMemory** (warning): Memory >90% for >15min
- **ProxmoxStorageFull** (warning): Storage >85% for >10min
- **ProxmoxVMDown** (warning): VM stopped/crashed >5min (was running in last 4h)

**Configuration:**
- `resources/gitops-config/infrastructure/prometheus-pve-exporter/`

**Troubleshooting:**

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-pve-exporter
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-pve-exporter

# Verify targets
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090
# http://localhost:9090/targets (search "pve")

# Test metrics endpoint
kubectl port-forward -n monitoring svc/prometheus-pve-exporter 9221:80
curl http://localhost:9221/pve?target=10.0.10.200
```

---

## Alert Severity Levels

| Level | Priority | Behavior | Examples |
|-------|----------|----------|---------|
| **critical** | 1 | Bypass DND, repeat until ack | Node down, etcd unhealthy, PVC full |
| **warning** | 0 | Normal notification | High CPU, cert expiring, sync failed |
| **info** | -1 | Silent (log only) | Scheduled maintenance |

### Key Pre-configured Rules (kube-prometheus-stack)

**Infrastructure:**
- `NodeNotReady` — Node is not Ready
- `NodeMemoryHighUtilization` — Memory >90%
- `NodeFilesystemSpaceFillingUp` — Disk filling within 24h

**Kubernetes:**
- `KubePodCrashLooping` — Pod restart loop
- `KubePodNotReady` — Pod not Ready >15min
- `KubeDeploymentReplicasMismatch` — Desired != Available
- `KubePersistentVolumeFillingUp` — PVC nearly full

**Control Plane:**
- `etcdMembersDown` — etcd member offline
- `etcdHighNumberOfLeaderChanges` — Unstable cluster
- `KubeAPIErrorBudgetBurn` — API server errors

---

## Querying

### PromQL Examples

```promql
# CPU usage per node (percentage)
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod restart count last hour
increase(kube_pod_container_status_restarts_total[1h])

# Top 5 memory consuming pods
topk(5, sum(container_memory_working_set_bytes) by (pod, namespace))
```

### LogQL Examples

```logql
# All logs from namespace
{namespace="home-assistant"}

# Error logs only
{namespace="argocd"} |= "error" != "errors=0"

# Rate of errors per minute
rate({namespace="monitoring"} |= "error" [1m])

# Top namespaces by log volume
topk(10, sum(rate({job="monitoring/promtail"}[5m])) by (namespace))
```

---

## Grafana Dashboards

### Pre-configured (kube-prometheus-stack)
- Kubernetes / Compute Resources / Cluster
- Node Exporter / Nodes
- CoreDNS, etcd, API Server, Kubelet

### Recommended Imports (Grafana.com)

| Dashboard | ID | Description |
|-----------|----|-------------|
| Longhorn | 16888 | Volume health, replica status |
| Cilium | 16611 | Network policies, flows |
| ArgoCD | 14584 | Sync status, health |
| Loki Dashboard | 13639 | Log volume, errors |

---

## Access

```bash
# Grafana (external)
https://grafana.svc.damman.tech

# Port forwarding for debugging
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090
kubectl port-forward -n monitoring svc/prometheus-alertmanager 9093:9093
kubectl port-forward -n monitoring svc/loki 3100:3100
```

---

## Configuration Files

| Path | Description |
|------|-------------|
| `operators/prometheus-community/values.yaml` | Prometheus, Grafana, Alertmanager config |
| `operators/prometheus-community/templates/grafana-admin-secret.yaml` | ExternalSecret for Grafana |
| `operators/prometheus-community/templates/alertmanager-pushover-secret.yaml` | ExternalSecret for Pushover |
| `operators/prometheus-community/templates/grafana-httproute.yaml` | Gateway API HTTPRoute |
| `operators/loki/values.yaml` | Loki configuration |
| `operators/promtail/values.yaml` | Promtail configuration |

---

## Troubleshooting

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090
# http://localhost:9090/targets

# Check Alertmanager
kubectl port-forward -n monitoring svc/prometheus-alertmanager 9093:9093
# http://localhost:9093/#/status

# View Promtail logs
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail

# Test Pushover notification
kubectl exec -n monitoring -it deploy/prometheus-alertmanager -- \
  amtool alert add test severity=critical namespace=test
```

| Issue | Symptom | Solution |
|-------|---------|---------|
| Promtail not ready | 0/1 Running | Check scrape config has `__path__` |
| No logs in Loki | Empty queries | Check Promtail → Loki connectivity |
| Alerts not firing | No notifications | Check Alertmanager config, secrets |
| High cardinality | Slow queries | Reduce label values, add aggregation |

---

## Changelog

### 2026-01-27
- **Storage Optimization**: Introduced `longhorn-monitoring` StorageClass for ephemeral monitoring data (1 replica, strict-local, no backups). Significantly reduces disk I/O.
- Prometheus and Loki migrated from `longhorn-standard` to `longhorn-monitoring`

### 2026-01-26
- **Resource Limit Increases**: Fixed CPU/memory throttling
  - Grafana: CPU 500m→1000m, Memory 512Mi→1024Mi (was hitting 78% memory)
  - Promtail: CPU 100m→200m, Memory 128Mi→512Mi (was hitting 80-94% across pods)

### 2026-01-15
- Prometheus PVE Exporter: CPU limit 500m→300m (utilization was only 5%)

### 2026-01-12
- Added prometheus-pve-exporter for Proxmox VE hypervisor monitoring
- 7 new Proxmox alert rules (3 critical, 4 warning)

### 2026-01-02
- Watchdog and InfoInhibitor alerts routed to null receiver (no Pushover notifications)
- `bind-address: 0.0.0.0` added for kube-controller-manager and kube-scheduler
- ServiceMonitors: HTTPS with insecureSkipVerify for control plane components
