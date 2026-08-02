# Homepage — Homelab Dashboard

Central dashboard for all homelab services, replacing the never-deployed Homarr (see [ADR-016/017](../architecture/adr.md)).

## Overview

**Status:** ✅ Deployed (2026-08-01)
**Purpose:** Single-page overview of every operator/app in the cluster, with live widgets where available.
**Namespace:** `homepage`
**External Access:** https://homepage.app.damman.tech (Authentik forward-auth protected)

---

## Architecture

```
┌────────────────────────────────────────────┐
│  Gateway (app-gateway) - homepage.app.damman.tech │
└──────────────────────┬───────────────────────┘
                       │
              ┌─────────────────┐
              │ Authentik Outpost │  (forward-auth, port 9000)
              │ (ghcr.io/goauthentik/proxy) │
              └────────┬─────────┘
                       │ (only path in)
              ┌─────────────────┐
              │  Homepage        │  (ghcr.io/gethomepage/homepage, port 3000)
              │  (ClusterRole:   │
              │   nodes/pods/    │
              │   metrics.k8s.io)│
              └────────┬─────────┘
                       │
        ┌──────────────┼──────────────────────┐
        │              │                      │
   in-cluster       gateway (world:443/80)   siteMonitor
   Services       (Proxmox 8006, AdGuard,     (ping-only,
   (ArgoCD,        no in-cluster route)       no widget)
   Grafana,
   Authentik,
   Home Assistant,
   EVCC)
```

No database — config is plain YAML, fully GitOps-managed (`resources/gitops-config/applications/homepage/values.yaml`). No CNPG dependency, no backup/restore surface.

---

## Widget → target routing (important gotcha)

Server-side widget API calls (ArgoCD, Grafana, Authentik, EVCC, Home Assistant) point at the **in-cluster Service**, not the external `*.svc.damman.tech`/`*.app.damman.tech` hostname:

| Widget | Internal URL |
|--------|---------------|
| ArgoCD | `http://argo-cd-argocd-server.argocd.svc.cluster.local` |
| Grafana | `http://prometheus-community-grafana.monitoring.svc.cluster.local` |
| Authentik | `http://authentik-server.authentik.svc.cluster.local` |
| EVCC | `http://evcc.evcc.svc.cluster.local:7070` |
| Home Assistant | `http://home-assistant.home-assistant.svc.cluster.local:8123` |

**Why:** going through the external gateway hostname from homepage's own Node HTTP client (both `fetch`/undici and the built-in `https` module) returns a bare 403 "Access denied" from Envoy — root cause not identified despite extensive testing (ruled out RBAC/token validity, HTTP/1.1 vs HTTP/2, TLS version, User-Agent, Host header port suffix, backend replica randomness; `curl` on the identical path with the identical token succeeds every time). Routing internally sidesteps it entirely and is the more efficient path anyway.

Proxmox and AdGuard widgets still use the external hostname — they have no in-cluster Service to hairpin to (Proxmox is a bare-metal host, AdGuard is an LXC container), so they go through the gateway's TLS-passthrough/terminate path like normal.

**Home Assistant is a special case:** it runs `hostNetwork: true`, so its pod IP is a node IP, not a pod-overlay IP. The CiliumNetworkPolicy egress rule for it uses `toEntities: remote-node`, not `toEndpoints` label matching (which never identifies hostNetwork pods).

---

## Widgets with live data (credentialed)

| Service | Widget type | 1Password item | Fields |
|---------|------------|-----------------|--------|
| Proxmox VE | `proxmox` | `Proxmox - Automation Account` (reused) | VMs, LXC, CPU, MEM |
| AdGuard Home / Kids | `adguard` | `Adguard` (reused) | queries, blocked, filtered, latency |
| ArgoCD | `argocd` | `homepage-argocd` | apps, synced, healthy, outOfSync |
| Grafana | `grafana` | `grafana-admin` (reused) | dashboards, alerts triggered |
| Authentik | `authentik` (`version: 2`) | `homepage-authentik-api` | users, logins (24h), failed logins (24h) |
| EVCC | `evcc` | none needed | production, grid, consumption, charger |
| Home Assistant | `homeassistant` | `homepage-homeassistant` | people home, lights on, switches on |

