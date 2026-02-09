# NetBox & Homarr Implementation Documentation

> **Note:** This document provides implementation details for updating the Notion documentation.
> Last updated: 2026-02-09

## Overview

Successfully implemented two new applications in the homelab:
- **NetBox** - IPAM/DCIM for network infrastructure management
- **Homarr** - Dashboard for homelab service management

Both applications are configured with:
- PostgreSQL via CNPG (CloudNativePG) shared cluster
- OIDC authentication via Authentik
- Persistent storage via Longhorn
- HTTPS access via Gateway API

---

## NetBox Implementation

### Service Details
- **URL:** https://netbox.svc.damman.tech
- **Version:** v4.2.0
- **Namespace:** `netbox`
- **Gateway:** svc-gateway (svc-https-listener)

### Architecture

#### Database
- **Type:** PostgreSQL via CNPG shared cluster
- **Database:** `netbox`
- **User:** `netbox`
- **Connection:** cnpg-shared-rw.cnpg-system.svc.cluster.local:5432

#### Authentication
- **Method:** OIDC via Authentik
- **Provider:** `social_core.backends.open_id_connect.OpenIdConnectAuth`
- **Client ID:** `xS0lvZfCpBNuTlbYF4a16Xvo0kEa5W4QmYzkVMOi`
- **Issuer URL:** https://sso.svc.damman.tech/application/o/netbox/
- **Scopes:** `openid profile email`

#### Storage
- **Media Storage:** 10Gi PVC (longhorn-standard)
- **Path:** `/opt/netbox/netbox/media`

#### Resources
- **Requests:** 200m CPU, 512Mi memory
- **Limits:** 1000m CPU, 2Gi memory
- **Worker:** 100m CPU, 256Mi memory (requests), 500m CPU, 512Mi memory (limits)

### Key Configuration

#### OIDC Custom Pipeline
NetBox requires custom user details handling due to Authentik not always providing `family_name` claim:

```python
# Custom pipeline function to handle missing user fields
def get_user_details(strategy, details, backend, user=None, *args, **kwargs):
    """Extract user details from OIDC response with fallbacks for required fields"""
    out = {
        'username': details.get('username'),
        'email': details.get('email', ''),
        'first_name': details.get('first_name', ''),
        'last_name': details.get('last_name', ''),
    }

    # Handle missing last_name (required by NetBox)
    if not out['last_name']:
        # Split full name if available
        full_name = details.get('fullname') or details.get('first_name', '')
        name_parts = full_name.split(' ', 1) if full_name else []

        if len(name_parts) == 2:
            out['first_name'] = name_parts[0]
            out['last_name'] = name_parts[1]
        elif len(name_parts) == 1:
            out['first_name'] = name_parts[0]
            out['last_name'] = name_parts[0]
        else:
            out['first_name'] = out.get('username', 'User')
            out['last_name'] = out.get('username', 'User')

    return {'details': out}
```

The pipeline runs **before** `create_user` to ensure proper field values.

#### Probe Configuration
Due to database migrations at startup:
- **Liveness Probe:** 180s initial delay, 30s period, 6 failures
- **Readiness Probe:** 120s initial delay, 15s period, 6 failures

### Secrets Management

#### 1Password Entries
1. **`cnpg-shared-netbox`** (KubernetesSecrets vault)
   - host, port, database, username, password

2. **`netbox-secret-key`** (KubernetesSecrets vault)
   - key: Django SECRET_KEY

3. **`netbox-superuser`** (KubernetesSecrets vault)
   - password: Admin password
   - api_token: API access token

4. **`netbox-oidc`** (KubernetesSecrets vault)
   - client_secret: Authentik OAuth client secret

### Troubleshooting Issues & Solutions

#### Issue 1: Segmentation Fault (Signal 11)
**Problem:** NetBox crashed during OAuth callback with SIGSEGV
**Cause:** Missing `SOCIAL_AUTH_OIDC_SECRET` in configuration
**Solution:** Added client secret environment variable and ConfigMap reference

#### Issue 2: IntegrityError - null last_name
**Problem:** Database constraint violation when creating users
**Cause:** Authentik not providing `family_name` claim
**Solution:** Custom pipeline function to handle missing fields with fallbacks

#### Issue 3: Probe Timeouts
**Problem:** Pods killed during database migrations
**Cause:** Default probe delays too short (30s/20s)
**Solution:** Increased delays to 180s/120s with higher failure thresholds

---

## Homarr Implementation

### Service Details
- **URL:** https://homarr.app.damman.tech
- **Version:** latest
- **Namespace:** `homarr`
- **Gateway:** app-gateway (app-https-listener)

### Architecture

#### Database
- **Type:** PostgreSQL via CNPG shared cluster
- **Database:** `homarr`
- **User:** `homarr`
- **Connection:** cnpg-shared-rw.cnpg-system.svc.cluster.local:5432

#### Authentication
- **Method:** OIDC via Authentik
- **Provider:** `oidc`
- **Client ID:** `xsQOrUUzKH2dO7AEcMXJmTrZ2IfUrrk68fLvCCzT`
- **Issuer URL:** https://sso.app.damman.tech/application/o/homarr/ ⚠️ *Note trailing slash*
- **Scopes:** `openid email profile groups`
- **Groups Attribute:** `groups`

#### Storage
- **Data Storage:** 5Gi PVC (longhorn-standard) - `/app/data/configs`
- **Icons Storage:** 1Gi PVC (longhorn-standard) - `/app/public/icons`

#### Resources
- **Requests:** 200m CPU, 512Mi memory
- **Limits:** 1000m CPU, 1Gi memory

#### Internal Services
- **Web Server:** Port 3000 (Next.js)
- **WebSocket Server:** Port 3001
- **Internal Redis:** Port 6379 (embedded)

