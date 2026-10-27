#!/usr/bin/env bash
#
# Power-cycle one Talos node so staged Proxmox hardware changes (RAM, iothread,
# devices) take effect. A guest reboot keeps the same QEMU process; the pending
# config only applies on a full stop/start.
#
# Steps: wait until the cluster is calm, move etcd leadership away (control
# planes), cordon + drain, talosctl shutdown, qm start, wait for Ready (and
# etcd 3/3), uncordon, check that no Proxmox changes are left pending.
#
# Usage: ./scripts/powercycle-node.sh <node-name> [--dry-run]
#        e.g. ./scripts/powercycle-node.sh prd-w-01
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export TALOSCONFIG="${SCRIPT_DIR}/../output/talos-config.yaml"
export KUBECONFIG="${SCRIPT_DIR}/../output/kube-config.yaml"

PROXMOX_HOST="root@10.0.10.200"
# Optional ssh jump host, e.g. PROXMOX_JUMP=root@10.0.10.201 when pve-01 port 22
# is not reachable directly.
PROXMOX_JUMP="${PROXMOX_JUMP:-}"
CP_IPS="10.0.10.130,10.0.10.131,10.0.10.132"
CALM_MINUTES="${CALM_MINUTES:-5}"
CALM_TIMEOUT_MIN=30

NODE="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { log "ERROR: $*"; exit 1; }
run() { if $DRY_RUN; then log "[dry-run] $*"; else "$@"; fi; }

case "$NODE" in
  prd-cp-01) IDX=0 ;; prd-cp-02) IDX=1 ;; prd-cp-03) IDX=2 ;;
  prd-w-01) IDX=3 ;; prd-w-02) IDX=4 ;; prd-w-03) IDX=5 ;;
  *) die "unknown node '$NODE' (expected prd-cp-0[1-3] or prd-w-0[1-3])" ;;
esac
IP="10.0.10.$((130 + IDX))"
VMID=$((500 + IDX))
IS_CP=false
[[ "$NODE" == prd-cp-* ]] && IS_CP=true

etcd_members() {
  # Count only rows with a member ID; unreachable nodes must not count.
  talosctl -n "$CP_IPS" etcd status 2>/dev/null \
    | awk 'NR>1 && $2 ~ /^[0-9a-f]+$/ && length($2)==16' | wc -l | tr -d ' ' || true
}

etcd_warnings_since() {
  talosctl -n "$CP_IPS" logs etcd --tail 500 2>/dev/null \
    | grep -E "heartbeat|slow fdatasync|elected" \
    | grep -oE '"ts":"[^"]{19}' | sed 's/"ts":"//' \
    | awk -v s="$1" '$1>=s' | wc -l | tr -d ' '
}

cluster_calm() {
  local since warn members cnpg_bad longhorn_bad nodes_bad
  since=$(date -u -v-"${CALM_MINUTES}"M +%Y-%m-%dT%H:%M:%S 2>/dev/null \
    || date -u -d "-${CALM_MINUTES} min" +%Y-%m-%dT%H:%M:%S)
  warn=$(etcd_warnings_since "$since")
  members=$(etcd_members)
  cnpg_bad=$(kubectl -n cnpg-system get cluster --no-headers -o custom-columns=P:.status.phase | grep -vc "healthy state" || true)
  longhorn_bad=$(kubectl -n longhorn-system get volumes.longhorn.io --no-headers | awk '$4!="healthy"' | wc -l | tr -d ' ')
  nodes_bad=$(kubectl get nodes --no-headers | grep -vc " Ready " || true)
  log "calm check: etcd_warn_${CALM_MINUTES}m=$warn members=$members cnpg_bad=$cnpg_bad longhorn_bad=$longhorn_bad nodes_bad=$nodes_bad"
  [[ "$warn" == 0 && "$members" == 3 && "$cnpg_bad" == 0 && "$longhorn_bad" == 0 && "$nodes_bad" == 0 ]]
}

wait_calm() {
  local deadline=$(( $(date +%s) + CALM_TIMEOUT_MIN * 60 ))
  until cluster_calm; do
    (( $(date +%s) < deadline )) || die "cluster not calm after ${CALM_TIMEOUT_MIN} min, not touching $NODE"
    sleep 30
  done
}

