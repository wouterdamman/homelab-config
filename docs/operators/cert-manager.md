# Cert-Manager Configuration

**Source:** `resources/gitops-config/operators/cert-manager/values.yaml`

---

## Overview

cert-manager handles automatic TLS certificate management for the cluster, integrating with Let's Encrypt via Cloudflare DNS-01 challenge.

---

## Configuration

```yaml
crds:
  enabled: true
  keep: true

extraArgs:
  - --enable-gateway-api
  - --dns01-recursive-nameservers-only
  - --dns01-recursive-nameservers=1.1.1.1:53
```

### Components

| Component | Purpose |
|-----------|---------|
| Controller | Main certificate management |
| Webhook | Validation and mutation webhook |
| CA Injector | Inject CA bundles into resources |
| Startup API Check | Verify API availability on startup |

---

## Resource Limits

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| Controller | 5m | 100m | 32Mi | 128Mi |
| Webhook | 5m | 100m | 16Mi | 64Mi |
| CA Injector | 5m | 100m | 32Mi | 128Mi |
| Startup API Check | 10m | 100m | 32Mi | 64Mi |

---

## ClusterIssuer — Let's Encrypt + Cloudflare DNS-01

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cert-manager-cloudflare
              key: cloudFlare
        selector:
          dnsZones:
            - "damman.tech"
```

---

## DNS Configuration

```yaml
podDnsConfig:
  nameservers:
    - "1.1.1.1"
    - "8.8.8.8"
```

Custom DNS servers ensure reliable DNS-01 challenge resolution.

---

## Monitoring

```yaml
prometheus:
  enabled: true
  servicemonitor:
    enabled: true
    labels:
      release: prometheus
```

**Key metrics:**
- `certmanager_certificate_expiration_timestamp_seconds` — Certificate expiry
- `certmanager_certificate_ready_status` — Certificate ready status
- `certmanager_http_acme_client_request_duration_seconds` — ACME latency

---

## Scheduling

Runs on worker nodes (no control-plane tolerations) to keep control-plane nodes clean.
