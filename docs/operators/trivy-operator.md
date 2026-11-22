# Trivy Operator

**Source:** `resources/gitops-config/operators/trivy-operator/`

---

## Overview

Trivy Operator scans the running workloads for CVEs and exposed secrets and stores the results as `VulnerabilityReport` and `ExposedSecretReport` objects. Its metrics feed the Trivy Deep Dive dashboard and the alerts in `templates/vmrule.yaml` (`TrivyCriticalFixableCVE`, `TrivyOperatorDown`).

Config audit and RBAC assessment are on, infra assessment is off (the node-collector mounts `/etc/systemd`, which does not exist on Talos), and SBOM and compliance reports are off because nothing reads them.

---

## ClientServer mode

`trivy.mode: ClientServer` with `operator.builtInTrivyServer: true` runs a `trivy-server` StatefulSet in `trivy-system` next to the operator. The scan jobs send the image layers to the server instead of downloading the vulnerability database themselves.

Standalone mode did not work for workloads with several images (home-assistant, cilium, cnpg): the containers of one scan job share a single filesystem cache and lock each other out (`cache may be in use by another process`), so those workloads never got a report.

| Setting | Value | Why |
|---------|-------|-----|
| Server port | 4954 | Container port of `trivy-server`; the CiliumNetworkPolicy allows it from `trivy-system` |
| Server storage | 5 Gi PVC, `longhorn-archive` | 1 replica: the database is downloaded again if the volume is lost |
| Server resources | 50m / 256Mi requests, 1 CPU / 1Gi limits | |
| `trivy.timeout` | 20m | The home-assistant image (python site-packages, thousands of files) failed at the 5m default with `semaphore acquire: context deadline exceeded` |
| `operator.scanJobTimeout` | 25m | Stays above `trivy.timeout` so Trivy fails first |
| `scanJobsConcurrentLimit` | 1 | One scan at a time: scans compete with Longhorn and etcd for the NVMe on the single host |
| `scannerReportTTL` | 72h | Unchanged images are rescanned every 3 days; new or changed images are scanned at once |
| `severity` / `ignoreUnfixed` | `MEDIUM,HIGH,CRITICAL` / true | Only fixable findings, so the dashboard reads as a list of images to update |

---

## Network policy

`templates/networkpolicy.yaml` allows ingress on 4954 from `trivy-system` to the server, and egress from the scan jobs to the server on 4954. The server itself needs egress to pull the database from `mirror.gcr.io`.

---

## Monitoring

The operator exposes its metrics on the metrics port; vmagent scrapes them through the scrape in `operators/victoria-metrics/scrapes/`. `metricsVulnIdEnabled` and the other `metrics*Enabled` flags add per-finding series for the Deep Dive dashboard; watch the active series count if you add more.

The dashboard ConfigMap (`templates/grafana-dashboard.yaml`, `dashboards/trivy-deep-dive.json`) lands in the Grafana folder Trivy.

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| A workload has no report | `kubectl get pods,jobs -n trivy-system`; an `Error` scan job: `kubectl logs -n trivy-system <pod> -c <container>` |
| `context deadline exceeded` in a scan job | The image is large: raise `trivy.timeout` and `operator.scanJobTimeout` |
| Scan job cannot reach the server | The 4954 rules in `templates/networkpolicy.yaml` |
| Server restarts | Memory limit of 1Gi, large images peak |
