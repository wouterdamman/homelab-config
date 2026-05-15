# Cilium Configuration

**Source:** `resources/gitops-config/operators/cilium/values.yaml`

---

## Overview

Cilium is the Container Network Interface (CNI) for the cluster, providing eBPF-based networking, Gateway API ingress, and Hubble network observability.

---

## Key Features

| Feature | Status | Description |
|---------|--------|-------------|
| eBPF Datapath | Enabled | Kernel-native networking, high performance |
| Kube-proxy Replacement | Enabled | Cilium handles all service routing |
| Gateway API | Enabled | Modern ingress via HTTPRoute resources |
| L2 Announcements | Enabled | ARP announcements for LoadBalancer IPs |
| Hubble | Enabled | Network observability (flows, DNS, HTTP) |
| Maglev Load Balancing | Enabled | Consistent hashing for better distribution |

---

## Network Configuration

| Setting | Value |
|---------|-------|
| Cluster Name | talos |
| Cluster ID | 1 |
| IPAM Mode | kubernetes |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |

### Talos-Specific Settings

```yaml
k8sServiceHost: localhost
k8sServicePort: 7445
cgroup:
  autoMount:
    enabled: false
  hostRoot: /sys/fs/cgroup
```

---

## Resource Configuration

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| Cilium Agent | 100m | 1000m | 256Mi | 512Mi |
| Operator | 10m | 100m | 64Mi | 128Mi |
| Envoy | 5m | 100m | 32Mi | 64Mi |
| Hubble Relay | 5m | 100m | 32Mi | 128Mi |
| Hubble UI Backend | 5m | 100m | 32Mi | 64Mi |
| Hubble UI Frontend | 2m | 50m | 16Mi | 32Mi |

---

## Gateway API

```yaml
gatewayAPI:
  enabled: true
  enableAlpn: true
  enableAppProtocol: true
```

**Traffic flow:**
```
Client → UniFi DNS → Cilium LB IP → Envoy → HTTPRoute → Service → Pod
```

### Gateways

**svc-gateway** (10.0.10.240) — Services domain:
- HTTP Listener (port 80): `*.svc.damman.tech`
- HTTPS Listener (port 443): `*.svc.damman.tech` — TLS Terminate
- TLS Passthrough Listener (port 8006): `pve.svc.damman.tech` — TLS Passthrough

**app-gateway** (10.0.10.241) — Applications domain:
- HTTP Listener (port 80): `*.app.damman.tech`
- HTTPS Listener (port 443): `*.app.damman.tech` — TLS Terminate

### Route Types

**HTTPRoute** (most services): TLS terminated at Gateway with Let's Encrypt

**TLSRoute** (TLS passthrough): SNI-based routing, backend handles its own TLS. Example: Proxmox VE (`pve.svc.damman.tech:8006`)

---

## Hubble Observability

```bash
# Access Hubble UI (not externally exposed)
kubectl port-forward -n kube-system svc/hubble-ui 8080:80
# Open: http://localhost:8080
```

**Enabled metrics:** dns, drop, tcp, flow, icmp, http

---

## Prometheus Integration

ServiceMonitors enabled for all Cilium components (label: `release: prometheus`).

| Component | Port |
|-----------|------|
| Cilium Agent | 9962 |
| Operator | 9963 |
| Hubble | 9965 |

**Key metrics:**
- `cilium_endpoint_count` — Endpoints managed
- `cilium_policy_*` — Network policy statistics
- `hubble_flows_processed_total` — Flow processing rate
- `cilium_drop_count_total` — Dropped packets by reason

---

## ArgoCD Sync Configuration

Hubble certificates are regenerated on every sync. To prevent out-of-sync:

```yaml
# In sync-app/templates/cilium.yaml
ignoredifferences:
  - group: ""
    kind: Secret
    name: hubble-relay-client-certs
    jsonPointers:
      - /data/ca.crt
      - /data/tls.crt
      - /data/tls.key
```

This is already configured in `sync-app/templates/cilium.yaml`.

---

## Troubleshooting

```bash
# Check Cilium status
kubectl -n kube-system exec ds/cilium -- cilium status

# View network flows
kubectl -n kube-system exec ds/cilium -- hubble observe

# Check connectivity
kubectl -n kube-system exec ds/cilium -- cilium connectivity test

# View dropped packets
kubectl -n kube-system exec ds/cilium -- hubble observe --verdict DROPPED
```
