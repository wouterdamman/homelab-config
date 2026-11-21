# Monitoring & Alerting

Metrics, logs and alerts with VictoriaMetrics, VictoriaLogs, Grafana and Pushover. Alertmanager and Grafana are their own Argo apps; everything lives in the `monitoring` namespace.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MONITORING ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  COLLECTION                                                                 │
│  vmagent (pull, 30s)  ◄── kubelet, API server, etcd, CoreDNS, node-exporter,│
│                           kube-state-metrics, all app endpoints             │
│  vlagent (DaemonSet)  ◄── /var/log/pods of every node (container logs)     │
│  Vector               ◄── Talos service + kernel logs (TCP, 10.0.10.242)    │
│                                                                             │
│  STORAGE                                                                    │
│  vmsingle (metrics, 40Gi)         vlsingle (logs, 10Gi)                     │
│                                                                             │
│  RULES AND ALERTS                                                           │
│  vmalert ──► Alertmanager ──► Pushover (critical / warning)                 │
│                          └──► healthchecks.io (Watchdog, dead man's switch) │
│                                                                             │
│  VISUALIZATION                                                              │
│  Grafana  ◄── vmsingle + vlsingle      https://grafana.svc.damman.tech      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Data flow**
1. **Metrics**: vmagent scrapes the targets and remote-writes to vmsingle. Grafana and vmalert query vmsingle (through the internal `vmauth`, which also routes to vlsingle).
2. **Logs**: vlagent tails the container logs of its node and ships them to vlsingle. Talos sends its own service and kernel logs to Vector, which posts them to vlsingle.
3. **Alerts**: vmalert evaluates the rules and notifies Alertmanager, which sends Pushover messages. The always-firing `Watchdog` alert pings healthchecks.io; if the pings stop, healthchecks.io messages you.

---

## Apps

| Argo app | Chart | What |
|----------|-------|------|
| `victoria-metrics` | `victoria-metrics-k8s-stack` | VMSingle, vmagent, vmalert, the operator, VLSingle, vlagent, kube-state-metrics, node-exporter, native scrapes and the kubernetes-mixin rules |
| `alertmanager` | `prometheus-community/alertmanager` | Routing, Pushover, Watchdog |
| `grafana` | `grafana-community/grafana` | UI, Authentik OIDC, data sources, dashboards from the repo |
| `vector` | `vector/vector` | Receiver for the Talos node logs |

### VictoriaMetrics (metrics)

```yaml
Retention: 14 days
Storage: 40Gi PVC on longhorn-monitoring (vmsingle-vmks)
Scrape interval: 30s (vmagent-vmks), rule evaluation 30s (vmalert-vmks)
Series: about 280k live (the API server histograms were 60% of what Prometheus kept)
```

- **Native scrapes** (`operators/victoria-metrics/values.yaml`): kubelet (the cAdvisor allowlist keeps only the container metrics that rules and dashboards need), API server (a drop rule removes nine unused histogram families), etcd (`10.0.10.130-132:2381`, plain HTTP on Talos), CoreDNS (job name `coredns`), kube-state-metrics and node-exporter. Controller manager, scheduler and kube-proxy are not scraped.
- **Converter**: the operator turns the `ServiceMonitor`, `PodMonitor` and `PrometheusRule` objects of the other apps (argo-cd, cilium, longhorn, cnpg, cert-manager, ...) into VM objects. The Prometheus Operator CRDs therefore stay installed; they are annotated `argocd.argoproj.io/sync-options: Prune=false,Delete=false` because no Argo app owns them any more.
- **Resources**: the whole `monitoring` namespace uses about 1.8 GiB of memory (was 3.0 GiB with Prometheus, Loki and Promtail).

### VictoriaLogs (logs)

```yaml
Retention: 14 days
Storage: 10Gi PVC on longhorn-monitoring, hard cap retention.maxDiskSpaceUsageBytes=8GiB
Container logs: vlagent DaemonSet (all nodes, reads /var/log/pods)
Talos logs: Vector (tcp://10.0.10.242:5140) -> /insert/jsonline
```

Stream fields: container logs `kubernetes.pod_namespace`, `kubernetes.pod_name`, `kubernetes.container_name`; Talos logs `node` and `talos-service` (machined, kubelet, etcd, cri, apid, kernel, ...).

### Talos node logs

Talos can only send `json_lines` over raw TCP or UDP (`machine.logging` in `resources/bootstrap/talos/machine-config/*.tftpl`). VictoriaLogs takes JSON over HTTP, so Vector sits in between: a LoadBalancer Service with the fixed IP `10.0.10.242` (Cilium LB-IPAM, announced on L2), TCP 5140, an `http` sink to vlsingle. The node name is added with `extraTags` (`node: <hostname>`). Applying `machine.logging` needs no reboot. Talos replays the kernel ring buffer once when it starts to log (about 5k lines per node).

If the nodes cannot reach `10.0.10.242:5140`, the `TalosLogsMissing` alert fires after 30 minutes; delivery errors raise `VectorDeliveryErrors`.

### Alertmanager

```yaml
route:
  group_by: ['alertname', 'namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 24h          # fallback
  receiver: 'pushover-warning'
  routes:
    - Watchdog        -> healthchecks-watchdog (every 30m, dead man's switch)
    - InfoInhibitor   -> null
    - severity=critical -> pushover-critical (priority 1, repeat 4h)
    - severity=warning  -> pushover-warning  (priority 0, repeat 24h)
```

Pushover **critical** (priority 1) bypasses Do Not Disturb; **warning** (priority 0) is a normal notification. The service is `alertmanager.monitoring:9093`, the pod `alertmanager-0` (2Gi on `longhorn-standard`). Secrets (`alertmanager-pushover`, `alertmanager-healthchecks`) come from 1Password through External Secrets.

### Grafana

```yaml
URL: https://grafana.svc.damman.tech (Authentik OIDC, admin credentials in 1Password: grafana-admin)
Storage: 5Gi on longhorn-standard (fresh database; users come back through OIDC)
Data sources (provisioned from the values):
  - VictoriaMetrics (default, uid "prometheus"): http://vmsingle-vmks.monitoring.svc:8428
  - VictoriaLogs (uid "victorialogs"): http://vlsingle-vmks.monitoring.svc:9428
```

The uid of the metrics data source stays `prometheus` because the dashboards refer to it.

---

## Dashboards (GitOps)

Dashboards are not created by hand: one ConfigMap per dashboard, rendered from JSON files in `operators/grafana/dashboards/<folder>/` and picked up by the Grafana sidecar (label `grafana_dashboard=1`, folder from the `grafana_folder` annotation).

| Folder | Dashboards |
|--------|-----------|
| Kubernetes | Compute resources (cluster, namespace pods/workloads, node, nodes overview, pod, workload), API server, Kubelet, etcd, CoreDNS, Persistent Volumes |
| Nodes | Node Exporter Nodes, USE method cluster and node |
| Longhorn | grafana.com 16888 |
| Argo CD | grafana.com 14584 |
| Cilium | agent, operator, Hubble (metrics, DNS, L7 HTTP, network overview) from the Cilium 1.20.4 chart |
| PostgreSQL | CloudNativePG (cloudnative-pg chart 0.29.1) |
| (root) | Trivy, from `operators/trivy-operator/dashboards` |

To add a dashboard: put the JSON in the right folder under `operators/grafana/dashboards/` and merge (the template maps `${DS_PROMETHEUS}` to the `prometheus` data source uid). Dashboards edited in the UI are not saved (`allowUiUpdates: false`).

---

## Storage Layout

| Component | Storage | Retention | StorageClass | Replicas |
|-----------|---------|-----------|--------------|----------|
| vmsingle | 40Gi | 14 days | longhorn-monitoring | 1 (strict-local) |
| vlsingle | 10Gi (8GiB cap) | 14 days | longhorn-monitoring | 1 (strict-local) |
| Grafana | 5Gi | — | longhorn-standard | 2 |
| Alertmanager | 2Gi | — | longhorn-standard | 2 |

**`longhorn-monitoring`**: 1 replica, strict-local data locality, no backups. Metrics and logs are regenerated continuously, so losing history is acceptable. The volumes are unavailable while their node reboots.

---

## Secrets Management

```yaml
# 1Password items
grafana-admin:        # vault KubernetesSecrets, field password
grafana-oidc:         # client_id, client_secret
pushover-credentials: # username (user-key), password (api-token)
alertmanager-healthchecks: # ping-url
```

---

## Proxmox VE Monitoring

**Status:** Operational (deployed 2026-01-12)
**Chart:** christianhuth/prometheus-pve-exporter v2.7.1 (app v3.8.0)
**Authentication:** Password-based (`monitoring@pve` user with PVEAuditor role)

**Targets:**
- 10.0.10.200 (dmn-sk-pve-01) — UP
- Scrape interval: 60s (Proxmox API performance consideration)

**Key metrics (45+ `pve_*` available):**
- `pve_up` — Node/VM/storage status
- `pve_cpu_usage_ratio` — CPU usage (0.0–1.0)
- `pve_memory_usage_bytes` / `pve_memory_size_bytes`
- `pve_cluster_quorate` — Cluster quorum status

**Alert rules:**
- **ProxmoxNodeDown** (critical): Node offline >5min
- **ProxmoxClusterNoQuorum** (critical): Cluster lost quorum >2min
- **ProxmoxStorageCritical** (critical): Storage >95% for >5min
- **ProxmoxHighCPU** (warning): CPU >90% for >15min
- **ProxmoxHighMemory** (warning): Memory >90% for >15min
- **ProxmoxStorageFull** (warning): Storage >85% for >10min
- **ProxmoxVMDown** (warning): VM stopped/crashed >5min (was running in last 4h)

**Configuration:** `resources/gitops-config/infrastructure/prometheus-pve-exporter/`

---

## Alert Severity Levels

| Level | Priority | Behavior | Examples |
|-------|----------|----------|---------|
| **critical** | 1 | Bypass DND, repeat every 4h | Node down, etcd unhealthy, PVC full |
| **warning** | 0 | Normal notification, repeat every 24h | High CPU, cert expiring, sync failed |
| **info** | — | No notification (InfoInhibitor) | Informational alerts |

### Rules

| Where | What |
|-------|------|
| `operators/victoria-metrics/rules/*.yaml` (VMRules, rendered by `templates/rules.yaml`) | The kubernetes-mixin set that kube-prometheus-stack used to deploy: recording rules for the dashboards and the `kubernetes-*`, `node-exporter`, `etcd`, `kube-state-metrics`, API server alerts, plus `victoria-metrics.yaml` (disk space, remote write, rule errors) |
| `operators/alertmanager/templates/prometheusrule.yaml` | Alertmanager reload, notification failures, down, crashloop |
| `operators/vector/templates/vmrule.yaml` | Vector delivery errors, no Talos logs for 30 minutes |
| `operators/longhorn/templates/prometheusrule.yaml` | `LonghornVolumeBackupTooOld`: a `longhorn-fast`/`longhorn-standard` volume has no backup younger than 36h (also when it never had one), for 1h |
| `operators/descheduler/templates/prometheusrule.yaml` | `WorkerPodDistributionSkewed`: the busiest worker has more than 1.4x the Running CPU requests of the quietest one, for 2h |
| `operators/trivy-operator/templates/prometheusrule.yaml` | Trivy findings |
| `infrastructure/prometheus-pve-exporter/templates/prometheusrule.yaml` | `Proxmox*`, `KubeNodeHighMemory` |

A failed Longhorn backup job is covered by `KubeJobFailed`. The `PrometheusRule` files are converted to VMRules by the operator.

---

## Querying

VictoriaMetrics speaks PromQL (with MetricsQL extensions). Grafana data source `VictoriaMetrics` is the default.

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

### LogsQL examples (data source `VictoriaLogs`)

```logsql
# All logs from a namespace
_stream:{kubernetes.pod_namespace="home-assistant"}

# Errors in a namespace
_stream:{kubernetes.pod_namespace="argocd"} error

# Errors per namespace
level:error | stats by (kubernetes.pod_namespace) count() errors | sort by (errors desc)

# Talos logs of one node, kubelet only
_stream:{node="prd-w-01",talos-service="kubelet"}

# Everything one node logged about an error, per container
kubernetes.pod_node_name:prd-w-01 AND (error OR fail*) | stats by (kubernetes.container_name) count() hits | sort by (hits desc)
```

Longhorn writes logfmt, so its level is not a field: `... | unpack_logfmt fields (level) | filter level:warning`.

---

## Access

```bash
# Grafana
https://grafana.svc.damman.tech

# Port forwarding for debugging
kubectl port-forward -n monitoring svc/vmsingle-vmks 8428:8428      # metrics UI, /vmui
kubectl port-forward -n monitoring svc/vmagent-vmks 8429:8429       # /targets
kubectl port-forward -n monitoring svc/vmalert-vmks 8080:8080       # rules and alerts
kubectl port-forward -n monitoring svc/vlsingle-vmks 9428:9428      # logs UI, /select/vmui
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
```

---

## Configuration Files

| Path | Description |
|------|-------------|
| `operators/victoria-metrics/values.yaml` | VMSingle, vmagent, vmalert, VLSingle, vlagent, native scrapes |
| `operators/victoria-metrics/templates/` | CiliumNetworkPolicies and the rules template |
| `operators/victoria-metrics/rules/` | The kubernetes-mixin VMRules |
| `operators/alertmanager/values.yaml` | Alertmanager config (routes, receivers, templates) |
| `operators/alertmanager/templates/externalsecret-*.yaml` | Pushover and healthchecks.io secrets |
| `operators/grafana/values.yaml` | Grafana config (OIDC, data sources, sidecar) |
| `operators/grafana/dashboards/` | The dashboards |
| `operators/grafana/templates/` | ExternalSecrets, HTTPRoute, CiliumNetworkPolicy, dashboard ConfigMaps |
| `operators/vector/` | Vector, receiver for the Talos logs |
| `resources/bootstrap/talos/machine-config/*.tftpl` | `machine.logging` of the nodes |

---

## Troubleshooting

```bash
# Targets (all should be up)
kubectl port-forward -n monitoring svc/vmagent-vmks 8429:8429     # http://localhost:8429/targets

# Rules that fail to evaluate
kubectl port-forward -n monitoring svc/vmalert-vmks 8080:8080     # the vmalert UI on http://localhost:8080
kubectl logs -n monitoring deploy/vmalert-vmks -c vmalert --tail=50

# Alertmanager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093     # http://localhost:9093/#/status

# Test notification
kubectl exec -n monitoring -it alertmanager-0 -c alertmanager -- \
  amtool alert add test severity=critical namespace=test --alertmanager.url=http://localhost:9093
```

| Issue | Symptom | Solution |
|-------|---------|---------|
| Watchdog pings stop | healthchecks.io "dead man's switch is DOWN" | vmalert cannot evaluate: check `kubectl logs deploy/vmalert-vmks`, its CiliumNetworkPolicy (it queries `vmauth-vmks-internal:8427`) and Alertmanager |
| Target down after a chart bump | `up == 0` / `TargetDown` | Service labels or port names changed: compare with the VMServiceScrape; check the CiliumNetworkPolicy of that namespace allows `vmagent` |
| No logs of a pod | Empty `_stream` query | Check the vlagent pod on that node and its policy (egress to vlsingle 9428 and the API server) |
| No Talos logs | `TalosLogsMissing` | Check `machine.logging` on the node and that `10.0.10.242:5140` is reachable; `kubectl logs deploy/vector` |
| Grafana pod crash-loops | `data source with the same uid already exists` | Renaming a data source while keeping its uid needs `deleteDatasources` for the old name |
| Missing dashboard | Not in the folder | Check the ConfigMap `grafana-dashboard-<name>` and the sidecar log (`grafana-sc-dashboard`) |

---

## Changelog

### 2026-11-21
- **Migration**: kube-prometheus-stack, Loki and Promtail replaced by VictoriaMetrics and VictoriaLogs; Alertmanager and Grafana are their own apps; dashboards are provisioned from the repo; Talos node logs go to VictoriaLogs through Vector. The `monitoring` namespace went from about 3.0 GiB to about 1.8 GiB of memory.

### 2026-01-27
- **Storage Optimization**: Introduced `longhorn-monitoring` StorageClass for ephemeral monitoring data (1 replica, strict-local, no backups). Significantly reduces disk I/O.

### 2026-01-12
- Added prometheus-pve-exporter for Proxmox VE hypervisor monitoring
- 7 new Proxmox alert rules (3 critical, 4 warning)
