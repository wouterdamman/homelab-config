# Authentik Configuration

SSO and Authentication Platform for the homelab.

## Overview

Authentik provides centralized authentication and single sign-on (SSO) for homelab services via OAuth2/OIDC and forward authentication.

- **URL:** https://sso.svc.damman.tech / https://sso.app.damman.tech
- **Admin Portal:** https://sso.svc.damman.tech/if/admin/
- **User Portal:** https://sso.svc.damman.tech/if/user/
- **Namespace:** `authentik`
- **Admin User:** `akadmin`
- **Credentials:** 1Password → `authentik-admin`

---

## Architecture

### Components

| Component | Replicas | CPU (req/limit) | Memory (req/limit) | Purpose |
|-----------|----------|-----------------|--------------------|---------|
| authentik-server | 1 | 100m/750m | 640Mi/1280Mi | Web UI + API |
| authentik-worker | 1 | 100m/none | 384Mi/1024Mi | Background tasks |

### Database

| Setting | Value |
|---------|-------|
| Cluster | cnpg-shared |
| Database | authentik |
| User | authentik (dedicated, NOT postgres superuser) |
| Connection | cnpg-shared-rw.cnpg-system.svc.cluster.local:5432 |

### Secrets (1Password)

| 1Password Item | Kubernetes Secret | Namespace | Purpose |
|---------------|-------------------|-----------|---------|
| cnpg-shared-authentik | authentik-db-credentials | authentik | Database credentials |
| authentik-secret-key | authentik-secret-key | authentik | Session encryption (**NEVER change!**) |
| authentik-admin | authentik-bootstrap-password | authentik | Admin password |

---

## Configuration

### Outpost (Forward Auth)

Authentik uses an embedded outpost for forward authentication:
- **Endpoint:** https://sso.svc.damman.tech/outpost.goauthentik.io
- **Mode:** Domain-level forward auth

### Forward Auth Integration

To protect a service with Authentik forward auth:

1. **Create Proxy Provider** in Authentik UI:
   - Applications → Providers → Create
   - Type: Proxy Provider, Mode: Forward auth (domain level)
   - External host: `https://[service].svc.damman.tech`

2. **Create Application** in Authentik:
   - Applications → Applications → Create
   - Link to created provider

3. **Update service HTTPRoute** with forward auth filter

### Protected Services

| Service | URL | Auth Method | Status |
|---------|-----|-------------|--------|
| Grafana | grafana.svc.damman.tech | Forward auth | Planned |
| ArgoCD | argocd.svc.damman.tech | OAuth2/OIDC | Planned |
| Longhorn | longhorn.svc.damman.tech | Forward auth | Planned |
| Prometheus | prometheus.svc.damman.tech | Forward auth | Planned |
| NetBox | netbox.svc.damman.tech | OIDC | ✅ Live |
| Homarr | homarr.app.damman.tech | OIDC | ✅ Live |

---

## Operations

### Health Check

```bash
# Pod status
kubectl get pods -n authentik

# Logs
kubectl logs -n authentik -l app.kubernetes.io/component=server --tail=50

# Health endpoint
kubectl exec -n authentik deploy/authentik-server -- \
  wget -O- http://localhost:9000/-/health/ready/
```

### Database Check

```bash
# Verify database exists
kubectl exec -n cnpg-system cnpg-shared-1 -c postgres -- \
  psql -U postgres -c '\l' | grep authentik

# Test connectivity
kubectl exec -n authentik deploy/authentik-server -- \
  pg_isready -h cnpg-shared-rw.cnpg-system.svc.cluster.local -p 5432
```

---

## Monitoring

- **ServiceMonitor:** Enabled
- **Metrics endpoint:** http://authentik-server:9300/metrics
- **Grafana Dashboard:** Import ID 14837 (Authentik Overview)

**Key metrics:**
- `authentik_system_runtime_uptime_seconds` — Uptime
- `authentik_outposts_connected` — Outpost status
- `authentik_http_requests_total` — Request count
- `authentik_models_user_total` — User count

---

## Backup & Recovery

Database backed up daily via CloudNative-PG to Hetzner Object Storage:
- **Retention:** 14 days
- **Schedule:** Daily at 03:00 UTC
- **Location:** `s3://homelab-prd/cnpg-backup/shared/`

See [CloudNative-PG docs](cloudnative-pg.md) for restore procedures.

---

## Troubleshooting

### Database connection failed

```bash
kubectl get cluster -n cnpg-system cnpg-shared
kubectl get secret -n authentik authentik-db-credentials -o yaml
```

### Permission denied for schema public

```bash
PRIMARY=cnpg-shared-1
kubectl exec -n cnpg-system $PRIMARY -c postgres -- \
  psql -U postgres -d authentik -c "GRANT ALL ON SCHEMA public TO authentik;"
kubectl exec -n cnpg-system $PRIMARY -c postgres -- \
  psql -U postgres -d authentik -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO authentik;"
```

### Redis connection failed

```bash
kubectl get pods -n authentik -l app.kubernetes.io/name=redis
kubectl exec -n authentik -l app.kubernetes.io/name=redis -- redis-cli ping
```

### Cannot login with akadmin

- Password in 1Password → `authentik-admin`
- Recovery flow: https://sso.svc.damman.tech/if/flow/default-recovery-flow/
- Or reset via kubectl:
  ```bash
  kubectl exec -n authentik deploy/authentik-worker -- \
    ak create_admin_group --username akadmin
  ```

### All pods CrashLoopBackOff

```bash
kubectl logs -n authentik -l app.kubernetes.io/name=authentik --tail=100
# Common causes: DB connection failed, secret key missing, Redis not ready
```

---

## Security Considerations

- **CRITICAL:** Never change `authentik-secret-key` after deployment — it invalidates all sessions and encrypted data
- Enable MFA for akadmin after first login
- Database credentials rotated via 1Password; connection encrypted via PostgreSQL SSL (CNPG default)
