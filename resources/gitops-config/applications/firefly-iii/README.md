# Firefly III - Personal Finance Manager

Self-hosted personal finance management with budgeting, transaction tracking, and reporting features.

## Overview

- **Version:** 6.1.21
- **URL:** https://budget.app.damman.tech
- **Namespace:** `firefly-iii`
- **Authentication:** Email/password (SSO planned for future)
- **Database:** PostgreSQL 16.4 on CloudNative-PG shared cluster

## Architecture

### Components

- **Application:** Firefly III web interface (Laravel/PHP)
- **Database:** PostgreSQL database on `cnpg-shared` cluster
- **Storage:** Persistent volume for uploads (10Gi Longhorn)
- **Ingress:** Cilium Gateway API (HTTPRoute)

### Database Configuration

Database and user are automatically provisioned via GitOps:
- **Job:** `cnpg-init-firefly` (PostSync hook)
- **Database:** `firefly` on cnpg-shared cluster
- **User:** `firefly` with full permissions
- **Credentials:** Managed via External Secrets (1Password)

### Secrets

Managed via External Secrets Operator from 1Password vault `KubernetesSecrets`:

1. **Database credentials:** `cnpg-shared-firefly`
   - `username`: firefly
   - `password`: auto-generated
   - `host`: cnpg-shared-rw.cnpg-system.svc.cluster.local
   - `port`: 5432
   - `database`: firefly

2. **Application key:** `firefly-app-key`
   - Laravel encryption key (base64-encoded)

## Deployment

Deployed via ArgoCD with GitOps:

```yaml
Application: firefly-iii
Sync Wave: 5 (tier-4)
Auto-sync: Enabled
Prune: Enabled
Self-heal: Enabled
```

### Initial Setup

1. Database is automatically created by init job
2. Application pod starts and runs migrations
3. Access https://budget.app.damman.tech
4. Register first user account (becomes admin)

## Authentication

Currently using built-in email/password authentication.

### Future: SSO via Authentik

Forward authentication with Authentik is planned but requires:
- Mature Cilium Gateway API external authorization support
- CiliumEnvoyConfig for ext_authz integration
- Authentik Proxy Provider configuration

**Status:** Waiting for upstream maturity (GitHub Issue #13545)

## Maintenance

### Database Backups

Automatic backups via CloudNative-PG to Hetzner Object Storage:
- WAL archiving with gzip compression
- Regular base backups
- Point-in-time recovery support

### Application Updates

Update image tag in `values.yaml`:
```yaml
image:
  tag: "version-X.Y.Z"
```

### Database Access

Connect via primary service:
```bash
kubectl exec -it -n cnpg-system cnpg-shared-1 -c postgres -- psql -U firefly -d firefly
```

## Monitoring

- **Logs:** `kubectl logs -n firefly-iii -l app.kubernetes.io/name=firefly-iii`
- **Pod status:** `kubectl get pods -n firefly-iii`
- **Database:** CloudNative-PG PodMonitor for Prometheus metrics

## Troubleshooting

### Pod not starting

Check init job completion:
```bash
kubectl get jobs -n cnpg-system cnpg-init-firefly
kubectl logs -n cnpg-system -l job-name=cnpg-init-firefly
```

### Database connection issues

Verify database exists and user has permissions:
```bash
kubectl exec -n cnpg-system cnpg-shared-1 -c postgres -- psql -U postgres -c "\l" | grep firefly
kubectl exec -n cnpg-system cnpg-shared-1 -c postgres -- psql -U postgres -c "\du" | grep firefly
```

### Application errors

Check application logs:
```bash
kubectl logs -n firefly-iii deployment/firefly --tail=100
```

## Related Documentation

- **ADR-023:** [Firefly III - Personal Finance Manager](https://www.notion.so/2d7b49ed6b9181f1bb08ead80ea7125a)
- **ADR-024:** [CloudNative-PG Configuration](https://www.notion.so/2e3b49ed6b918111aac6c072a1b60e7f)
- [Firefly III Official Docs](https://docs.firefly-iii.org/)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/)

## Development

### Local Testing

Values can be overridden in `values.yaml`:
```yaml
replicas: 1
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Database Schema Changes

Firefly III handles migrations automatically on startup via Laravel's migration system.
