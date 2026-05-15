# Longhorn Configuration

**Source:** `resources/gitops-config/operators/longhorn/values.yaml`
**Helm Chart:** [Longhorn](https://longhorn.io/docs/)

---

## Overview

Longhorn is the distributed block storage system for the cluster, providing persistent volumes with replication and S3 backups to Hetzner Object Storage.

---

## Configuration

### Backup Settings

```yaml
defaultBackupStore:
  backupTarget: s3://homelab-prd@nbg1/longhorn-backup/
  backupTargetCredentialSecret: longhorn-s3-secret
  pollInterval: 300

defaultSettings:
  backupCompressionMethod: lz4
  backupConcurrentLimit: 2
  restoreConcurrentLimit: 2
```

### Storage Settings

```yaml
defaultSettings:
  storageMinimalAvailablePercentage: 15
  storageOverProvisioningPercentage: 200
  replicaAutoBalance: best-effort
  defaultDataLocality: best-effort
  snapshotMaxCount: 250
```

### Resilience Settings

```yaml
defaultSettings:
  nodeDownPodDeletionPolicy: delete-both-statefulset-and-deployment-pod
  nodeDrainPolicy: block-if-contains-last-replica
  replicaReplenishmentWaitInterval: 600
  concurrentReplicaRebuildPerNodeLimit: 5
  orphanAutoDeletion: true
```

---

## Storage Classes

Defined in `templates/storage-classes.yaml`:

| Class | Replicas | Reclaim | Use Case |
|-------|----------|---------|----------|
| `longhorn-fast` | 3 | Retain | Databases, critical data |
| `longhorn-standard` | 2 | Retain | General applications (default) |
| `longhorn-archive` | 1 | Delete | Logs, temporary data |

There is also `longhorn-monitoring` (1 replica, strict-local, no backups) used by Prometheus and Loki — see [Monitoring & Alerting](../monitoring/monitoring-alerting.md).

---

## Resource Limits

Resource limits are **not explicitly configured** in `values.yaml` — Longhorn uses its chart defaults. The values below are informational chart defaults only, not enforced via this repo's configuration.

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| Manager | 25m | 250m | 64Mi | 256Mi |
| Driver | 50m | 200m | 64Mi | 256Mi |
| UI | 5m | 200m | 32Mi | 256Mi |

---

## Scheduling

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Equal
    value: "true"
    effect: NoSchedule
```

Runs on all nodes including control-plane (required for distributed storage).

---

## Monitoring

```yaml
metrics:
  serviceMonitor:
    enabled: true
    additionalLabels:
      release: prometheus
```

**Key metrics:**
- `longhorn_volume_state` — Volume health state
- `longhorn_volume_actual_size_bytes` — Actual volume size
- `longhorn_backup_state` — Backup job state
- `longhorn_node_status` — Node health status

---

## Related Documentation

- [Longhorn Production-Grade Plan](longhorn-production-plan.md)
- [Longhorn Disaster Recovery Runbook](longhorn-dr-runbook.md)
