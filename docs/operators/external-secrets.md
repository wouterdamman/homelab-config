# External Secrets Configuration

**Source:** `resources/gitops-config/sync-app/templates/external-secrets.yaml` (inline values)

---

## Overview

External Secrets Operator (ESO) synchronizes secrets from 1Password to Kubernetes Secrets. It uses a ClusterSecretStore to provide cluster-wide secret access.

---

## Architecture

```
1Password Cloud (KubernetesSecrets vault)
         │
         ▼
1Password Connect (onepassword namespace, :8080)
         │
         ▼
External Secrets Operator
         │
         ▼
Kubernetes Secrets (per namespace)
```

---

## Configuration

```yaml
installCRDs: false  # CRDs managed separately

serviceMonitor:
  enabled: true
  additionalLabels:
    release: prometheus
```

### ClusterSecretStore

```yaml
# operators/external-secrets/templates/cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: onepassword-connect
spec:
  provider:
    onepassword:
      connectHost: http://onepassword-connect.onepassword:8080
      vaults:
        KubernetesSecrets: 1
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-connect-token
            namespace: external-secrets
            key: token
```

---

## Resource Limits

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| Controller | 50m | 200m | 64Mi | 256Mi |
| Webhook | 20m | 200m | 32Mi | 128Mi |
| Cert Controller | 20m | 200m | 32Mi | 128Mi |

---

## Monitoring

**Key metrics:**
- `externalsecret_status_condition` — ExternalSecret sync status
- `externalsecret_sync_calls_total` — Total sync attempts
- `externalsecret_sync_calls_error` — Failed sync attempts

---

## Usage Example

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: my-secret
  data:
    - secretKey: password
      remoteRef:
        key: my-1password-item
        property: password
```

---

## Scheduling

Runs on worker nodes (no control-plane tolerations).

---

## Troubleshooting

```bash
# Check ExternalSecret sync status
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <namespace>

# Check ClusterSecretStore
kubectl get clustersecretstore
kubectl describe clustersecretstore onepassword-connect

# Force-sync all ExternalSecrets
kubectl get externalsecret -A -o json | \
  jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
  while read ns name; do
    kubectl annotate externalsecret -n $ns $name \
      force-sync="$(date +%s)" --overwrite
  done
```