Each credential is a **separate** ExternalSecret/Secret (not one bundled secret) — consumed via `envFrom` with `optional: true` on the Deployment, so a missing 1Password item only breaks that one widget instead of blocking every credential at once.

Authentik widget: uses a dedicated Service Account (`homepage-dashboard`, RBAC role `homepage-dashboard-readonly` granting `authentik_core.view_user` + `authentik_events.view_event` globally) rather than a personal admin token.

---

## Services with no native widget (siteMonitor only)

Longhorn, Hubble, Zigbee2MQTT, EMQX, NetBox, LucidVault, Home Finance, Code-server — no widget exists in homepage for any of these. Each gets `siteMonitor: <url>` (HTTP up/down + latency), no credentials needed.

NetBox is marked "(uitgeschakeld)" — its ArgoCD Application is commented out (never actually deployed, same dormant state Homarr was in before removal). `siteMonitor` correctly shows it down.

---

## Forward-auth (Authentik outpost)

Dedicated per-app outpost, same pattern as zigbee2mqtt and the Home Assistant code-server addon — **not** the domain-level embedded outpost (see [Authentik docs](authentik.md#outpost-forward-auth)):

- Outpost Deployment+Service in `templates/outpost-deployment.yaml`/`outpost-service.yaml`, image `ghcr.io/goauthentik/proxy`, port 9000.
- Provider + Outpost + Application declared via Authentik blueprint ConfigMap: `resources/gitops-config/operators/authentik/templates/homepage-proxy-outpost-blueprint.yaml`. The Outpost's `config` field is **required** by Authentik's schema — omitting it makes the blueprint fail silently (`status: error`, no outpost object created, no error visible in worker logs without querying the Managed Blueprints API directly).
- One manual step, unavoidable: after the blueprint creates the Outpost, its service-account token has to be copied from the Authentik UI (Outposts → homepage → token) into 1Password item `authentik-outpost-homepage`.

---

## Images (background / PWA icons)

homepage's `next.config.js` only allowlists `cdn.jsdelivr.net` for external images (`remotePatterns`) — any other domain (e.g. `images.unsplash.com`) silently fails to render, no error anywhere. Both the dashboard background and the PWA icons are committed to this repo at `resources/gitops-config/applications/homepage/assets/` and served via jsdelivr's GitHub-raw proxy:

```
https://cdn.jsdelivr.net/gh/wouterdamman/homelab-config@main/resources/gitops-config/applications/homepage/assets/<file>
```

---

## Cluster-wide resources widget

Top-of-page widget shows cluster CPU/memory (not just the homepage pod's own negligible usage). Requires:
- `kubernetesYaml: mode: cluster`
- `widgets.yaml` → `kubernetes.cluster` **and** `kubernetes.nodes` blocks both present (frontend crashes with `TypeError: Cannot read properties of undefined (reading 'show')` if only `cluster` is set).
- ServiceAccount + ClusterRole (`get`/`list` on `nodes`/`namespaces`/`pods` and `metrics.k8s.io` `nodes`/`pods`) — `templates/rbac.yaml`.

---

## Troubleshooting

### Widget shows "API Error Information"
Almost always a missing/wrong 1Password item, or the widget pointed at the external hostname instead of the internal Service (see routing table above). Check:
```bash
kubectl logs -n homepage deploy/homepage --tail=100 | grep -i <service>
kubectl get externalsecret -n homepage
```

### Widget "Missing Widget Type: X"
The widget type name doesn't exist in this homepage version — verify with `curl -o /dev/null -w '%{http_code}' https://gethomepage.dev/widgets/services/<name>/` before using it (returns 404 if it doesn't exist).

### siteMonitor tile shows red but service seems fine
Check the service's own ArgoCD Application actually exists and is synced — a `siteMonitor` red dot correctly reflects a genuinely down/undeployed app (this caught NetBox being disabled).
