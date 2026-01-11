# Proxmox VE Gateway API Integration

Exposes external Proxmox VE server via Cilium Gateway API with TLS passthrough and Authentik SSO integration.

## Architecture

```
User (https://pve.svc.damman.tech:8006)
  ↓
Cilium Gateway (10.0.10.240:8006) - TLS Passthrough
  ↓
Proxmox VE (10.0.10.200:8006) - TLS Termination
  ↓
Authentik OpenID Connect (SSO)
```

## Components

- **Service + Endpoints**: Maps external Proxmox IP (10.0.10.200:8006) to Kubernetes Service
- **TLSRoute**: Routes traffic based on SNI (pve.svc.damman.tech) with TLS passthrough
- **Gateway Listener**: Port 8006 with TLS passthrough mode
- **Authentik OIDC**: OpenID Connect provider for SSO authentication

## Access

- **URL**: https://pve.svc.damman.tech:8006
- **Port**: 8006 (TLS passthrough, same as original Proxmox port)
- **TLS**: Proxmox's own certificate (not Let's Encrypt via Gateway)
- **Authentication**:
  - Local Proxmox users (pam/pve realm)
  - Authentik SSO (openid realm) - **RECOMMENDED**

## Authentik OpenID Connect Configuration

### 1. Create OAuth2/OpenID Provider in Authentik

1. Login to Authentik: https://sso.svc.damman.tech/if/admin/
2. Navigate to **Applications** → **Providers** → **Create**
3. Select **OAuth2/OpenID Connect Provider**
4. Configuration:
   ```
   Name: Proxmox VE
   Authentication flow: default-authentication-flow
   Authorization flow: default-provider-authorization-explicit-consent

   Client type: Confidential
   Client ID: proxmox-ve
   Client Secret: <generate strong secret - save this!>

   Redirect URIs/Origins (RegEx):
   https://pve\.svc\.damman\.tech:8006/.*

   Scopes: openid, profile, email

   Subject mode: Based on the User's hashed ID
   Include claims in id_token: Yes
   ```

5. Click **Finish**

### 2. Create Application in Authentik

1. Navigate to **Applications** → **Applications** → **Create**
2. Configuration:
   ```
   Name: Proxmox VE
   Slug: proxmox-ve
   Provider: Proxmox VE (select the provider created above)
   Launch URL: https://pve.svc.damman.tech:8006
   ```

3. Click **Create**

### 3. Configure Proxmox OpenID Connect Realm

SSH to Proxmox server or use the web console:

```bash
pveum realm add openid --issuer-url https://sso.svc.damman.tech/application/o/proxmox-ve/ \
  --client-id proxmox-ve \
  --client-key <client-secret-from-authentik> \
  --username-claim preferred_username \
  --comment "Authentik SSO"

# Verify configuration
pveum realm list
```

Or via Proxmox Web UI:
1. Navigate to **Datacenter** → **Permissions** → **Realms**
2. Click **Add** → **OpenID Connect Server**
3. Configuration:
   ```
   Realm: openid
   Issuer URL: https://sso.svc.damman.tech/application/o/proxmox-ve/
   Client ID: proxmox-ve
   Client Key: <client-secret-from-authentik>
   Username Claim: preferred_username
   Scopes: openid profile email
   Comment: Authentik SSO
   ```
4. Click **Add**

### 4. Create Proxmox User for Authentik

```bash
# Create user in openid realm
pveum user add yourname@openid --firstname "Your" --lastname "Name" --email "you@example.com"

# Grant permissions (example: Administrator)
pveum aclmod / --user yourname@openid --role Administrator
```

Or via Web UI:
1. **Datacenter** → **Permissions** → **Users** → **Add**
2. Username: `yourname`
3. Realm: `openid`
4. Fill in details
5. Click **Add**
6. Navigate to **Permissions** → **Add User Permission**
7. Path: `/`
8. User: `yourname@openid`
9. Role: `Administrator` (or custom role)

### 5. Test Login

1. Logout of Proxmox
2. Go to https://pve.svc.damman.tech:8006
3. Select **Realm**: `openid` (Authentik SSO)
4. Click **Login**
5. You'll be redirected to Authentik
6. Login with your Authentik credentials
7. Approve the consent screen
8. You'll be redirected back to Proxmox

## Troubleshooting

### Cannot access pve.svc.damman.tech:8006

```bash
# Check DNS resolution
dig pve.svc.damman.tech

# Should return: 10.0.10.240 (Gateway IP)

# Check Gateway status
kubectl get gateway -n kube-system svc-gateway

# Check TLSRoute
kubectl get tlsroute -n infrastructure proxmox-tlsroute

# Check Service endpoints
kubectl get endpoints -n infrastructure proxmox

# Test connectivity from cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl -k -v https://pve.svc.damman.tech:8006
```

### OpenID Connect login fails

```bash
# Check Proxmox logs
journalctl -u pveproxy -f

# Common issues:
# 1. Incorrect Client Secret
# 2. Wrong Issuer URL (must end with /)
# 3. Redirect URI not matching in Authentik
# 4. User doesn't exist in openid realm
```

### Verify Authentik OIDC configuration

```bash
# Test OIDC discovery endpoint
curl -k https://sso.svc.damman.tech/application/o/proxmox-ve/.well-known/openid-configuration | jq .

# Should return JSON with:
# - issuer
# - authorization_endpoint
# - token_endpoint
# - userinfo_endpoint
# - jwks_uri
```

### Certificate warnings

This is **expected behavior** with TLS passthrough. The Gateway doesn't terminate TLS, so you'll see Proxmox's self-signed certificate warning in your browser. Options:

1. **Accept the certificate** (easiest for homelab)
2. **Install Proxmox's certificate** in your browser's trusted store
3. **Replace Proxmox certificate** with Let's Encrypt certificate on Proxmox itself

## Security Notes

1. **TLS Passthrough**: Traffic is encrypted end-to-end, Gateway cannot inspect it
2. **Port 8006**: Non-standard HTTPS port, may be blocked by some firewalls
3. **Authentik SSO**: Provides centralized authentication and MFA support
4. **Proxmox Certificate**: Consider replacing self-signed cert with proper certificate
5. **Network Access**: Gateway IP (10.0.10.240) should be reachable from your network

## References

- [Cilium Gateway API TLS Passthrough](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
- [Proxmox OpenID Connect](https://pve.proxmox.com/wiki/User_Management#pveum_openid_configuration)
- [Authentik OAuth2 Provider](https://docs.goauthentik.io/docs/providers/oauth2/)
- [External Services with Gateway API](https://blog.stonegarden.dev/articles/2024/04/k8s-external-services/)
