# NetBox Configuration

NetBox is a web-based IPAM (IP Address Management) and DCIM (Data Center Infrastructure Management) platform for documenting and managing network infrastructure.

## Overview

**Purpose**: Central documentation and management platform for:
- IP address management (IPAM)
- VLAN/subnet planning
- Device inventory (servers, switches, access points)
- Cable management
- Rack layouts
- Circuit management

**Status**: ✅ Deployed (2026-02-09) — Live at https://netbox.svc.damman.tech

## Architecture

```
┌─────────────────────────────────────────────┐
│         Gateway API (svc-gateway)           │
│        netbox.svc.damman.tech               │
└───────────────┬─────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────┐
│          NetBox Application                 │
│          (Django/Python)                    │
│  - Web UI                                   │
│  - REST API                                 │
│  - GraphQL API (optional)                   │
└───────────────┬─────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────┐
│       CloudNative-PG (cnpg-shared)         │
│          PostgreSQL Database                │
│  Database: netbox                          │
└─────────────────────────────────────────────┘
```

## Technical Specifications

| Component | Image | Version |
|-----------|-------|---------|
| NetBox | netboxcommunity/netbox | v4.6.4 |
| Redis | redis | 8.8.0-alpine |

### Resource Requirements

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| NetBox | 200m | 1000m | 512Mi | 2Gi |
| Redis | 50m | 200m | 128Mi | 256Mi |

### Storage

| Purpose | Size | Storage Class | Mount Path |
|---------|------|---------------|-----------|
| Media files | 10Gi | longhorn-standard | /opt/netbox/netbox/media |

## Database Configuration

| Setting | Value |
|---------|-------|
| Cluster | cnpg-shared |
| Database Name | netbox |
| Username | netbox |
| Connection | cnpg-shared-rw.cnpg-system.svc.cluster.local:5432 |

## SSO Authentication (OIDC)

| Setting | Value |
|---------|-------|
| Provider | Authentik |
| Backend | `social_core.backends.open_id_connect.OpenIdConnectAuth` |
| Client ID | `xS0lvZfCpBNuTlbYF4a16Xvo0kEa5W4QmYzkVMOi` |
| Issuer URL | https://sso.svc.damman.tech/application/o/netbox/ |
| Scopes | `openid profile email` |

### Custom Pipeline

NetBox requires a custom OIDC pipeline to handle missing user fields (Authentik doesn't always provide `family_name`):

```python
def get_user_details(strategy, details, response, user=None, *args, **kwargs):
    """Extract user details from OIDC response with fallbacks"""
    out = {
        'username': details.get('username'),
        'email': details.get('email', ''),
        'first_name': details.get('first_name', ''),
        'last_name': details.get('last_name', ''),
    }

    # Handle missing last_name (required by NetBox)
    if not out['last_name']:
        full_name = details.get('fullname') or details.get('first_name', '')
        name_parts = full_name.split(' ', 1) if full_name else []

        if len(name_parts) == 2:
            out['first_name'] = name_parts[0]
            out['last_name'] = name_parts[1]
        else:
            out['last_name'] = out.get('first_name', 'User')

    return {'details': out}
```

**Pipeline runs BEFORE** `create_user` to ensure proper field values.

## Secrets Management

| Secret | 1Password Item | Purpose |
|--------|---------------|---------|
| SECRET_KEY | netbox-secret-key | Django secret key |
| DB_PASSWORD | cnpg-shared-netbox | PostgreSQL password |
| SUPERUSER_PASSWORD | netbox-superuser | Admin user password |
| SUPERUSER_API_TOKEN | netbox-superuser | API token for automation |
| OIDC_CLIENT_SECRET | netbox-oidc | OIDC client secret |

## Network Configuration

| Type | Value |
|------|-------|
| Gateway | svc-gateway (10.0.10.240) |
| Hostname | netbox.svc.damman.tech |
| Protocol | HTTPS (TLS via cert-manager) |
| Certificate | Let's Encrypt wildcard (*.svc.damman.tech) |

DNS managed automatically by external-dns: A record `netbox.svc.damman.tech` → 10.0.10.240.

## Environment Variables

```bash
ALLOWED_HOSTS=*
DB_HOST=cnpg-shared-rw.cnpg-system.svc.cluster.local
DB_NAME=netbox
DB_USER=netbox
REDIS_HOST=netbox-redis
REDIS_PORT=6379
TIME_ZONE=Europe/Amsterdam
SUPERUSER_NAME=admin
SUPERUSER_EMAIL=admin@damman.tech
```

## Health Checks

```yaml
livenessProbe:
  initialDelaySeconds: 180  # allow for migrations
  failureThreshold: 6

readinessProbe:
  initialDelaySeconds: 120
  failureThreshold: 6
```

## Use Cases

- **VLAN documentation**: VLANs 10, 13, 30, 99
- **Device inventory**: Proxmox hosts, K8s nodes, UniFi devices, IoT devices
- **Network documentation**: Cable connections, switch ports, VLAN trunking

### Integration Points

| System | Method | Purpose |
|--------|--------|---------|
| External-DNS | NetBox API → DNS | Auto DNS record sync from IPAM |
| Prometheus | Scrape `/metrics` | Enrich metrics with device metadata |
| Ansible | NetBox inventory plugin | Dynamic inventory |
| Terraform | NetBox provider | IaC source of truth |

## Troubleshooting

### Issue 1: Segmentation Fault (Signal 11)

**Cause:** Missing `SOCIAL_AUTH_OIDC_SECRET`

```yaml
env:
- name: SOCIAL_AUTH_OIDC_SECRET
  valueFrom:
    secretKeyRef:
      name: netbox-secrets
      key: OIDC_CLIENT_SECRET
```

### Issue 2: IntegrityError - null last_name

**Error:** `null value in column "last_name" violates not-null constraint`
**Fix:** Custom pipeline function (see SSO section above)

### Issue 3: Probe Timeouts

**Fix:** Increase delays to 180s/120s with `failureThreshold: 6`

### Database Checks

```bash
# Check database exists
kubectl -n cnpg-system exec -it cnpg-shared-1 -- psql -U postgres -l | grep netbox

# Check migration logs
kubectl -n netbox logs <netbox-pod> -c migration

# Manually run migrations
kubectl -n netbox exec -it <netbox-pod> -- python manage.py migrate --fake-initial
```

## Changelog

### 2026-02-09
- ✅ Deployed to production
- Integrated OIDC authentication via Authentik
- Fixed SIGSEGV crash (missing client secret)
- Fixed IntegrityError (custom pipeline for missing last_name)
- Increased probe delays for migration time
