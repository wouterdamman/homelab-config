# Kubelet CSR Approver Configuration

**Source:** `resources/gitops-config/operators/kubelet-csr-approver/values.yaml`
**Chart:** postfinance/kubelet-csr-approver

---

## Overview

Kubelet CSR Approver automatically approves kubelet-serving Certificate Signing Requests (CSRs). Required because Talos uses `rotate-server-certificates: true` and kubelet serving certificates must be approved.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Kubelet CSR Approver                        │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Controller (2 replicas)                     ││
│  │                                                          ││
│  │  • Watches for CertificateSigningRequests               ││
│  │  • Validates CSR against providerRegex                  ││
│  │  • Validates source IP against providerIpPrefixes       ││
│  │  • Auto-approves valid kubelet-serving CSRs             ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Leader Election                             ││
│  │  Only one replica actively processes CSRs               ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

---

## Key Features

| Feature | Status | Description |
|---------|--------|-------------|
| Auto-approval | Enabled | Automatically approves valid kubelet-serving CSRs |
| HA Deployment | 2 replicas | High availability with leader election |
| IP Validation | 10.0.10.0/24 | Only approves CSRs from known node IPs |
| Hostname Validation | Regex | Validates node names match pattern |
| Prometheus Metrics | Enabled | ServiceMonitor for observability |

---

## Configuration

### Node Validation

```yaml
# Only approve CSRs from nodes matching this pattern
providerRegex: "^prd-(cp|w)-\\d+$"

# Only approve CSRs from these IP ranges
providerIpPrefixes:
  - 10.0.10.0/24
```

Only CSRs from known nodes (`prd-cp-01`, `prd-w-01`, etc.) are approved.

---

## Resource Limits

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 5m | 100m |
| Memory | 32Mi | 64Mi |

---

## Prometheus Integration

ServiceMonitor enabled with `release: prometheus` label.

**Key metrics:**
- `kubelet_csr_approver_approved_total` — Total approved CSRs
- `kubelet_csr_approver_denied_total` — Total denied CSRs
- `kubelet_csr_approver_ignored_total` — Total ignored CSRs

---

## Why This Component

Talos Linux configures kubelets with `rotate-server-certificates: true`, meaning:
1. Kubelet generates a CSR for its serving certificate
2. CSR must be approved by a controller
3. Without an approver, kubelets wait indefinitely for certificates

The approver automates this safely by validating IPs and hostnames against known patterns.

> **Migration note:** Replaced `alex1989hu/kubelet-serving-cert-approver` with `postfinance/kubelet-csr-approver` for Helm chart support, configurable resource limits, built-in ServiceMonitor, and active maintenance.

---

## Troubleshooting

```bash
# Check pending CSRs
kubectl get csr

# View approver logs
kubectl logs -n kubelet-serving-cert-approver -l app.kubernetes.io/name=kubelet-csr-approver

# Manually approve CSR (emergency)
kubectl certificate approve <csr-name>
```
