# External-DNS Configuration

**Source:** `resources/gitops-config/operators/external-dns/values.yaml`

---

## Overview

external-dns automatically manages DNS records in UniFi based on Kubernetes resources (Services, Ingresses, Gateway HTTPRoutes, and DNSEndpoint CRDs).

---

## Configuration

```yaml
fullnameOverride: "external-dns-unifi"

interval: 1m
policy: sync
registry: noop

domainFilters:
  - local.damman.tech
  - svc.damman.tech
  - app.damman.tech

sources:
  - crd
  - service
  - ingress
  - gateway-httproute
  - gateway-tlsroute
```

### UniFi Webhook Provider

```yaml
provider:
  name: webhook
  webhook:
    image:
      repository: 'ghcr.io/kashalls/external-dns-unifi-webhook'
      tag: v0.8.2
    env:
      - name: UNIFI_HOST
        value: https://10.0.10.193
      - name: UNIFI_API_KEY
        valueFrom:
          secretKeyRef:
            name: external-dns-unifi-secret
            key: api-key
```

---

## Resource Limits

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| Controller | 10m | 250m | 64Mi | 128Mi |
| Webhook Sidecar | 10m | 100m | 64Mi | 128Mi |

---

## Secret Management

The UniFi API key is stored in 1Password and synced via External Secrets Operator:

```
1Password vault: KubernetesSecrets
Item: external-dns-unifi
Field: api-key
→ Kubernetes Secret: external-dns-unifi-secret
```

---

## Monitoring

```yaml
serviceMonitor:
  enabled: true
  additionalLabels:
    release: prometheus
```

**Key metrics:**
- `external_dns_source_endpoints` — Endpoints from sources
- `external_dns_registry_endpoints` — Endpoints in registry
- `external_dns_controller_last_sync_timestamp_seconds` — Last sync time

---

## Scheduling

Runs on worker nodes (no control-plane tolerations).

---

## Troubleshooting

```bash
# Check controller logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns -f

# Check webhook sidecar
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns -c webhook

# Test DNS resolution
kubectl run -it --rm dns-test --image=busybox -- nslookup myapp.app.damman.tech
```

Verify records in UniFi Console → Settings → Networks → DNS Records.
