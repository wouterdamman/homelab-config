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

## SSO (SAML 2.0 via Authentik)

**Status:** ✅ Working (2026-06-22)
**Method:** SAML 2.0, SP-initiated. NOT OIDC — see below for why.

### Why SAML, not OIDC

Native OIDC SSO was attempted first (Authentik provider type OAuth2/OIDC). It never worked reliably and was abandoned after extensive debugging, because EMQX's backend has to make a **server-to-server** call (token exchange, and the `.well-known/openid-configuration` discovery fetch) to Authentik via the public hostname — and that call hairpins through the same Cilium Gateway that fronts both EMQX and Authentik. Cilium's Gateway anti-hairpin protection blocks this unconditionally, independent of any CiliumNetworkPolicy (see `docs/operators/cilium.md` → "Gateway Hairpin / Anti-Hairpin Protection"). EMQX's OIDC client has no config option to route discovery/token calls anywhere except the public issuer URL, so there was no way around it from EMQX's side.

SAML avoids the problem structurally: after the IdP metadata is fetched once (at SSO config save time), the actual login is pure browser-redirect — Authentik signs an assertion and the user's browser POSTs it straight to EMQX's ACS endpoint, no backend-to-backend call involved.

### Setup

**1. Authentik — SAML Provider** (created via API, not Terraform — Authentik providers/applications in this cluster are not GitOps-managed):
- ACS URL: `https://emqx.svc.damman.tech/api/v5/sso/saml/acs`
- Issuer / SP Entity ID: `https://emqx.svc.damman.tech/api/v5/sso/saml/metadata`
- `sp_binding: post` — **must** be `post`, not `redirect`. This setting controls how Authentik delivers the signed Response to the ACS URL; EMQX's ACS endpoint only accepts POST and returns `405` on a redirect-bound (GET) response.
- `name_id_mapping` + `property_mappings`: set to the "authentik default SAML Mapping: Username" (and Email/Name) mappings — without this, Authentik issues an opaque persistent NameID and EMQX displays that hex string instead of a real username.
- Bound to the existing "EMQX Dashboard" Application (swapped from the old OAuth2/OIDC provider).

**2. EMQX dashboard SSO settings:**
- Dashboard Address: `https://emqx.svc.damman.tech`
- SAML Metadata URL: `http://emqx-saml-metadata.emqx.svc.cluster.local/metadata.xml` (see below — **not** Authentik's real metadata URL)

### The esaml binding bug (why there's a static metadata server)

EMQX's SAML client is the Erlang `esaml` library. It has a binding mismatch bug that no configuration on either side fixes:

- `esaml.erl`'s metadata parser only ever extracts the IdP metadata's `SingleSignOnService` entry where `Binding='...HTTP-POST'` (hardcoded XPath) for the login URL.
- `emqx_dashboard_sso_saml.erl` then always sends the AuthnRequest via `esaml_binding:encode_http_redirect` (GET, deflated query param) — regardless of which binding that URL was actually meant for.

Net effect: EMQX takes the URL meant for POST and GETs it instead. Authentik's real `/sso/binding/post/` endpoint expects a POST body, finds none, and returns `400 Bad Request: The SAML payload is missing`.

Authentik has no setting to suppress or alter just one binding's `Location` in its generated metadata, and EMQX exposes no manual binding override. The fix is `resources/gitops-config/applications/emqx/templates/saml-metadata-server.yaml`: a tiny static nginx server in the `emqx` namespace serving a hand-patched copy of Authentik's metadata (same entity ID, same signing cert, only the `HTTP-POST` entry's `Location` swapped to point at the `HTTP-Redirect` endpoint instead, which actually accepts the GET that EMQX sends). The document-level XML signature is stripped since it's invalid after the edit — harmless, `esaml` doesn't verify metadata signing, only the IdP signing cert inside `KeyDescriptor` (kept verbatim), which is what matters for validating actual SAML Responses.

If Authentik's signing cert ever rotates, this ConfigMap needs to be regenerated by hand (re-fetch metadata, re-apply the same `sed` swap on the `HTTP-POST` Location, redeploy).

### NetworkPolicy notes

`resources/gitops-config/applications/emqx/templates/networkpolicy.yaml` has an ingress + egress rule pair scoped to `app: emqx-saml-metadata` in-namespace — that's the only cross-pod traffic this SSO setup needs, since the metadata server is local and the actual login flow is browser-only (no EMQX→Authentik traffic at all post-setup).

The old OIDC-era rules (`fromEntities: ingress` on port 443, `toEntities: world` on port 443) were removed when OIDC was abandoned.

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