### Key Configuration

#### Environment Variables
```yaml
DATABASE_URL: postgresql://homarr:PASSWORD@host:5432/homarr
BASE_URL: https://homarr.app.damman.tech
TZ: Europe/Amsterdam
SECRET_ENCRYPTION_KEY: <64-char hex string>
AUTH_PROVIDERS: oidc
AUTH_OIDC_CLIENT_ID: <client-id>
AUTH_OIDC_CLIENT_SECRET: <client-secret>
AUTH_OIDC_ISSUER: https://sso.app.damman.tech/application/o/homarr/
AUTH_OIDC_CLIENT_NAME: Authentik
AUTH_OIDC_SCOPE_OVERWRITE: openid email profile groups
AUTH_OIDC_GROUPS_ATTRIBUTE: groups
```

#### Probe Configuration
- **Liveness Probe:** 120s initial delay, 30s period, 6 failures
- **Readiness Probe:** 90s initial delay, 15s period, 6 failures

### Secrets Management

#### 1Password Entries
1. **`cnpg-shared-homarr`** (KubernetesSecrets vault)
   - host, port, database, username, password

2. **`homarr-oidc`** (KubernetesSecrets vault)
   - client_secret: Authentik OAuth client secret
   - encryption_key: 64-character hex key for data encryption

### Troubleshooting Issues & Solutions

#### Issue 1: Missing SECRET_ENCRYPTION_KEY
**Problem:** App crashed with "Invalid environment variables"
**Cause:** Required encryption key not configured
**Solution:** Generated 64-char hex key and added to environment

#### Issue 2: Wrong Port Configuration
**Problem:** Probes failing with EOF errors
**Cause:** Service configured for port 7575, app runs on port 3000
**Solution:** Updated all port references to 3000

#### Issue 3: OIDC Issuer Mismatch
**Problem:** OAuth authentication failed with issuer mismatch
**Cause:** Authentik returns issuer URL **with trailing slash** `/`
**Solution:** Added trailing slash to issuer URL configuration

#### Issue 4: OOMKilled (Exit Code 137)
**Problem:** Container repeatedly crashed after ~28 seconds
**Cause:** Memory limit 512Mi too low for Homarr
**Solution:** Increased memory limit to 1Gi

#### Issue 5: Probe Timeouts
**Problem:** Similar to NetBox, probes killed container during startup
**Cause:** Default delays too short for initialization
**Solution:** Increased delays to 90s/120s

---

## Common Patterns & Lessons Learned

### OIDC Configuration
1. **Always check trailing slashes** - Authentik includes them, match exactly
2. **Custom pipelines may be needed** - Handle missing user fields gracefully
3. **Test with actual user data** - Don't assume all OIDC claims will be present

### Resource Sizing
- **Start conservative, monitor, adjust** - Both apps needed more memory than initially allocated
- **Watch for OOMKills** - Exit code 137 indicates memory issues
- **PostgreSQL apps** - Generally need 1Gi+ memory for production use

### Probe Configuration
- **Database migrations need time** - 120s+ initial delays recommended
- **Higher failure thresholds** - 6 failures prevents premature restarts
- **Monitor startup time** - Adjust delays based on actual startup duration

### CNPG Integration
- **Shared cluster works well** - Multiple apps on one PostgreSQL cluster
- **Init jobs for setup** - Use Kubernetes Jobs for database initialization
- **Connection strings in secrets** - Use DATABASE_URL format where possible

### Gateway API
- **Separate gateways for services** - `svc-gateway` vs `app-gateway`
- **Section names matter** - Match listener configurations
- **HTTPRoute per service** - Clean separation of routing rules

---

## File Locations

### NetBox
- **Application:** `resources/gitops-config/applications/netbox/`
- **ArgoCD App:** `resources/gitops-config/sync-app/templates/netbox.yaml`
- **CNPG Init:** `resources/gitops-config/operators/cloudnative-pg/templates/cnpg-init-netbox.yaml`

### Homarr
- **Application:** `resources/gitops-config/applications/homarr/`
- **ArgoCD App:** `resources/gitops-config/sync-app/templates/homarr.yaml`
- **CNPG Init:** `resources/gitops-config/operators/cloudnative-pg/templates/cnpg-init-homarr.yaml`

---

## Next Steps / Future Improvements

### NetBox
- [ ] Configure device types and manufacturers
- [ ] Set up IP address management (IPAM) hierarchy
- [ ] Define rack layouts and cable management
- [ ] Configure API automation for inventory management
- [ ] Set up NAPALM for network device automation

### Homarr
- [ ] Create admin group in Authentik (`homarr-admins`)
- [ ] Configure service integrations
- [ ] Set up custom dashboard layouts
- [ ] Configure widgets for monitoring
- [ ] Document common dashboards and layouts

### Both Applications
- [ ] Monitor resource usage over time
- [ ] Set up backup schedules (databases are in CNPG backup)
- [ ] Configure alert rules (if needed)
- [ ] Document operational runbooks
- [ ] Review and optimize resource allocations

---

## References

### Documentation
- [NetBox Documentation](https://docs.netbox.dev/)
- [Homarr Documentation](https://homarr.dev/docs)
- [Authentik Integrations - NetBox](https://goauthentik.io/integrations/services/netbox/)
- [Authentik Integrations - Homarr](https://integrations.goauthentik.io/dashboards/homarr/)

### Git Commits
- NetBox OIDC fixes: commits 23c5ce3, f218462, 7351988
- Homarr implementation: commits 1c90ffc, d7a431e, 7de42c6
- Resource and configuration fixes: commits 52bd4c9, 74d2c15, 0a7e9d6
