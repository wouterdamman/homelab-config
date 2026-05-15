# Homarr Configuration

Homarr is a modern, customizable dashboard for managing and accessing homelab services.

## Overview

**Purpose**: Centralized dashboard for service management, monitoring, and quick access
**Status**: ✅ Deployed (2026-02-09) — Live at https://homarr.app.damman.tech
**Documentation**: [Homarr Docs](https://homarr.dev/docs)

## Architecture

```
┌─────────────────────────────────────────────┐
│  Gateway (app-gateway) - homarr.app.damman.tech   │
└──────────────────────┬───────────────────────┘
                       │
         ┌──────────────┬───────────────┐
         │              │                │
    Homarr App       Redis     WebSocket
   (Next.js:3000) (Embedded) (Port:3001)
         │
         ▼
    PostgreSQL (cnpg-shared)
    Database: homarr
```

## Technical Specifications

| Item | Value |
|------|-------|
| Image | ghcr.io/homarr-labs/homarr:v1.61.0 |
| CPU | 200m request, 1000m limit |
| Memory | 512Mi request, **1Gi limit** ⚠️ |
| Storage | 5Gi (configs) + 1Gi (icons) |

> ⚠️ **Note:** 512Mi memory limit caused OOMKills. Increased to 1Gi.

## Database Configuration

| Setting | Value |
|---------|-------|
| Cluster | cnpg-shared |
| Database | homarr |
| User | homarr |
| Connection | cnpg-shared-rw.cnpg-system.svc.cluster.local:5432 |

**Credentials**: 1Password via ExternalSecret

## SSO Authentication (OIDC)

| Setting | Value |
|---------|-------|
| Provider | Authentik |
| Issuer | https://sso.app.damman.tech/application/o/homarr/ ⚠️ |
| Scopes | `openid email profile groups` |
| Redirect URI | https://homarr.app.damman.tech/api/auth/callback/oidc |

> ⚠️ **Critical:** Issuer URL **must include trailing slash** `/`

## Secrets Management

| Secret | 1Password Vault | Purpose |
|--------|----------------|---------|
| DATABASE_URL | cnpg-shared-homarr | PostgreSQL connection |
| SECRET_ENCRYPTION_KEY | homarr-oidc | Data encryption (64-char hex) |
| AUTH_OIDC_CLIENT_SECRET | homarr-oidc | OAuth client secret |

## Deployment Configuration

### Required Environment Variables

```bash
# Application
BASE_URL=https://homarr.app.damman.tech
TZ=Europe/Amsterdam

# Database
DATABASE_URL=postgresql://homarr:PASSWORD@host:5432/homarr

# Security (REQUIRED!)
SECRET_ENCRYPTION_KEY=<64-char-hex>

# OIDC
AUTH_PROVIDERS=oidc
AUTH_OIDC_ISSUER=https://sso.app.damman.tech/application/o/homarr/
AUTH_OIDC_CLIENT_ID=<client-id>
AUTH_OIDC_CLIENT_SECRET=<secret>
```

### Health Checks

```yaml
livenessProbe:
  initialDelaySeconds: 120  # Database migrations + Redis startup
  periodSeconds: 30
  failureThreshold: 6

readinessProbe:
  initialDelaySeconds: 90
  periodSeconds: 15
  failureThreshold: 6
```

## Troubleshooting

### Issue 1: Missing SECRET_ENCRYPTION_KEY
**Error:** "Invalid environment variables"
**Fix:** Generate 64-char hex: `openssl rand -hex 32`

### Issue 2: Wrong Port (7575 vs 3000)
**Error:** Probe EOF failures
**Fix:** Update containerPort to `3000`

### Issue 3: OIDC Issuer Mismatch
**Error:** `issuer property does not match`
**Fix:** Add trailing slash to issuer URL

```bash
# Correct
AUTH_OIDC_ISSUER=https://sso.app.damman.tech/application/o/homarr/

# Wrong
AUTH_OIDC_ISSUER=https://sso.app.damman.tech/application/o/homarr
```

### Issue 4: OOMKilled (Exit Code 137)
**Error:** Container crashes after ~28s
**Fix:** Increase memory limit to 1Gi

### Logs

```bash
kubectl logs -n homarr -l app.kubernetes.io/name=homarr --tail=100
kubectl logs -n homarr -l app.kubernetes.io/name=homarr | grep "Ready in"
```

## Backup Strategy

**Database**: CloudNative-PG (WAL + daily backups, 14-day retention)
**Config**: Longhorn snapshots (daily, 7-day) + S3 backups (14-day)

## Changelog

### 2026-02-09
- ✅ Deployed to production
- OIDC via Authentik
- Fixed: SECRET_ENCRYPTION_KEY missing
- Fixed: Port 7575 → 3000
- Fixed: OIDC issuer trailing slash
- Fixed: OOMKill (512Mi → 1Gi)
