# Home Assistant - Smart Home Platform

**Source:** `resources/gitops-config/applications/home_assistant/`  
**Namespace:** `home-assistant`  
**External Access:** `https://ha.app.damman.tech`  
**Code-Server:** `https://codeserver.svc.damman.tech`  
**Status:** Deployed & Migrated (2026-01-28, migrated from 10.0.10.165)

---

## Overview

Local-first smart home automation platform. Central hub for device control, automations, and scenes.

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                Home Assistant (Kubernetes)                │
│                                                          │
│  ┌─────────────────┐    ┌─────────────────────────────┐  │
│  │ Home Assistant  │    │  Code-Server (sidecar)      │  │
│  │ :8123           │    │  :8080 (internal)            │  │
│  │ (runs as root)  │    │  :12321 (service)            │  │
│  └────────┬────────┘    └────────────┬────────────────┘  │
│           │                          │                    │
│           └──────────┐  ┌────────────┘                   │
│                      ▼  ▼                                 │
│              ┌────────────────┐                           │
│              │  /config (PVC) │                           │
│              │   10Gi         │                           │
│              └────────────────┘                           │
└──────────────────────────────────────────────────────────┘
       │ MQTT          │ PostgreSQL        │ Zigbee
       ▼               ▼                  ▼
   EMQX            CNPG               Zigbee2MQTT
 (tcp://emqx)   (homeassistant DB)   (MQTT bridge)
```

---

## Deployment

**StatefulSet** — 1 replica, `hostNetwork: true`, `dnsPolicy: ClusterFirstWithHostNet`

`hostNetwork: true` is required for local device discovery (mDNS/Bonjour) and direct device access.

### Init Container

```yaml
initContainers:
- name: fix-permissions
  image: busybox:1.37.0
  command: [sh, -c, "chown -R :911 /config && chmod -R g+rw /config && find /config -type d -exec chmod g+s {} ;"]
  securityContext:
    runAsUser: 0
```

Fixes `/config` permissions for UID 911 (the `abc` user). Required because code-server and HA share the volume.

### Security Context

```yaml
# Pod-level
securityContext:
  fsGroup: 911
  fsGroupChangePolicy: "OnRootMismatch"

# Container-level (HA main)
securityContext:
  runAsUser: 0
  runAsGroup: 0
```

HA runs as root — required for installing Python packages and device access.

---

## Configuration

### Service

```yaml
service:
  type: LoadBalancer
  port: 8123
  annotations:
    io.cilium/lb-ipam-ips: "10.0.10.242"
  loadBalancerIP: 10.0.10.242
```

### HTTPRoutes

```yaml
# Home Assistant
- hostname: ha.app.damman.tech
  timeout: "0s"          # disabled — required for WebSocket
  gateway: app-gateway (app-https-listener)
  backend: home-assistant:8123

# Code-Server
- hostname: codeserver.svc.damman.tech
  timeout: "0s"          # disabled — required for WebSocket
  gateway: svc-gateway (svc-https-listener)
  backend: home-assistant-codeserver:12321
```

> **Important:** `timeout: "0s"` disables the request timeout for both routes. Without this, WebSocket connections (used by the HA frontend) are dropped after ~15s on WiFi, causing a black screen. See [Known Issues](#known-issues).

### Storage

```yaml
persistence:
  enabled: true
  size: 10Gi
  storageClassName: longhorn-standard
```

---

## Resource Limits

| Container | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|----------------|--------------|
| home-assistant | 200m | 1000m | 512Mi | 2Gi |
| codeserver | 50m | 500m | 128Mi | 512Mi |

---

## Secrets

Managed via ExternalSecrets (1Password → `KubernetesSecrets` vault):

| Secret | 1Password Item | Key | Mount |
|--------|----------------|-----|-------|
| `homeassistant-secrets` | homeassistant-secrets | secrets.yaml | `/config/secrets.yaml` (HA only) |
| `home-assistant-ssh-key` | github-ssh-key-codeserver | private_key | `/home/coder/.ssh/id_ed25519` (code-server only) |

SSH known hosts for `github.com` are configured via ConfigMap (for git operations in code-server).

---

## Code-Server

Code-server runs as a sidecar on the same pod, sharing the `/config` volume. This allows editing Home Assistant configuration files from a browser IDE.

```yaml
addons:
  codeserver:
    enabled: true
    image: ghcr.io/coder/code-server:4.128.0
    service:
      type: ClusterIP
      port: 12321
```

- Workspace root: `/config`
- VS Code settings: `/config/.vscode`
- Extensions: `/config/.vscode-extensions`
- Auth: none (protected by Gateway + network policy)

---

## Database

PostgreSQL via CloudNative-PG operator:

```yaml
# In home_assistant/configuration.yaml
recorder:
  db_url: postgresql://homeassistant:<password>@cnpg-shared-rw.cnpg-system.svc/homeassistant
```

The `homeassistant` database is provisioned in the shared CNPG cluster.

---

## Known Issues

### Black Screen on WiFi (Resolved)

**Symptom:** HA app shows black screen when connecting from WiFi. Works fine on LAN.

**Root cause:** Cilium Gateway API default request timeout (15s) was dropping WebSocket connections. HA frontend relies on long-lived WebSocket connections; WiFi latency caused handshake to exceed the timeout.

**Fix:** Set `timeout: "0s"` on both HTTPRoutes (HA and code-server) to disable the timeout.

```yaml
timeouts:
  request: "0s"
```

**Commit:** `fix: disable HTTPRoute request timeout for HA and codeserver WebSocket connections`

---

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n home-assistant

# View HA logs
kubectl logs -n home-assistant -l app.kubernetes.io/name=home-assistant -c home-assistant -f

# View code-server logs
kubectl logs -n home-assistant -l app.kubernetes.io/name=home-assistant -c codeserver -f

# Check init container logs
kubectl logs -n home-assistant -l app.kubernetes.io/name=home-assistant -c fix-permissions

# Check ExternalSecret sync
kubectl get externalsecret -n home-assistant
kubectl describe externalsecret -n home-assistant homeassistant-secrets

# Access HA API for health check
kubectl exec -n home-assistant home-assistant-0 -- curl -s http://localhost:8123/api/
```

### Reset configuration (emergency)

```bash
# Shell into HA container
kubectl exec -it -n home-assistant home-assistant-0 -c home-assistant -- bash

# Check configuration
cat /config/configuration.yaml
cat /config/secrets.yaml  # should show secret values injected by ESO
```
