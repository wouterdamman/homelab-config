#!/usr/bin/env bash
#
# Power-cycle one Talos node so staged Proxmox hardware changes (RAM, iothread,
# devices) take effect. A guest reboot keeps the same QEMU process; the pending
# config only applies on a full stop/start.
#
# Steps: wait until the cluster is calm, silence the alerts the power cycle
# triggers, move etcd leadership away (control planes) and CNPG primaries off
# the node, cordon + drain, talosctl shutdown, qm start, wait for Ready (and
# etcd 3/3), uncordon, wait until Longhorn and CNPG are healthy again, check
# that no Proxmox changes are left pending. The silences are expired on exit,
# also when the script fails, so a node left down still alerts.
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
HEALTHY_TIMEOUT_MIN=30
AM_POD="alertmanager-prometheus-alertmanager-0"
# Cluster-wide symptoms of one node being down. Alerts that carry the node
# name or IP are silenced by separate matchers; Watchdog stays untouched.
SILENCED_ALERTS="TargetDown|KubePodNotReady|KubeDeploymentReplicasMismatch|KubeStatefulSetReplicasMismatch|KubeDaemonSetRolloutStuck|KubeDaemonSetMisScheduled|etcdMembersDown|etcdInsufficientMembers|etcdHighNumberOfLeaderChanges"

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

cnpg_bad_count() {
  kubectl -n cnpg-system get cluster --no-headers -o custom-columns=P:.status.phase | grep -vc "healthy state" || true
}

longhorn_bad_count() {
  kubectl -n longhorn-system get volumes.longhorn.io --no-headers | awk '$4!="healthy"' | wc -l | tr -d ' '
}

cluster_calm() {
  local since warn members cnpg_bad longhorn_bad nodes_bad
  since=$(date -u -v-"${CALM_MINUTES}"M +%Y-%m-%dT%H:%M:%S 2>/dev/null \
    || date -u -d "-${CALM_MINUTES} min" +%Y-%m-%dT%H:%M:%S)
  warn=$(etcd_warnings_since "$since")
  members=$(etcd_members)
  cnpg_bad=$(cnpg_bad_count)
  longhorn_bad=$(longhorn_bad_count)
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

amtool() {
  kubectl -n monitoring exec "$AM_POD" -c alertmanager -- \
    amtool --alertmanager.url=http://localhost:9093 "$@"
}

SILENCE_IDS=""
silence_alerts() {
  local m id
  for m in "node=$NODE" "instance=~$IP:.*" "id=qemu/$VMID" "alertname=~$SILENCED_ALERTS"; do
    if $DRY_RUN; then log "[dry-run] silence $m"; continue; fi
    id=$(amtool silence add --duration=90m --author=powercycle-node.sh \
      --comment="power cycle $NODE" "$m") || { log "could not add silence $m, continuing"; continue; }
    SILENCE_IDS="$SILENCE_IDS $id"
  done
  [[ -z "$SILENCE_IDS" ]] || log "silences:$SILENCE_IDS"
}

expire_silences() {
  [[ -n "$SILENCE_IDS" ]] || return 0
  # shellcheck disable=SC2086 # word splitting is intended
  amtool silence expire $SILENCE_IDS && log "silences expired" \
    || log "could not expire silences:$SILENCE_IDS (they end after 90m)"
}

# The primary's PDB allows no disruption, so the drain would time out on it
# and the shutdown would force an unplanned failover. Switch over to a ready
# replica on another node first.
cnpg_switchover() {
  local cluster primary target
  for cluster in $(kubectl -n cnpg-system get cluster -o jsonpath='{.items[*].metadata.name}'); do
    primary=$(kubectl -n cnpg-system get cluster "$cluster" -o jsonpath='{.status.currentPrimary}')
    [[ "$(kubectl -n cnpg-system get pod "$primary" -o jsonpath='{.spec.nodeName}')" == "$NODE" ]] || continue
    target=$(kubectl -n cnpg-system get pods -l "cnpg.io/cluster=$cluster,cnpg.io/instanceRole=replica" -o json \
      | jq -r --arg n "$NODE" '.items[]
          | select(.spec.nodeName != $n)
          | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
          | .metadata.name' | head -1)
    [[ -n "$target" ]] || die "$cluster primary $primary is on $NODE and there is no ready replica on another node"
    log "$cluster: switchover $primary -> $target"
    run kubectl cnpg promote -n cnpg-system "$cluster" "$target"
    $DRY_RUN && continue
    for _ in $(seq 1 30); do
      [[ "$(kubectl -n cnpg-system get cluster "$cluster" -o jsonpath='{.status.currentPrimary}/{.status.phase}')" \
        == "$target/Cluster in healthy state" ]] && break
      sleep 10
    done
    [[ "$(kubectl -n cnpg-system get cluster "$cluster" -o jsonpath='{.status.currentPrimary}')" == "$target" ]] \
      || die "$cluster switchover to $target did not finish within 5 min"
  done
}

wait_storage_healthy() {
  local cnpg_bad longhorn_bad deadline=$(( $(date +%s) + HEALTHY_TIMEOUT_MIN * 60 ))
  log "waiting for Longhorn volumes and CNPG clusters to be healthy"
  while true; do
    cnpg_bad=$(cnpg_bad_count)
    longhorn_bad=$(longhorn_bad_count)
    [[ "$cnpg_bad" == 0 && "$longhorn_bad" == 0 ]] && { log "storage healthy"; return; }
    (( $(date +%s) < deadline )) \
      || die "after ${HEALTHY_TIMEOUT_MIN} min still cnpg_bad=$cnpg_bad longhorn_bad=$longhorn_bad, check before the next node"
    sleep 30
  done
}

log "== $NODE (ip $IP, vmid $VMID, control plane: $IS_CP, dry-run: $DRY_RUN)"
# The VM can only be started again over ssh (qm start). With a locked
# 1Password SSH agent a shutdown would leave the node down, so check first.
proxmox_ssh_ok || die "no ssh access to $PROXMOX_HOST (1Password SSH agent locked?), not touching $NODE"
log "pending Proxmox changes:"
pve "qm pending $VMID" | grep -E '^(new|del)' || log "  none (power cycle will not change hardware)"

wait_calm

trap expire_silences EXIT
silence_alerts

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

cnpg_switchover

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

$DRY_RUN || wait_storage_healthy

left=$(pve "qm pending $VMID" | grep -cE '^(new|del)' || true)
log "pending Proxmox changes left on $VMID: $left"
log "== $NODE done"
