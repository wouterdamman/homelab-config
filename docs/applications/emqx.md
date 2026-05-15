# EMQX — MQTT Broker

Enterprise-grade MQTT broker for home automation communication.

## Overview

**Status:** ✅ Deployed & Production (2026-01-28)
**Purpose:** MQTT message broker for Home Assistant, Zigbee2MQTT, EVCC, and other IoT devices.
**Namespace:** `emqx`
**Dashboard:** https://emqx.svc.damman.tech

**Migration completed 2026-01-28:** External LoadBalancer removed, all MQTT communication is now internal to the cluster.

---

## Architecture

```
┌──────────────────────────────────┐
│         EMQX Cluster           │
│  (3 replicas, StatefulSet)     │
│                                │
│  Internal: emqx.emqx:1883      │
│  (ClusterIP only)              │
└────────┬─────────────────────────┘
         │
         ├──────────────────────────┐
         │                          │
         ↓                          ↓
┌───────────────┐        ┌──────────────────┐
│  Zigbee2MQTT   │       │ Home Assistant   │
│  (Kubernetes)  │       │ (Kubernetes)     │
└───────────────┘        └──────────────────┘
```

---

## Deployment Configuration

| Setting | Value |
|---------|-------|
| Type | StatefulSet |
| Replicas | 3 |
| Image | `emqx/emqx:5.8.9` |
| CPU | 100m request, 500m limit |
| Memory | 256Mi request, 512Mi limit |
| Storage | 10Gi per pod (longhorn-standard) |

---

## Services

**Internal (ClusterIP):**

| Port | Protocol |
|------|----------|
| 1883 | MQTT |
| 8883 | MQTT/TLS |
| 8083 | WebSocket |
| 8084 | WebSocket/TLS |
| 18083 | Dashboard |

All external clients connect via `emqx.emqx.svc.cluster.local`.

---

## Cluster Configuration

```yaml
EMQX_CLUSTER__DISCOVERY_STRATEGY: dns
EMQX_CLUSTER__DNS__NAME: emqx-headless.emqx.svc.cluster.local
EMQX_CLUSTER__DNS__RECORD_TYPE: srv
```

---

## Dashboard Access

**URL:** https://emqx.svc.damman.tech
**Username:** `admin`
**Password:** 1Password → `emqx-dashboard-password`

> **Note:** `EMQX_DASHBOARD__DEFAULT_PASSWORD` only applies at first install. For existing deployments, reset manually:
> ```bash
> kubectl exec -n emqx emqx-0 -- emqx ctl admins passwd admin <new-password>
> ```

---

## Secrets Management

**ExternalSecret:** `emqx-dashboard-secret`
**1Password Item:** `emqx-dashboard-password` (KubernetesSecrets vault)

> The `property` field is required when a 1Password item has multiple fields:
> ```yaml
> data:
>   - remoteKey: emqx-dashboard-password
>     property: password
>     secretKey: EMQX_DASHBOARD__DEFAULT_PASSWORD
> ```

---

## Monitoring

**Metrics endpoint:** `http://emqx:18083/api/v5/prometheus/stats`

| Metric | Description |
|--------|-------------|
| `emqx_connections_count` | Active MQTT connections |
| `emqx_messages_received` | Messages received |
| `emqx_messages_sent` | Messages sent |
| `emqx_messages_dropped` | Dropped messages |
| `emqx_bytes_received` | Network traffic in |
| `emqx_bytes_sent` | Network traffic out |

---

## Operations

```bash
# Cluster status
kubectl exec -n emqx emqx-0 -- emqx ctl cluster status

# List connections
kubectl exec -n emqx emqx-0 -- emqx ctl clients list

# View logs
kubectl logs -n emqx -l app.kubernetes.io/name=emqx --tail=100

# Reset admin password
kubectl exec -n emqx emqx-0 -- emqx ctl admins passwd admin <new-password>
```

---

## Migration History

| Phase | Status | Date |
|-------|--------|------|
| EMQX deployed (3 replicas + LoadBalancer) | ✅ | 2026-01-17 |
| Zigbee2MQTT connected to internal EMQX | ✅ | 2026-01-17 |
| Old HA connected to EMQX LoadBalancer | ✅ | 2026-01-18 |
| New HA deployed in Kubernetes | ✅ | 2026-01-18 |
| Old HA decommissioned | ✅ | 2026-01-28 |
| External LoadBalancer removed | ✅ | 2026-01-28 |

**Benefits of removing external LoadBalancer:**
- Reduced attack surface (no external MQTT access)
- Freed up LoadBalancer IP (10.0.10.242)
- All communication internal to cluster

---

## Lessons Learned

### ExternalSecret Property Field

1Password items with multiple fields need `property` specified — otherwise ESO can't identify which field to use.

### Default Password Only at First Install

`EMQX_DASHBOARD__DEFAULT_PASSWORD` env var is ignored after the first install. Always reset via CLI after deployment:
```bash
kubectl exec -n emqx emqx-0 -- emqx ctl admins passwd admin <password>
```

### External Traffic Policy

`externalTrafficPolicy: Local` caused connectivity issues with the LoadBalancer. Changed to `Cluster` for better external access (now moot since LoadBalancer removed).
