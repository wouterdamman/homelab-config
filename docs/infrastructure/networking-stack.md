# Networking Stack — UniFi

Complete UniFi network configuration for the homelab environment.

## Overview

The network consists of a UniFi Dream Machine (UDM), managed switches, and access points. Infrastructure is divided into logical segments (VLANs) for clients, IoT devices, servers, and management.

---

## Networks and VLANs

| Name | VLAN | Subnet | Purpose | DHCP |
|------|------|--------|---------|------|
| Default | 1 | 192.168.2.0/27 | Fallback / adoption | Server |
| Client | 10 | 10.0.10.0/26 | Everyday devices | Server |
| Kids | 11 | 10.0.10.64/29 | Kids' devices | Server |
| Server | 13 | 10.0.10.128/25 | NAS/servers/homelab | Server |
| IoT | 30 | 10.0.30.0/24 | IoT & cameras | Server |
| Guest | 40 | 10.0.40.128/28 | Guests | Server |
| MGMT | 99 | 10.0.99.0/24 | UniFi device management | Off |
| Xbox | 255 | 10.255.1.0/29 | Game console | Server |

**VLAN notes:**
- **Server (VLAN 13):** Kubernetes cluster runs here (10.0.10.130–135)
- **MGMT (VLAN 99):** UniFi devices only, static IPs, no DHCP
- **IoT (VLAN 30):** Cameras use 10.0.30.10–19, DHCP range 10.0.30.50–200

---

## Management IP Plan

| Function | IP |
|----------|----|
| Router / UDM | 10.0.99.1 |
| Core switch | 10.0.99.2 |
| Distribution switch | 10.0.99.3 |
| Edge switches | 10.0.99.5–6 |
| Access points | 10.0.99.20–25 |
| Cameras (wired) | 10.0.30.10–19 (IoT) |

---

## Wi-Fi Networks

| SSID | VLAN | Bands | Security | Notes |
|------|------|-------|----------|-------|
| Another Brick in the Firewall | Client | 2.4/5/6 GHz | WPA2/WPA3 | General devices |
| Goomba Network | Kids | 2.4/5/6 GHz | WPA2/WPA3 | Content filtering + 50/5 Mbit/s limit |
| Gadget Galaxy | IoT | 2.4 GHz | WPA2 | IoT devices |
| Guest Galaxy | Guest | 2.4 GHz | WPA2/WPA3 | Hidden, 5/5 Mbit/s limit |

---

## Ethernet Port Profiles

| Profile | Native VLAN | Tagged VLANs | Use Case |
|---------|-------------|--------------|---------|
| ETH-AP-UPLINK | MGMT (99) | Client/Kids/IoT/Guest | Access points |
| ETH-SWITCH-UPLINK | Default (1) | Allow All | Switch uplinks |
| ETH-SERVER-ACCESS | Server | Block All | NAS and servers |
| ETH-IOT-WIRED | IoT (30) | Block All | Cameras, Zigbee hub |

---

## Zones & Firewall

| Zone | Networks |
|------|---------|
| Internal | Default, Client, Kids, Xbox, MGMT |
| IoT | IoT |
| Server | Server |
| Guest | Guest |
| VPN | Client-VPN |
| External | WAN1 |

**Key firewall rules:**
- MGMT → ALL: Management traffic allowed to all zones
- BLOCK → MGMT: All zones blocked from management VLAN
- IoT × Gateway: IoT blocked from UDM port 80/443
- IoT Established → Client: Return traffic only (no initiation)
- Sonos → Client: Multicast audio allowed

---

## VPN — WireGuard

- **Port:** 51820 (WAN1)
- **Subnet:** 10.0.100.0/29 (5 usable addresses)
- **Purpose:** Remote management and lab access
- **Access:** VPN → Management VLAN and Servers

---

## Services

- **mDNS Proxy:** Enabled for Client (10), IoT (30), Server (13)
- **IGMP Snooping:** Enabled for Client, IoT, Xbox, Server (Sonos multicast)

---

## WAN Configuration

- **WAN1:** KPN (active)
- **WAN2:** Not configured (available for failover)
- **Port forwarding:** None (WireGuard only via firewall)

---

## Kubernetes Network Integration

The Talos cluster runs on VLAN 13 (Server):

| Resource | IP/Range |
|----------|---------|
| Kubernetes nodes | 10.0.10.130–135 |
| Cluster VIP | 10.0.10.140 |
| Gateway | 10.0.10.193 |
| Cilium LB Pool | 10.0.10.240–250 |
| App Gateway | 10.0.10.241 |

---

## DNS Integration — external-dns

Automatic DNS record management via UniFi's internal DNS using the external-dns webhook provider.

### Architecture

```
Kubernetes Resources → External-DNS → UniFi Webhook → UniFi DNS
(HTTPRoute, Service)    (controller)    (sidecar)      (10.0.10.193)
```

### Domain Filters

| Domain | Purpose | Example |
|--------|---------|---------|
| *.local.damman.tech | Internal services | proxmox.local.damman.tech |
| *.svc.damman.tech | Kubernetes services | argocd.svc.damman.tech |
| *.app.damman.tech | Applications (via Gateway) | home.app.damman.tech |

### DNS Flow Example

```
1. User creates HTTPRoute for myapp.app.damman.tech
2. Cilium Gateway assigns route to app-gateway (10.0.10.241)
3. External-DNS detects the HTTPRoute
4. Webhook calls UniFi API to create DNS record:
   myapp.app.damman.tech → 10.0.10.241
5. Internal clients resolve myapp.app.damman.tech
```

### Troubleshooting DNS

```bash
# Check external-dns logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns -f

# Check webhook connectivity
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns -c webhook

# Test DNS resolution
kubectl run -it --rm dns-test --image=busybox -- nslookup myapp.app.damman.tech
```

UniFi DNS records: UniFi Console → Settings → Networks → DNS Records
