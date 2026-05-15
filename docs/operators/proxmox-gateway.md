# Proxmox VE Gateway Integration

**Source:** `resources/gitops-config/infrastructure/proxmox/`
**Access URL:** `https://pve.svc.damman.tech:8006`
**Status:** Deployed

---

## Overview

Proxmox VE is exposed via Cilium Gateway API with TLS passthrough, allowing secure access through a custom domain while maintaining Proxmox's own TLS certificate. Authentication is handled through Authentik OpenID Connect SSO.

---

## Architecture

```
User (browser)
  ↓
https://pve.svc.damman.tech:8006
  ↓
Cilium Gateway (10.0.10.240:8006)
  - TLS Passthrough (SNI routing)
  - No TLS termination
  ↓
Proxmox VE (10.0.10.200:8006)
  - Bare metal server
  - TLS termination
  - OpenID Connect → Authentik
```

---

## Components

### Kubernetes Service + Endpoints

- **Type:** Headless Service (ClusterIP: None)
- **Namespace:** infrastructure
- **External IP:** 10.0.10.200:8006
- **Purpose:** Maps external Proxmox server into Kubernetes service mesh

### TLSRoute

- **Hostname:** `pve.svc.damman.tech`
- **Parent Gateway:** svc-gateway
- **Listener:** svc-tls-passthrough-listener (port 8006)
- **Mode:** TLS Passthrough (SNI-based routing)
- **Backend:** proxmox:8006

---

## Authentication Methods

**OpenID (Authentik SSO) — RECOMMENDED**
- Realm: `openid`
- Centralized authentication with MFA support
- Single Sign-On across services

**PAM (Local Linux users)**
- Realm: `pam`
- Traditional Proxmox authentication
- For admin/recovery access only

---

## Authentik OpenID Connect Setup

### 1. Create OAuth2 Provider in Authentik

1. Login to Authentik → **Applications** → **Providers** → **Create**
2. Select **OAuth2/OpenID Connect Provider**

| Field | Value |
|-------|-------|
| Name | Proxmox VE |
| Client type | Confidential |
| Client ID | `proxmox-ve` |
| Client Secret | Generate strong secret (32+ chars) |
| Redirect URIs | `https://pve\.svc\.damman\.tech:8006/.*` |
| Scopes | openid, profile, email |
| Include claims in id_token | Yes |

### 2. Create Application in Authentik

- Name: Proxmox VE, Slug: proxmox-ve
- Provider: Proxmox VE (from step 1)
- Launch URL: `https://pve.svc.damman.tech:8006`

### 3. Configure Proxmox OpenID Realm

```bash
pveum realm add openid \
  --issuer-url https://sso.svc.damman.tech/application/o/proxmox-ve/ \
  --client-id proxmox-ve \
  --client-key <client-secret-from-authentik> \
  --username-claim preferred_username \
  --comment "Authentik SSO"

pveum realm list
```

> **Note:** The issuer URL must end with `/` (trailing slash required).

### 4. Create Proxmox Users

```bash
pveum user add yourname@openid \
  --firstname "Your" \
  --lastname "Name"

pveum aclmod / --user yourname@openid --role Administrator
```

---

## Let's Encrypt Certificate

**Status:** Configured and Active  
**Deployment Date:** 2026-01-11  
**Method:** Proxmox ACME with Cloudflare DNS-01 Challenge  
**Auto-Renewal:** Enabled (via `pve-daily-update.timer`)

```bash
# Check renewal timer
systemctl status pve-daily-update.timer

# View last renewal
journalctl -u pve-daily-update.service | grep -i acme

# Manual renewal test
pvenode acme cert renew --force
```

---

## Troubleshooting

### Cannot connect to pve.svc.damman.tech:8006

```bash
dig pve.svc.damman.tech

kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl -k -v https://pve.svc.damman.tech:8006

kubectl get gateway -n kube-system svc-gateway -o yaml
kubectl describe tlsroute -n infrastructure proxmox-tlsroute
```

### OpenID Connect login fails

```bash
ssh root@10.0.10.200
journalctl -u pveproxy -f
```

**Common causes:**
- Incorrect Client Secret → Update in Proxmox realm config
- Wrong Issuer URL → Must end with `/` (trailing slash required)
- Redirect URI mismatch → Check regex in Authentik provider
- User doesn't exist → Create user in `openid` realm
- No permissions → Grant role to user

```bash
# Test OIDC discovery
curl -k https://sso.svc.damman.tech/application/o/proxmox-ve/.well-known/openid-configuration | jq .
```

### Certificate not auto-renewing

```bash
pvenode config get | grep acme
pvenode acme plugin list
pvenode acme cert order  # manual renewal
```

---

## Security Considerations

| Aspect | Status | Note |
|--------|--------|------|
| End-to-end encryption | ✅ | TLS passthrough — Gateway can't decrypt |
| L7 traffic inspection | ⚠️ | Gateway can't inspect (no filtering) |
| Authentik SSO + MFA | ✅ | Centralized user management |
| Local PAM fallback | ✅ | Emergency access preserved |
| Non-standard port 8006 | ⚠️ | May be blocked by some firewalls |
