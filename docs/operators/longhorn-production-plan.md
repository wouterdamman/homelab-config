# Longhorn Production-Grade Plan

## Implementation Status

| Phase | Status | Notes |
|-------|--------|-------|
| **Phase 1: S3 Backup** | ✅ COMPLETED | Hetzner Object Storage operational, LZ4 compression |
| **Phase 2: Storage Tiers** | ✅ COMPLETED | 3-tier StorageClasses + RecurringJobs |
| **Phase 3: DR Procedures** | ✅ COMPLETED | Runbook + automated test scripts |
| **Phase 4: Monitoring** | ⏭️ DEFERRED | Waiting for monitoring stack deployment |

## Executive Summary

**Achieved**: RTO < 4h, RPO < 1h, 30-day backup retention, automated DR testing.

- S3 Backup to Hetzner Object Storage (LZ4 compressed, multi-retention)
- Disaster Recovery procedures and automated testing
- Performance Optimization with storage tiers
- Monitoring & Alerting via Prometheus/Grafana (deferred)

---

## Storage Tier Strategy

**Tier 1: Fast (Databases)**
- 3 replicas for high availability
- Hourly snapshots + daily backups
- Retain policy: keep on delete
- Use case: PostgreSQL, MariaDB, Redis

**Tier 2: Standard (Applications)**
- 2 replicas (balance cost/reliability)
- Daily backups, Delete policy
- **Default StorageClass**

**Tier 3: Archive (Logs)**
- 1 replica (cost-optimized)
- Monthly backups
- WaitForFirstConsumer binding

### StorageClass Definitions

```yaml
---
# Tier 1: Fast - High availability databases
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-fast
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "30"
  fsType: "ext4"
  dataLocality: "best-effort"
  replicaAutoBalance: "least-effort"
  recurringJobSelector: |
    - name: backup-daily
      isGroup: false
    - name: snapshot-hourly
      isGroup: false
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Retain
volumeBindingMode: Immediate

---
# Tier 2: Standard - Default for applications
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-standard
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
parameters:
  numberOfReplicas: "2"
  staleReplicaTimeout: "30"
  fsType: "ext4"
  dataLocality: "best-effort"
  replicaAutoBalance: "least-effort"
  recurringJobSelector: |
    - name: backup-daily
      isGroup: false
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate

---
# Tier 3: Archive - Cost-optimized logs/archives
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-archive
parameters:
  numberOfReplicas: "1"
  staleReplicaTimeout: "60"
  fsType: "ext4"
  dataLocality: "disabled"
  replicaAutoBalance: "disabled"
  recurringJobSelector: |
    - name: backup-monthly
      isGroup: false
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

---

## Backup Configuration

### S3 Target (Hetzner Object Storage)

```
Bucket: homelab-prd
Path: /longhorn-backup/
Region: Nuremberg (nbg1)
Retention:
  - Daily backups: 30 days
  - Monthly backups: 365 days
Compression: LZ4
```

### Recurring Jobs

```yaml
---
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: backup-daily
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"  # 02:00 UTC daily
  task: backup
  groups:
    - default
  retain: 30
  concurrency: 2

---
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: backup-monthly
  namespace: longhorn-system
spec:
  cron: "0 3 1 * *"  # 1st of month, 03:00 UTC
  task: backup
  groups:
    - default
  retain: 12
  concurrency: 1

---
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: snapshot-hourly
  namespace: longhorn-system
spec:
  cron: "0 * * * *"  # Every hour
  task: snapshot
  groups:
    - default
  retain: 24
  concurrency: 2
```

---

## Monitoring & Alerting (Phase 4)

### PrometheusRule Alert Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: longhorn-alerts
  namespace: longhorn-system
spec:
  groups:
  - name: longhorn.rules
    interval: 30s
    rules:
    - alert: LonghornVolumeDegraded
      expr: longhorn_volume_robustness == 2
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Longhorn volume degraded"
        description: "Volume {{ $labels.volume }} is degraded for > 5 minutes"

    - alert: LonghornVolumeDetached
      expr: longhorn_volume_state == 2
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Longhorn volume detached"
        description: "Volume {{ $labels.volume }} is detached for > 5 minutes"

    - alert: LonghornBackupFailed
      expr: longhorn_backup_state == 3
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Longhorn backup failed"

    - alert: LonghornBackupTooOld
      expr: (time() - longhorn_backup_timestamp_seconds) > 90000  # 25 hours
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Longhorn backup too old"

    - alert: LonghornDiskSpaceLow
      expr: (longhorn_disk_capacity_bytes - longhorn_disk_usage_bytes) / longhorn_disk_capacity_bytes < 0.2
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Longhorn disk space low (<20%)"

    - alert: LonghornDiskSpaceCritical
      expr: (longhorn_disk_capacity_bytes - longhorn_disk_usage_bytes) / longhorn_disk_capacity_bytes < 0.1
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Longhorn disk space critical (<10%)"

    - alert: LonghornReplicaCountMismatch
      expr: longhorn_volume_number_of_replicas != longhorn_volume_actual_replica_count
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Longhorn replica count mismatch"

    - alert: LonghornNodeDown
      expr: longhorn_node_status == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Longhorn node down"
```

### Grafana Dashboard

Import Dashboard ID **13032** (Official Longhorn dashboard). Custom panels:
1. Backup Success Rate (last 7 days)
2. Volume Health Overview
3. Disk Space per Node
4. Replica Distribution
5. Backup Age (oldest backup per volume)

---

## Cost Analysis (Hetzner Object Storage)

- Storage: ~3 TB compressed → ~€16/month
- Download: €0.01/GB (only on restores)
- Compared to AWS S3 Standard: ~€70/month for same data

---

## Related Documentation

- [Longhorn Configuration](longhorn.md)
- [Longhorn Disaster Recovery Runbook](longhorn-dr-runbook.md)
