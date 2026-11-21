# Power Outage Recovery

What happens to the cluster when the mains power fails, and how to recover when it does not come back by itself.

---

## Power layout

| Host | Behind the UPS | Notes |
|------|----------------|-------|
| `dmn-sk-pve-01` (10.0.10.200) | Yes | Runs every guest: Talos VMs, AdGuard, the QDevice, NUT |
| `dmn-sk-pve-02` (10.0.10.201) | **No** | Cluster member, idle. Loses power first |
| UniFi gateway/switch, Synology NAS | Yes | |

UPS: PowerWalker PR1500 R1U (900 W). At the current load (about 10%) it reports roughly 55-60 minutes of runtime.

NUT runs in LXC 250 (`nut-server`, 10.0.10.180) as the primary. `dmn-sk-pve-01` is a secondary and runs `shutdown -h +0` on a forced shutdown. NUT is managed from the separate `nut-server` Ansible repository.

LOWBATT is reported at **20 minutes of runtime left** (`override.battery.runtime.low = 1200` in `ups.conf`). The device default is 5 minutes, which is too short for six Talos VMs to stop cleanly.

---

## During the outage

1. pve-02 goes down immediately. pve-01 plus the QDevice (LXC 200, 10.0.10.202) still have 2 of 3 votes, so the cluster stays quorate.
2. pve-01 keeps running until LOWBATT. NUT then triggers a forced shutdown and the UPS cuts its outlets (this includes the NAS and the network gear).
3. Proxmox stops the guests in reverse startup order: guests without an order, then workers (`order=3`), control planes (`order=2`), then the LXCs (`order=1`).

---

## Cold boot after a long outage

### The quorum catch

The QDevice runs on pve-01 itself. After a full power loss pve-01 boots with **1 of 3 votes**, so the cluster is not quorate. Proxmox does not start guests without quorum (`cluster not ready - no quorum?`), so LXC 200 cannot start itself either.

- **Normal case:** pve-02 powers on, joins, and the two nodes reach 2 of 3 votes. Guests then start by themselves in startup order.
- **pve-02 does not come back:** pve-01 stays without guests until you force quorum (below).

pve-02 only powers on by itself if its BIOS has **Restore on AC power loss = Power On**. Keep that setting enabled.

### Startup order once quorate

| Order | Guests | Delay before the next group |
|-------|--------|-----------------------------|
| 1 | LXC 200 (QDevice), LXC 250 (NUT) | - |
| 2 | `prd-cp-01..03` | 60 s |
| 3 | `prd-w-01..03` | - |
| none | AdGuard LXCs (1000, 1001), other guests without a startup order | start after the ordered groups |

### Forcing quorum on pve-01

Only do this when pve-02 is confirmed down or unreachable, and never while both nodes are up. Check first:

```bash
ssh root@10.0.10.200 pvecm status        # Quorate: No, Total votes: 1
ping -c 2 10.0.10.201                    # pve-02 not answering
```

Then:

```bash
pvecm expected 1
# Guests may not have autostarted while there was no quorum. Start them in order:
pct start 200 && pct start 250
pct start 1000 && pct start 1001
for v in 500 501 502; do qm start $v; done
sleep 60
for v in 503 504 505; do qm start $v; done
```

When pve-02 comes back, check that the vote count recovered:

```bash
pvecm status      # Expected votes: 3, Total votes: 3, Qdevice listed
```

If the QDevice is missing, check that LXC 200 is running and that `corosync-qdevice` is active on both nodes.

---

## Checks after recovery

```bash
export KUBECONFIG=resources/bootstrap/output/kube-config.yaml
kubectl get nodes                                    # all 6 Ready
kubectl get pods -A | grep -v -E "Running|Completed"
kubectl get volumes -n longhorn-system               # healthy; rebuilds may run for a while
kubectl get cluster -n cnpg-system                   # "Cluster in healthy state"
```

- Longhorn may rebuild replicas after an unclean stop. Do not reboot further nodes until the volumes are healthy again.
- The descheduler spreads pods back over the workers in the following hours (see CLAUDE.md, "Talos operations").
- If the cluster was stopped by LOWBATT, also check that the UPS outlets came back on and that NUT reports `OL` again: `upsc powerwalker@10.0.10.180 ups.status`.

---

## Related

- [Talos Upgrade](talos-upgrade.md) for the node power-cycle script.
- [Troubleshooting](troubleshooting.md) for etcd and Longhorn problems after an unclean stop.
