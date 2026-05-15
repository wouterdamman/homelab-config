# 1Password Connect Configuration

**Source:** `resources/gitops-config/sync-app/templates/onepassword-connect.yaml` (inline values)

---

## Overview

1Password Connect provides a local API server that External Secrets Operator uses to fetch secrets from 1Password vaults. It consists of two containers: API server and sync service.

---

## Architecture

```
1Password Cloud
         │
         ▼
1Password Connect (onepassword namespace)
  ┌──────────────────┐
  │  Sync Container  │  (fetch + cache from 1Password Cloud)
  ├──────────────────┤
  │  API Container   │  (REST API :8080)
  └──────────────────┘
         │
         ▼
External Secrets Operator
```

---

## Configuration

```yaml
connect:
  credentialsName: onepassword-connect-credentials
  credentialsKey: onepassword-connect-credentials.json
```

### Credentials Secret

The Connect credentials file is manually created during bootstrap (cannot use ESO — bootstrap chicken-and-egg):

```bash
kubectl create secret generic onepassword-connect-credentials \
  --from-file=onepassword-connect-credentials.json \
  -n onepassword
```

> **Use `--from-file`** — this handles base64 encoding automatically.
> **Never** use `kubectl apply -f` with a manually base64-encoded YAML — this causes double-encoding.

---

## Resource Limits

| Container | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| API | 20m | 200m | 32Mi | 128Mi |
| Sync | 20m | 200m | 32Mi | 128Mi |

---

## Service Endpoint

```yaml
# Internal service URL (used by ClusterSecretStore)
http://onepassword-connect.onepassword:8080
```

---

## Sync Wave

Deployed in **Wave 1** — before External Secrets (Wave 2) to ensure Connect is available before ESO starts syncing.

```yaml
argocd.argoproj.io/sync-wave: "1"
```

---

## Monitoring

1Password Connect doesn't expose native Prometheus metrics. Monitor via:
- Kubernetes pod status: `kubectl get pods -n onepassword`
- ExternalSecret sync status (downstream indicator)
- Connect logs: `kubectl logs -n onepassword -l app=onepassword-connect`

---

## Troubleshooting

See [Troubleshooting Guide](../operations/troubleshooting.md) — Section 4: Secrets Issues.

### Double Base64-Encoded Credentials

**Symptoms:** `InvalidProviderConfig`, JSON parse errors in logs

**Fix:**
```bash
# Get correct credentials from 1Password
op item get "<item-id>" --reveal --fields label=password | base64 -d > /tmp/credentials.json

# Recreate secret correctly
kubectl delete secret -n onepassword onepassword-connect-credentials
kubectl create secret generic onepassword-connect-credentials \
  -n onepassword \
  --from-file=1password-credentials.json=/tmp/credentials.json
rm /tmp/credentials.json
```
