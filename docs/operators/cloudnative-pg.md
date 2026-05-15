# CloudNative-PG Configuration

**Source:** `resources/gitops-config/operators/cloudnative-pg/`
**Helm Chart:** [CloudNative-PG](https://cloudnative-pg.io/documentation/current/)

---

## Overview

CloudNative-PG is the Kubernetes-native PostgreSQL operator for the homelab. It manages PostgreSQL clusters with automatic failover, backups to S3, and monitoring.

---

## Clusters

| Cluster | Purpose | Instances | Storage | Backup Schedule | Retention |
|---------|---------|-----------|---------|-----------------|-----------|
| **cnpg-shared** | Authentik, NetBox, future apps | 2 (1 primary + 1 replica) | 5Gi | Daily @ 03:00 | 30 days |
| **cnpg-homeassistant** | Home Assistant recorder | 2 (1 primary + 1 replica) | 10Gi | Every 6 hours | 30 days |

---

## Service Endpoints

| Cluster | Service | Endpoint |
|---------|---------|----------|
| cnpg-shared | Read-Write | `cnpg-shared-rw.cnpg-system.svc.cluster.local:5432` |
| cnpg-shared | Read-Only | `cnpg-shared-ro.cnpg-system.svc.cluster.local:5432` |
| cnpg-homeassistant | Read-Write | `cnpg-homeassistant-rw.cnpg-system.svc.cluster.local:5432` |
| cnpg-homeassistant | Read-Only | `cnpg-homeassistant-ro.cnpg-system.svc.cluster.local:5432` |

---

## Databases

### cnpg-shared
- `authentik` — Authentik SSO/authentication database
- `netbox` — NetBox IPAM/DCIM database

### cnpg-homeassistant
- `homeassistant` — Home Assistant recorder database

---

## Database Users & Security

Each application has a dedicated database user with least-privilege access.

**cnpg-shared cluster:**
- `authentik` — Full access to `authentik` database only
- `netbox` — Full access to `netbox` database only
- `postgres` — Superuser (admin operations only)

**cnpg-homeassistant cluster:**
- `homeassistant` — Full access to `homeassistant` database
- `postgres` — Superuser (admin operations only)

### Security Best Practices
1. ✅ **Dedicated users per application** — No shared credentials
2. ✅ **Least privilege** — Users have access to their own database only
3. ✅ **Passwords via 1Password** — Never in Git or config files
4. ✅ **Automatic rotation support** — Update password in 1Password, restart pods
5. ✅ **Superuser for admin only** — Applications use dedicated users

---

## Database Initialization (GitOps)

### Overview

Database and user provisioning is managed via GitOps with ArgoCD PostSync hooks. Jobs run automatically **after** the database cluster is deployed.

### Job Pattern

Each database has a dedicated init Job:
- `cnpg-init-authentik.yaml`
- `cnpg-init-firefly.yaml`
- `cnpg-init-netbox.yaml`

**ArgoCD Hook Configuration:**

```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

### Implementation

```bash
#!/bin/bash
set -e

# Find primary pod dynamically
PRIMARY_POD=$(kubectl get pods -n cnpg-system \
  -l cnpg.io/cluster=cnpg-shared,role=primary \
  -o jsonpath='{.items[0].metadata.name}')

# Create database (idempotent with DO block)
kubectl exec -n cnpg-system "$PRIMARY_POD" -c postgres -- psql -U postgres -c \
  "DO \$\$ BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'firefly') THEN
     CREATE DATABASE firefly OWNER postgres;
   END IF;
   END \$\$;"

# Create user (idempotent)
kubectl exec -n cnpg-system "$PRIMARY_POD" -c postgres -- psql -U postgres -c \
  "DO \$\$ BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'firefly') THEN
     CREATE USER firefly WITH PASSWORD '$FIREFLY_PW';
   END IF;
   END \$\$;"

# Grant privileges
kubectl exec -n cnpg-system "$PRIMARY_POD" -c postgres -- psql -U postgres -c \
  "GRANT ALL PRIVILEGES ON DATABASE firefly TO firefly;"
```

### Key Learnings

**What Doesn't Work:**
1. `postInitSQL` — Only runs at bootstrap, not for existing clusters
2. TCP connections from Job containers — Password auth fails with CNPG
3. Heredocs with kubectl exec — Silent failures

**What Works:**
1. `kubectl exec` with inline SQL (using `-c` flag)
2. Peer authentication (exec into pod = local connection)
3. Dynamic pod discovery (label selectors find primary pod)
4. Idempotent DO blocks (safe to rerun)
5. ArgoCD PostSync hooks (automatic after cluster deployment)

---

## Backup Configuration

### S3 Target

```yaml
backup:
  barmanObjectStore:
    destinationPath: s3://homelab-prd/cnpg-backup/<cluster>/
    endpointURL: https://nbg1.your-objectstorage.com
    s3Credentials:
      accessKeyId:
        name: cnpg-s3-secret
        key: ACCESS_KEY_ID
      secretAccessKey:
        name: cnpg-s3-secret
        key: ACCESS_SECRET_KEY
    wal:
      compression: gzip
    data:
      compression: gzip
```

---

## Backup Validation

### Overview

Weekly automated restore testing validates that backups are usable by actually performing restores from S3.

- **Frequency:** Every Sunday @ 04:00 UTC
- **Method:** Full S3 restore to temporary test cluster
- **Validation:** Data integrity check (database count, connectivity)
- **Cleanup:** Automatic removal of test resources
- **Notifications:** Pushover alerts (success/warning/failure)

### Notification Priorities

| Result | Priority | Details |
|--------|----------|---------|
| ✅ Success | -1 (Low) | Cluster name, backup time, database count, S3 source |
| ⚠️ Warning | 0 (Normal) | Fewer databases than expected, backup age issue |
| ❌ Failure | 1 (High) | Restore failed, timeout, connection error |

### Manual Test Trigger

```bash
# Trigger validation manually
kubectl create job --from=cronjob/cnpg-backup-validation \
  manual-test-$(date +%s) -n cnpg-system

# Follow logs
kubectl logs -f job/manual-test-{timestamp} -n cnpg-system
```

---

## Resource Limits

| Component | Requests CPU | Requests Memory | Limits CPU | Limits Memory |
|-----------|-------------|----------------|------------|--------------|
| Operator | 50m | 100Mi | 500m | 256Mi |
| cnpg-shared Instances | 100m | 256Mi | 500m | 512Mi |
| cnpg-homeassistant Instances | 200m | 256Mi | 1000m | 512Mi |

---

## Secrets (1Password)

| Item | Purpose | Vault |
|------|---------|-------|
| `cnpg-s3-backup` | Hetzner credentials | KubernetesSecrets |
| `cnpg-shared-superuser` | Shared cluster superuser | KubernetesSecrets |
| `cnpg-shared-authentik` | Authentik DB user | KubernetesSecrets |
| `cnpg-shared-netbox` | NetBox DB user | KubernetesSecrets |
| `cnpg-homeassistant-superuser` | HA cluster superuser | KubernetesSecrets |
| `cnpg-homeassistant-app` | Home Assistant DB user | KubernetesSecrets |

---

## Useful Commands

```bash
# Check cluster status
kubectl get clusters -n cnpg-system
kubectl get pods -n cnpg-system -l cnpg.io/cluster

# Connect to database
kubectl exec -it -n cnpg-system cnpg-shared-1 -- psql -U postgres
kubectl exec -it -n cnpg-system cnpg-homeassistant-1 -- psql -U homeassistant -d homeassistant

# Check backups
kubectl get backups -n cnpg-system
kubectl get scheduledbackups -n cnpg-system

# Manual backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: cnpg-shared-manual-$(date +%Y%m%d%H%M)
  namespace: cnpg-system
spec:
  cluster:
    name: cnpg-shared
EOF
```

---

## PostgreSQL Tuning

### Shared Cluster

```yaml
postgresql:
  parameters:
    shared_buffers: "64MB"
    effective_cache_size: "192MB"
    max_connections: "100"
```

### Home Assistant Cluster

```yaml
postgresql:
  parameters:
    shared_buffers: "128MB"
    effective_cache_size: "384MB"
    max_connections: "50"
    synchronous_commit: "off"  # Optimized for high write throughput
    wal_writer_delay: "200ms"
```

---

## Troubleshooting

### WAL Archiving Issues

```bash
# Check WAL archiving status
kubectl exec -it -n cnpg-system cnpg-shared-1 -- psql -U postgres -c "SELECT * FROM pg_stat_archiver;"

# Force WAL switch and archive
kubectl exec -it -n cnpg-system cnpg-shared-1 -- psql -U postgres -c "SELECT pg_switch_wal();"

# Check barman status
kubectl cnpg status cnpg-shared -n cnpg-system
```

### Force First Backup

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: cnpg-shared-initial
  namespace: cnpg-system
spec:
  cluster:
    name: cnpg-shared
  target: prefer-standby
EOF
```

| Issue | Cause | Solution |
|-------|-------|---------|
| WAL not archiving | S3 credentials incorrect | Check ExternalSecret sync status |
| Backup failed | No base backup exists | Wait for first scheduled backup or trigger manual |
| Restore fails | WAL files missing | Ensure continuous archiving is working |
