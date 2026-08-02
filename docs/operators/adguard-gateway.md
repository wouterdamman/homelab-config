# AdGuard Home Gateway Integration

**Source:** `resources/gitops-config/infrastructure/adguard/`, `resources/gitops-config/infrastructure/adguard-kids/`
**Access URLs:** `https://adguard.svc.damman.tech`, `https://kids-adguard.svc.damman.tech`
**Status:** Deployed (2026-08-01)

---

## Overview

Two AdGuard Home instances (primary + kids) run as LXC containers on Proxmox, outside the Kubernetes cluster — same pattern as the [Proxmox gateway](proxmox-gateway.md), but TLS-**terminate** rather than passthrough, since AdGuard's web UI speaks plain HTTP internally (no self-signed cert to preserve).

---

## Architecture

```
User (browser)
  ↓
https://adguard.svc.damman.tech / https://kids-adguard.svc.damman.tech
  ↓
Cilium Gateway (10.0.10.240) — svc-https-listener
  - TLS Terminate (wildcard-svc-gateway-tls-cert)
  ↓
AdGuard Home LXC (10.0.10.220:80 / 10.0.10.221:80)
  - Proxmox VE, node dmn-sk-pve-01, vmid 1000 / 1001
```

---

## Components (per instance)

### Kubernetes Service + Endpoints

- **Type:** Headless Service (ClusterIP: None)
- **Namespace:** infrastructure
- **External IP:** `10.0.10.220:80` (primary) / `10.0.10.221:80` (kids)

### HTTPRoute

- **Hostname:** `adguard.svc.damman.tech` / `kids-adguard.svc.damman.tech`
- **Parent Gateway:** svc-gateway, listener `svc-https-listener`
- **Rule:** explicit `matches: [{path: {type: PathPrefix, value: /}}]` and explicit `backendRefs[].{group: '', kind: Service, weight: 1}` — **required**, not optional. Omitting either causes the Kubernetes API server to inject its own defaults on the live object that never match what's in git, and ArgoCD's diff never resolves — the app perpetually self-heals/re-applies every reconcile (~15s) forever. Hit this bug building the AdGuard routes; fixed by making both fields explicit rather than relying on defaulting.

No dedicated CiliumNetworkPolicy needed — the generic `gateway-ingress-identity-egress` clusterwide policy already allows the per-node Gateway Envoy (`reserved:ingress`) egress to `world` on ports 80/443, which covers this. (Contrast with the Proxmox gateway, which needed its own policy for port 8006 specifically since only 80/443 are in the generic allow-list.)

---

## Known network gotcha: LXC subnet mask mismatch

Both AdGuard LXC containers were provisioned with the wrong netmask on their Proxmox network interface — `/26` (network 10.0.10.192–255) instead of the actual "Server network" `/25` (10.0.10.128–255) that the Talos nodes are also on. Even though everything sits on the same L2 bridge (`vmbr1`, same Proxmox node `dmn-sk-pve-01`), the container's own kernel routing decided any client outside its (wrongly narrow) local subnet — including the Talos node IPs — needed to go via its default gateway rather than being answered directly on the bridge. Result: TCP SYN reached the container fine, but the SYN-ACK reply got routed away and lost, producing a **silent connection timeout** with no trace in any firewall log (UniFi router, Proxmox host/CT/datacenter firewall, ebtables) since nothing was actually blocking it — it was a routing decision, not a filter.

**Fix applied:** corrected both `net0` configs via the Proxmox API from `/26` to `/25`, then rebooted both containers.

```bash
# Diagnostic sequence that found it (all firewall layers ruled out first):
pct exec 1000 -- iptables -L -n -v   # empty — no OS firewall
pct exec 1000 -- nft list ruleset    # not installed
ebtables -L                          # empty on the Proxmox host
# ...then compared net0 netmask against a working Talos VM's ipconfig0 — mismatch found
```

If AdGuard (or any other LXC on this node) becomes unreachable from the cluster again with a plain connect timeout and no firewall rule anywhere explains it, check this first:

```bash
curl -sk https://pve.svc.damman.tech:8006/api2/json/nodes/<node>/lxc/<vmid>/config | jq -r .data.net0
```

---

## Troubleshooting

### Cannot connect to adguard.svc.damman.tech

```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n infrastructure -- \
  curl -sk -v https://adguard.svc.damman.tech/

kubectl get httproute -n infrastructure adguard-httproute -o yaml
kubectl get application adguard -n argocd -o jsonpath='{.status.resources}'
```

### ArgoCD shows the app perpetually OutOfSync / re-applying

Check the HTTPRoute's `backendRefs` and `matches` are fully explicit (see Components above) — this was the root cause the one time it happened here.

### Widget/homepage dashboard reports it down but the site loads fine in browser

Check homepage's widget/siteMonitor is using `https://` not `http://` — the `svc-http-listener` (port 80) has no HTTPRoute attached for AdGuard, so plain-HTTP requests get an unhandled redirect that Node's fetch client refuses to follow (`ERR_FR_REDIRECTION_FAILURE`). See [Homepage docs](../applications/homepage.md).
