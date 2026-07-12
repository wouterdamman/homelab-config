# EVCC — Solar Charging Platform

Electric vehicle charging with solar surplus optimization.

## Overview

**Status:** ✅ Deployed (2026-01-22)
**Purpose:** Charge electric vehicles with solar power surplus and dynamic pricing optimization.
**Namespace:** `evcc`
**External Access:** https://evcc.app.damman.tech

---

## Architecture

```
┌──────────────────────────────────┐
│         EVCC Core                │
│      (Kubernetes)                │
└─────┬──────────┬──────────┬──────┘
      │          │          │
      │ MQTT     │ Database │ Modbus TCP
      ↓          ↓          ↓
  ┌────────┐  SQLite    ┌──────────────┐
  │  EMQX  │  (2Gi PVC)  │ Devices      │
  │ Broker │            │ - Alfen      │
  └────────┘            │ - SolarEdge  │
      │                 │ - DSMR       │
      ↓                 └──────────────┘
  ┌───────────────┐
  │ Home Assistant │
  │   (MQTT)       │
  └───────────────┘
```

---

## Deployment Configuration

| Setting | Value |
|---------|-------|
| Image | `evcc/evcc:0.311.1` |
| Strategy | Recreate (for PVC attachment) |
| CPU | 100m request, 500m limit |
| Memory | 256Mi request, 512Mi limit |
| Storage | 2Gi PVC (longhorn-standard, SQLite database) |

**Internal:** `evcc.evcc.svc.cluster.local:7070`

---

## Configuration (ExternalSecret)

Configuration is sourced from a 1Password item via ExternalSecret — there is no ConfigMap.

**ExternalSecret:** `evcc-config`
**1Password Item:** `evcc-config` (KubernetesSecrets vault)

The secret key `evcc.yaml` is mounted read-only into the container at `/etc/evcc.yaml`. Application data (SQLite database) is stored separately on the PVC at `/root/.evcc`.

```yaml
# ExternalSecret data mapping
- remoteKey: evcc-config
  secretKey: evcc.yaml
```

---

## Device Configuration (Planned)

### Alfen Eve Wallbox

**Connection:** Modbus TCP — sponsor token required (€2/month)

```yaml
chargers:
  - name: alfen
    type: template
    template: alfen
    host: <WALLBOX_IP>
    port: 502
    id: 1
```

### SolarEdge Inverter

**Connection:** Modbus TCP (may need ModBus proxy — SolarEdge allows only one client)

```yaml
meters:
  - name: pv
    type: template
    template: solaredge
    host: <INVERTER_IP>
    port: 502
    modbus: tcpip
    id: 1
    usage: pv
```

### DSMR Smart Meter

**Connection:** Via Home Assistant sensor

```yaml
meters:
  - name: grid
    type: custom
    power:
      source: http
      uri: http://home-assistant.home-assistant.svc.cluster.local:8123/api/states/sensor.dsmr_meter_power
      headers:
      - Authorization: Bearer <LONG_LIVED_TOKEN>
      jq: .state | tonumber
    usage: grid
```

### Loadpoint

```yaml
loadpoints:
  - title: Garage
    charger: alfen
    mode: pv
    phases: 0   # Auto-detect 1/3 phase
    mincurrent: 6
    maxcurrent: 16
```

---

## MQTT Integration

- **Broker:** `emqx.emqx.svc.cluster.local:1883`
- **Topic:** `evcc`
- **Discovery:** Enabled for Home Assistant auto-discovery

EVCC publishes state to MQTT; Home Assistant auto-discovers entities (charging state, solar power, grid power, loadpoint mode, vehicle SOC).

---

## Secrets Management (Planned)

| 1Password Item | Purpose |
|---------------|---------|
| `evcc-sponsor-token` | Sponsor token for premium device support |
| `evcc-mqtt-credentials` | MQTT username/password |
| `evcc-ha-token` | Home Assistant long-lived access token |

---

## Backup & Restore

```bash
# Scale down
kubectl scale deployment evcc -n evcc --replicas=0

# Restore PVC from Longhorn snapshot (via UI or kubectl)

# Scale up
kubectl scale deployment evcc -n evcc --replicas=1
```

---

## Troubleshooting

### Pod CrashLoopBackOff

```bash
kubectl logs -n evcc -l app.kubernetes.io/name=evcc --previous
# Common: invalid YAML in evcc-config secret, missing required keys
```

### MQTT Connection Failed

```bash
kubectl get pods -n emqx
kubectl run -it --rm mqtt-test --image=eclipse-mosquitto --restart=Never -- \
  mosquitto_sub -h emqx.emqx.svc.cluster.local -p 1883 -t 'evcc/#'
```

### HTTPRoute Not Working

```bash
kubectl describe httproute evcc -n evcc
kubectl get gateway app-gateway -n kube-system
```

### Resolved Issues (2026-01-22)

| Issue | Cause | Fix |
|-------|-------|-----|
| ImagePullBackOff | Tag `0.133.1` doesn't exist | Changed to `0.311.1` |
| Config validation error | `buffersoc`/`prioritysoc` not camelCase | Removed site section |
| HTTPRoute Progressing | Wrong gateway namespace `cilium-gateway` | Changed to `kube-system` |

---

## Implementation Status

- [x] Deploy EVCC with minimal config
- [x] Configure SQLite database
- [x] Configure MQTT connection to EMQX
- [x] Create HTTPRoute for external access
- [ ] Obtain sponsor token
- [ ] Add Alfen wallbox configuration
- [ ] Add SolarEdge inverter configuration
- [ ] Add DSMR meter via Home Assistant
- [ ] Configure loadpoint
- [ ] Verify MQTT discovery in Home Assistant
