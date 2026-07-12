# Zigbee2MQTT — IoT Gateway

Zigbee to MQTT bridge for smart home device integration.

## Overview

**Status:** ✅ Deployed (2026-01-17)
**Purpose:** Bridge Zigbee devices to MQTT for Home Assistant integration.
**Namespace:** `zigbee2mqtt`
**Chart:** Custom Helm chart

---

## Architecture

```
┌───────────────┐
│ Home Assistant  │
└───────┬────────┘
        │ MQTT
        ↓
┌───────────────┐
│     EMQX       │
└───────┬────────┘
        │ MQTT
        ↓
┌───────────────┐
│  Zigbee2MQTT   │
│  (Kubernetes)  │
└───────┬────────┘
        │ TCP
        ↓
┌───────────────────┐
│ Zigbee Coordinator│
│ tcp://10.0.30.176:6638 │
└───────────────────┘
        │
        ↓
  Zigbee Devices
```

---

## Custom Helm Chart

**Why custom?** The upstream chart doesn't support the init container pattern needed to copy configuration from a secret to the PV without `subPath` conflicts.

**Chart:** `resources/gitops-config/applications/zigbee2mqtt/`

---

## Configuration

| Setting | Value |
|---------|-------|
| Type | StatefulSet |
| Replicas | 1 |
| Image | `koenkk/zigbee2mqtt:2.12.1` |
| Storage | 2Gi (longhorn-standard) |

### Zigbee Coordinator

**Type:** TCP Zigbee coordinator (no USB passthrough needed, runs on any node)
**Address:** `tcp://10.0.30.176:6638`

```yaml
serial:
  port: tcp://10.0.30.176:6638
  adapter: auto
```

---

## Init Container Pattern

**Problem:** Using `subPath` on secret volume caused conflicts with existing PV data.

**Solution:** Init container copies configuration from the secret to the PV at startup.

```yaml
initContainers:
- name: copy-config
  image: busybox:1.37.0
  command:
  - /bin/sh
  - -c
  - |
    cp /app/readonly/configuration.yaml /app/data/configuration.yaml
  volumeMounts:
  - name: config-volume
    mountPath: /app/readonly
    readOnly: true
  - name: data-volume
    mountPath: /app/data
```

The main container then reads `/app/data/configuration.yaml` normally.

---

## Secrets Management

**ExternalSecret:** `zigbee2mqtt-config`
**1Password Item:** `zigbee2mqtt-config` (KubernetesSecrets vault)

The entire `configuration.yaml` is stored as a single secret field and copied to the PV by the init container.

---

## Configuration Example

```yaml
homeassistant: true
permit_join: false

mqtt:
  base_topic: zigbee2mqtt
  server: mqtt://emqx.emqx.svc.cluster.local:1883
  user: admin
  password: <password>

serial:
  port: tcp://10.0.30.176:6638
  adapter: auto

advanced:
  log_level: info
  pan_id: 6754
  network_key: [1, 3, 5, 7, 9, 11, 13, 15, 0, 2, 4, 6, 8, 10, 12, 13]

frontend:
  port: 8080
  host: 0.0.0.0

devices: devices.yaml
groups: groups.yaml
```

---

## Backup & Restore

The PV contains:
- `database.db` (89.3K) — device database with all pairings
- `devices.yaml` (4.3K) — device configuration and friendly names
- `state.json` (19.5K) — current device states
- `coordinator_backup.json` (15.1K) — Zigbee coordinator backup

### Restore Procedure

```bash
# 1. Create restore pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backup-restore
  namespace: zigbee2mqtt
spec:
  restartPolicy: Never
  containers:
  - name: restore
    image: busybox:latest
    command: ["sh", "-c", "sleep 600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-volume-zigbee2mqtt-0
EOF

# 2. Copy backup files
kubectl cp ~/Downloads/z2m-backup/ zigbee2mqtt/backup-restore:/tmp/backup
kubectl exec -n zigbee2mqtt backup-restore -- cp -r /tmp/backup/* /data/

# 3. Cleanup
kubectl delete pod backup-restore -n zigbee2mqtt

# 4. Sync in ArgoCD
argocd app sync zigbee2mqtt
```

---

## ArgoCD Sync Policy

**Auto-sync disabled** — manual sync required to prevent accidental pod restarts that could conflict with the Zigbee coordinator during migrations.

---

## Monitoring

```bash
# Pod status
kubectl get pods -n zigbee2mqtt

# Logs
kubectl logs -n zigbee2mqtt -l app=zigbee2mqtt -f

# Check coordinator connection
kubectl logs -n zigbee2mqtt -l app=zigbee2mqtt | grep -i "coordinator"

# Check MQTT connection
kubectl logs -n zigbee2mqtt -l app=zigbee2mqtt | grep -i "mqtt"
```

**Successful startup messages:**
```
Zigbee2MQTT:info  Starting Zigbee2MQTT version 2.12.1
Zigbee2MQTT:info  MQTT connected
Zigbee2MQTT:info  Coordinator firmware version: ...
```

---

## Troubleshooting

### Coordinator Connection Failed

**Symptom:** `read ECONNRESET`
**Cause:** Another Zigbee2MQTT instance holds the connection

```bash
nc -zv 10.0.30.176 6638   # Verify coordinator available
kubectl rollout restart statefulset zigbee2mqtt -n zigbee2mqtt
```

### Configuration Not Applied

Config is copied once at pod startup by the init container. To update:

```bash
# 1. Update 1Password item zigbee2mqtt-config
# 2. Delete ExternalSecret to force refresh
kubectl delete externalsecret zigbee2mqtt-config -n zigbee2mqtt
# 3. Restart pod
kubectl rollout restart statefulset zigbee2mqtt -n zigbee2mqtt
```

### Devices Missing After Restore

```bash
kubectl exec -n zigbee2mqtt zigbee2mqtt-0 -- ls -lah /app/data/
# database.db should be >80KB
# devices.yaml should contain device list
```