# One multiplexed connection for all Proxmox calls. The stop-wait loop polls
# every 5s; a new connection per poll got port 22 dropped on the way to pve-01
# mid-shutdown (2026-10-27), leaving the VM stopped.
pve() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 \
    -o ControlMaster=auto -o ControlPath="${TMPDIR:-/tmp}/pc-%r@%h:%p" -o ControlPersist=15m \
    ${PROXMOX_JUMP:+-J "$PROXMOX_JUMP"} "$PROXMOX_HOST" "$@"
}

proxmox_ssh_ok() {
  pve true 2>/dev/null
}

log "== $NODE (ip $IP, vmid $VMID, control plane: $IS_CP, dry-run: $DRY_RUN)"
# The VM can only be started again over ssh (qm start). With a locked
# 1Password SSH agent a shutdown would leave the node down, so check first.
proxmox_ssh_ok || die "no ssh access to $PROXMOX_HOST (1Password SSH agent locked?), not touching $NODE"
log "pending Proxmox changes:"
pve "qm pending $VMID" | grep -E '^(new|del)' || log "  none (power cycle will not change hardware)"

wait_calm

if $IS_CP; then
  leader_id=$(talosctl -n "$IP" etcd status 2>/dev/null | awk 'NR==2{print $8}')  # columns: node member size MB inuse MB (pct) leader
  member_id=$(talosctl -n "$IP" etcd status 2>/dev/null | awk 'NR==2{print $2}')
  if [[ "$leader_id" == "$member_id" ]]; then
    log "$NODE is etcd leader, forfeiting leadership"
    run talosctl -n "$IP" etcd forfeit-leadership
    $DRY_RUN || sleep 15
  fi
fi

proxmox_ssh_ok || die "lost ssh access to $PROXMOX_HOST while waiting, not touching $NODE"

log "cordon + drain $NODE"
run kubectl cordon "$NODE"
# Longhorn keeps instance-managers of strict-local volumes behind a PDB; the
# drain then times out, which is expected. The shutdown stops them anyway.
run kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data \
  --grace-period=120 --timeout=10m || log "drain did not finish cleanly, continuing"

if ! proxmox_ssh_ok; then
  run kubectl uncordon "$NODE"
  die "lost ssh access to $PROXMOX_HOST after the drain; uncordoned $NODE, not shutting it down"
fi

log "shutting down $NODE"
run talosctl -n "$IP" shutdown --wait=false
if ! $DRY_RUN; then
  for _ in $(seq 1 60); do
    st=$(pve "qm status $VMID" 2>/dev/null | awk '{print $2}' || true)
    [[ "$st" == "stopped" ]] && break
    sleep 5
  done
  [[ "$st" == "stopped" ]] || die "VM $VMID did not stop within 5 min; check it in Proxmox"
fi

log "starting VM $VMID"
run pve "qm start $VMID"

if ! $DRY_RUN; then
  # The Node object still says Ready for a while after the shutdown, so wait
  # for the rebooted kubelet on the node itself first.
  log "waiting for kubelet on $NODE"
  for _ in $(seq 1 90); do
    talosctl -n "$IP" service kubelet 2>/dev/null | grep -qE "HEALTH +OK" && break
    sleep 10
  done
  log "waiting for $NODE to become Ready"
  for _ in $(seq 1 90); do
    kubectl get node "$NODE" --no-headers 2>/dev/null | grep -q " Ready" && break
    sleep 10
  done
  kubectl get node "$NODE" --no-headers | grep -q " Ready" || die "$NODE not Ready after 15 min"
  if $IS_CP; then
    for _ in $(seq 1 60); do [[ "$(etcd_members)" == 3 ]] && break; sleep 10; done
    [[ "$(etcd_members)" == 3 ]] || die "etcd not back to 3/3 members"
  fi
fi

log "uncordon $NODE"
run kubectl uncordon "$NODE"

left=$(pve "qm pending $VMID" | grep -cE '^(new|del)' || true)
log "pending Proxmox changes left on $VMID: $left"
log "== $NODE done"
