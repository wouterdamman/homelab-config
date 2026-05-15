# Firefly III Configuration

**Source:** `resources/gitops-config/applications/firefly-iii/`
**Application:** [Firefly III](https://www.firefly-iii.org/) — Personal Finance Manager

---

## Overview

Firefly III is a self-hosted personal finance manager for budgeting, expense tracking, and financial insights. Runs on Kubernetes with PostgreSQL via CloudNative-PG.

| Property | Value |
|----------|-------|
| Namespace | `firefly-iii` |
| Image | `fireflyiii/core:version-6.1.21` |
| Replicas | 1 |
| URL | https://budget.app.damman.tech |
| Database | `cnpg-shared` cluster, `firefly` database |
| Storage | 10Gi PVC for uploads |

---

## Architecture

```
Internet
  ↓
Cilium Gateway (app-gateway)
  ↓
HTTPRoute (budget.app.damman.tech)
  ↓
Service (firefly:8080)
  ↓
Pod (fireflyiii/core:6.1.21)
  ↓
CloudNative-PG (cnpg-shared-rw:5432)
```

### Deployment Strategy

```yaml
strategy:
  type: Recreate
```

Recreate is required because the PVC can't be mounted by multiple pods, and database migrations require a single instance.

---

## Environment Configuration

```yaml
APP_ENV: production
APP_URL: https://budget.app.damman.tech
TRUSTED_PROXIES: "**"
TZ: Europe/Amsterdam
APP_LOCALE: nl_NL
DKR_CHECK_SQLITE: "false"
```

### Database (via ExternalSecret)

```yaml
DB_CONNECTION: pgsql
DB_HOST: cnpg-shared-rw.cnpg-system.svc.cluster.local
DB_PORT: "5432"
DB_DATABASE: firefly
DB_USERNAME: firefly
DB_PASSWORD: <from secret>
```

### Application Key

```yaml
APP_KEY: <from secret>  # Format: base64:<key>
```

> **IMPORTANT:** APP_KEY must have Laravel's `base64:` prefix:
> ```bash
> base64:$(openssl rand -base64 32)
> ```

---

## Secrets Management

| 1Password Item | Fields | Purpose |
|---------------|--------|---------|
| `cnpg-shared-firefly` | host, port, database, username, password | Database credentials |
| `firefly-app-key` | key | Laravel encryption key |

### ExternalSecret Template Note

The ExternalSecret uses escaped Helm template syntax to avoid conflicts:
```yaml
DB_HOST: '{{ `{{ .dbHost }}` }}'
```

---

## Database

- **Cluster:** `cnpg-shared`
- **Endpoint:** `cnpg-shared-rw.cnpg-system.svc.cluster.local:5432`
- **Database:** `firefly`
- **User:** `firefly` (dedicated, least-privilege)

Database initialized automatically via ArgoCD PostSync job `cnpg-init-firefly.yaml`.

---

## Storage

```yaml
PVC: firefly-data
Size: 10Gi
StorageClass: longhorn-standard
MountPath: /var/www/html/storage/upload
```

Used for: uploaded attachments (receipts, invoices), import/export files, profile pictures.

---

## Health Checks

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 60
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
```

---

## Resource Allocation

```yaml
requests:
  cpu: 100m
  memory: 256Mi
limits:
  cpu: 500m
  memory: 512Mi
```

---

## Authentication

**Current:** Email/password (local user database)

**Future SSO:** No native OIDC support. Options:
1. **Forward Authentication** via Authentik — possible but complex with Cilium Gateway API
2. **Wait for native OIDC** — feature request [#10662](https://github.com/firefly-iii/firefly-iii/issues/10662)

See **ADR-023** for the full decision.

---

## Useful Commands

```bash
# Check pod status
kubectl get pods -n firefly-iii

# Logs
kubectl logs -n firefly-iii -l app.kubernetes.io/name=firefly-iii -f

# Check ExternalSecret
kubectl get externalsecret -n firefly-iii
kubectl describe externalsecret firefly-secrets -n firefly-iii

# Restart
kubectl rollout restart deployment/firefly -n firefly-iii
```

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|---------|
| `APP_KEY is empty` | ExternalSecret not synced | Check ExternalSecret status and 1Password item |
| `Unsupported cipher or incorrect key length` | APP_KEY missing `base64:` prefix | Regenerate: `base64:$(openssl rand -base64 32)` |
| `could not connect to server` | Database not ready | Check CNPG cluster status and init job |
| `role "firefly" does not exist` | Database init job failed | Check `cnpg-init-firefly` job logs |

### Database Connection Check

```bash
PRIMARY_POD=$(kubectl get pods -n cnpg-system -l cnpg.io/cluster=cnpg-shared,role=primary -o jsonpath='{.items[0].metadata.name}')

# Check database exists
kubectl exec -n cnpg-system $PRIMARY_POD -- psql -U postgres -c "\l" | grep firefly

# Check user exists
kubectl exec -n cnpg-system $PRIMARY_POD -- psql -U postgres -c "\du" | grep firefly
```

---

## Maintenance

### Credential Rotation

```bash
# 1. Generate new password and update in 1Password
# 2. Wait for ExternalSecret sync
kubectl get externalsecret -n firefly-iii -w

# 3. Update database user password
kubectl exec -n cnpg-system $PRIMARY_POD -- psql -U postgres -c \
  "ALTER USER firefly WITH PASSWORD 'new-password';"

# 4. Restart pod
kubectl rollout restart deployment/firefly -n firefly-iii
```

### Updates

Update `tag` in values.yaml — ArgoCD auto-syncs with Recreate strategy.

**Backups:** Database via CloudNative-PG, upload files via Longhorn snapshots.
