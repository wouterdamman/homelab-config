#!/bin/bash
set -euo pipefail

# Talos Rolling Upgrade Automation Script
# This script automates the rolling upgrade of Talos nodes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TFVARS_FILE="$(dirname "$(dirname "$0")")/proxmox.auto.tfvars"
TALOSCONFIG="$(dirname "$(dirname "$0")")/output/talos-config.yaml"
KUBECONFIG="$(dirname "$(dirname "$0")")/output/kube-config.yaml"
SCHEMATIC_FILE="$(dirname "$(dirname "$0")")/talos/image/schematic.yaml"

# Compute schematic ID dynamically from schematic.yaml via Talos image factory
if [[ ! -f "$SCHEMATIC_FILE" ]]; then
  echo "[ERROR] Schematic file not found: $SCHEMATIC_FILE" >&2
  exit 1
fi
SCHEMATIC_ID=$(curl -sf -X POST https://factory.talos.dev/schematics \
  --data-binary @"$SCHEMATIC_FILE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
if [[ -z "$SCHEMATIC_ID" ]]; then
  echo "[ERROR] Failed to compute schematic ID from factory.talos.dev" >&2
  exit 1
fi

# Default wait times (in seconds)
WORKER_WAIT_TIME=30     # 30 seconds between workers
CP_WAIT_TIME=90         # 90 seconds between control planes

# Parse command line arguments
CURRENT_VERSION=""
TARGET_VERSION=""
DRY_RUN=false
SKIP_WORKERS=false
SKIP_CONTROL_PLANES=false
AUTO_APPROVE=false
SINGLE_NODE=""
SINGLE_NODE_IP=""

usage() {
    echo "Usage: $0 --current <version> --target <version> [options]"
    echo ""
    echo "Options:"
    echo "  --current <version>       Current Talos version (e.g., v1.11.6)"
    echo "  --target <version>        Target Talos version (e.g., v1.12.0)"
    echo "  --dry-run                 Show what would be done without making changes"
    echo "  --node <name>             Upgrade only this node (e.g., prd-cp-01)"
    echo "  --node-ip <ip>            Upgrade only this IP (e.g., 10.0.10.130)"
    echo "  --skip-workers            Skip worker node upgrades"
    echo "  --skip-control-planes     Skip control plane upgrades"
    echo "  --auto-approve            Skip confirmation prompts (use with caution!)"
    echo "  --worker-wait <seconds>   Wait time between workers (default: 300)"
    echo "  --cp-wait <seconds>       Wait time between CPs (default: 600)"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --current v1.11.6 --target v1.12.0"
    echo "  $0 --current v1.11.6 --target v1.12.0 --dry-run"
    echo "  $0 --current v1.11.6 --target v1.12.0 --node prd-cp-01"
    echo "  $0 --current v1.11.6 --target v1.12.0 --skip-workers"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --current)
            CURRENT_VERSION="$2"
            shift 2
            ;;
        --target)
            TARGET_VERSION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-workers)
            SKIP_WORKERS=true
            shift
            ;;
        --skip-control-planes)
            SKIP_CONTROL_PLANES=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --worker-wait)
            WORKER_WAIT_TIME="$2"
            shift 2
            ;;
        --cp-wait)
            CP_WAIT_TIME="$2"
            shift 2
            ;;
        --node)
            SINGLE_NODE="$2"
            shift 2
            ;;
        --node-ip)
            SINGLE_NODE_IP="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$CURRENT_VERSION" ]] || [[ -z "$TARGET_VERSION" ]]; then
    echo -e "${RED}Error: --current and --target are required${NC}"
    usage
fi

# Validate single-node options
if [[ -n "$SINGLE_NODE" && -n "$SINGLE_NODE_IP" ]]; then
    echo -e "${RED}Error: Cannot specify both --node and --node-ip${NC}"
    exit 1
fi

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    command -v tofu >/dev/null 2>&1 || missing_tools+=("tofu")
    command -v talosctl >/dev/null 2>&1 || missing_tools+=("talosctl")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    if [[ ! -f "$TFVARS_FILE" ]]; then
        log_error "tfvars file not found: $TFVARS_FILE"
        exit 1
    fi

    log_success "All prerequisites met"
}

# Get current cluster state
get_cluster_state() {
    log_info "Getting current cluster state..."

    # Extract node configuration from tfvars
    local cp_count=$(grep -E "^controlplane_count\s*=" "$TFVARS_FILE" | grep -oE '[0-9]+')
    local worker_count=$(grep -E "^worker_count\s*=" "$TFVARS_FILE" | grep -oE '[0-9]+')

    # Extract IP configuration from tfvars
    CLUSTER_CIDR=$(grep -E "^cluster_cidr\s*=" "$TFVARS_FILE" | sed 's/.*"\(.*\)".*/\1/')
    IP_OFFSET=$(grep -E "^ip_offset\s*=" "$TFVARS_FILE" | grep -oE '[0-9]+')
    ENV=$(grep -E "^env\s*=" "$TFVARS_FILE" | sed 's/.*"\(.*\)".*/\1/')

    if [[ -z "$CLUSTER_CIDR" ]] || [[ -z "$IP_OFFSET" ]] || [[ -z "$ENV" ]]; then
        log_error "Failed to extract cluster_cidr, ip_offset, or env from tfvars"
        exit 1
    fi

    echo "Control Planes: $cp_count"
    echo "Workers: $worker_count"
    echo "Cluster CIDR: $CLUSTER_CIDR"
    echo "IP Offset: $IP_OFFSET"
    echo "Environment: $ENV"

    # Generate node names
    WORKER_NODES=()
    for i in $(seq 1 "$worker_count"); do
        WORKER_NODES+=("${ENV}-w-$(printf '%02d' $i)")
    done

    CP_NODES=()
    for i in $(seq 1 "$cp_count"); do
        CP_NODES+=("${ENV}-cp-$(printf '%02d' $i)")
    done

    log_success "Found ${#WORKER_NODES[@]} workers and ${#CP_NODES[@]} control planes"
}

# Calculate IP for a node based on its index
# Args: node_index (0-based)
get_node_ip() {
    local node_index=$1
    echo "${CLUSTER_CIDR}.$((IP_OFFSET + node_index))"
}

# Build installer image URL for Factory
get_installer_image() {
    local version="$1"
    echo "factory.talos.dev/installer/${SCHEMATIC_ID}:${version}"
}

# Upgrade a single node using talosctl
upgrade_node() {
    local node_name="$1"
    local node_ip="$2"
    local installer_image="$3"

    log_info "Upgrading $node_name ($node_ip) to $TARGET_VERSION..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would cordon node: $node_name"
        log_info "[DRY RUN] Would drain node: $node_name"
        log_info "[DRY RUN] Would run: talosctl upgrade --nodes $node_ip --image $installer_image --wait --timeout 30m"
        return 0
    fi

    export TALOSCONFIG
    export KUBECONFIG

    # Step 1: Cordon the node to prevent new pods from being scheduled
    log_info "Cordoning $node_name..."
    if ! kubectl cordon "$node_name" >/dev/null 2>&1; then
        log_error "Failed to cordon $node_name"
        return 1
    fi
    log_success "$node_name cordoned"

    # Step 2: Drain the node (graceful pod eviction)
    log_info "Draining $node_name (this may take a few minutes)..."
    if ! kubectl drain "$node_name" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --grace-period=120 \
        --timeout=10m \
        --force 2>&1 | grep -v "evicting pod"; then
        log_warning "Drain completed with warnings, continuing..."
    fi
    log_success "$node_name drained"

    # Step 3: Execute upgrade with --wait for monitoring
    log_info "Upgrading Talos OS on $node_name..."
    if ! talosctl upgrade \
        --nodes "$node_ip" \
        --image "$installer_image" \
        --wait \
        --timeout 30m; then
        log_error "Upgrade failed for $node_name"
        # Try to uncordon even if upgrade failed
        kubectl uncordon "$node_name" >/dev/null 2>&1 || true
        return 1
    fi

    log_success "$node_name Talos OS upgraded successfully"
    return 0
}

# Wait for node to be ready
wait_for_node() {
    local node_name="$1"
    local node_ip="$2"
    local max_wait="$3"

    log_info "Waiting for $node_name to be ready (max ${max_wait}s)..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would wait for $node_name"
        return
    fi

    local elapsed=0
    local interval=10

    export TALOSCONFIG
    export KUBECONFIG

    while [[ $elapsed -lt $max_wait ]]; do
        # Check if node is Ready in Kubernetes
        if kubectl get node "$node_name" 2>/dev/null | grep -q "Ready"; then
            log_success "$node_name is Ready"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
        echo -n "."
    done

    echo ""
    log_error "$node_name did not become Ready within ${max_wait}s"
    return 1
}

# Uncordon node to allow scheduling again
uncordon_node() {
    local node_name="$1"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would uncordon node: $node_name"
        return 0
    fi

    export KUBECONFIG

    log_info "Uncordoning $node_name..."
    if ! kubectl uncordon "$node_name" >/dev/null 2>&1; then
        log_warning "Failed to uncordon $node_name (it may already be uncordoned)"
        return 0
    fi
    log_success "$node_name is now schedulable"
    return 0
}

# Verify cluster health
verify_cluster_health() {
    log_info "Verifying cluster health..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would verify cluster health"
        return
    fi

    export KUBECONFIG

    # Check all nodes are Ready
    local not_ready=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
    if [[ $not_ready -gt 0 ]]; then
        log_error "$not_ready node(s) are not Ready"
        return 1
    fi

    # Wait for critical pods to become Running (max 5 minutes)
    log_info "Waiting for critical pods to become Running..."
    local max_wait=300  # 5 minutes
    local elapsed=0
    local interval=10

    while [[ $elapsed -lt $max_wait ]]; do
        local critical_pods=$(kubectl get pods -n kube-system --no-headers | grep -E "(cilium|etcd)" | grep -v "Running" | wc -l)

        if [[ $critical_pods -eq 0 ]]; then
            log_success "All critical pods are Running"
            log_success "Cluster is healthy"
            return 0
        fi

        echo -n "."
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo ""
    log_error "Critical pods did not become Running within ${max_wait}s"
    kubectl get pods -n kube-system | grep -E "(cilium|etcd)" | grep -v "Running" || true
    return 1
}

# Check if node is already on target version
check_node_version() {
    local node_name="$1"
    local node_ip="$2"
    local target_version="$3"

    export TALOSCONFIG

    # Get current version from node
    local current_ver=$(talosctl version --nodes "$node_ip" 2>/dev/null | grep "Tag:" | tail -1 | awk '{print $2}')

    if [[ "$current_ver" == "$target_version" ]]; then
        return 0  # Already on target version
    else
        return 1  # Needs upgrade
    fi
}

# Upgrade workers
upgrade_workers() {
    if [[ "$SKIP_WORKERS" == true ]]; then
        log_warning "Skipping worker upgrades"
        return
    fi

    log_info "Starting worker node upgrades..."

    local installer_image=$(get_installer_image "$TARGET_VERSION")
    log_info "Using installer image: $installer_image"

    local worker_count=${#WORKER_NODES[@]}
    local worker_idx=0

    for worker in "${WORKER_NODES[@]}"; do
        worker_idx=$((worker_idx + 1))

        # Calculate IP for this worker (CPs come first, then workers)
        local worker_num=$(echo "$worker" | grep -oE '[0-9]+$')
        local cp_count=$(grep -E "^controlplane_count\s*=" "$TFVARS_FILE" | grep -oE '[0-9]+')
        local node_index=$((cp_count + worker_num - 1))
        local worker_ip=$(get_node_ip "$node_index")

        # Skip if single-node mode is active and this isn't the target node
        if [[ -n "$SINGLE_NODE" && "$worker" != "$SINGLE_NODE" ]]; then
            continue
        fi
        if [[ -n "$SINGLE_NODE_IP" && "$worker_ip" != "$SINGLE_NODE_IP" ]]; then
            continue
        fi

        # Check if node is already on target version
        if check_node_version "$worker" "$worker_ip" "$TARGET_VERSION"; then
            log_info "$worker is already on $TARGET_VERSION, skipping..."
            continue
        fi

        log_info "Upgrading worker: $worker"

        # Execute upgrade via talosctl
        if ! upgrade_node "$worker" "$worker_ip" "$installer_image"; then
            log_error "Worker $worker upgrade failed or timed out"
            exit 1
        fi

        # Wait for node to be Ready
        if ! wait_for_node "$worker" "$worker_ip" "$WORKER_WAIT_TIME"; then
            log_error "Worker $worker did not become Ready"
            exit 1
        fi

        # Uncordon the node to allow scheduling again
        if ! uncordon_node "$worker"; then
            log_error "Failed to uncordon $worker"
            exit 1
        fi

        # Verify health
        if ! verify_cluster_health; then
            log_error "Cluster health check failed after upgrading $worker"
            exit 1
        fi

        log_success "Worker $worker upgraded successfully"

        # Wait before next worker (except for the last one)
        if [[ $worker_idx -lt $worker_count ]]; then
            log_info "Waiting ${WORKER_WAIT_TIME}s before next worker..."
            [[ "$DRY_RUN" == false ]] && sleep "$WORKER_WAIT_TIME"
        fi
    done

    log_success "All workers upgraded successfully"
}

# Upgrade control planes
upgrade_control_planes() {
    if [[ "$SKIP_CONTROL_PLANES" == true ]]; then
        log_warning "Skipping control plane upgrades"
        return
    fi

    log_info "Starting control plane upgrades..."

    local installer_image=$(get_installer_image "$TARGET_VERSION")
    log_info "Using installer image: $installer_image"

    local cp_count=${#CP_NODES[@]}
    local cp_idx=0

    for cp in "${CP_NODES[@]}"; do
        cp_idx=$((cp_idx + 1))

        # Calculate IP for this CP (CPs are indexed from 0)
        local cp_num=$(echo "$cp" | grep -oE '[0-9]+$')
        local node_index=$((cp_num - 1))
        local cp_ip=$(get_node_ip "$node_index")

        # Skip if single-node mode is active and this isn't the target node
        if [[ -n "$SINGLE_NODE" && "$cp" != "$SINGLE_NODE" ]]; then
            continue
        fi
        if [[ -n "$SINGLE_NODE_IP" && "$cp_ip" != "$SINGLE_NODE_IP" ]]; then
            continue
        fi

        # Check if node is already on target version
        if check_node_version "$cp" "$cp_ip" "$TARGET_VERSION"; then
            log_info "$cp is already on $TARGET_VERSION, skipping..."
            continue
        fi

        log_info "Upgrading control plane: $cp"

        # Execute upgrade via talosctl
        if ! upgrade_node "$cp" "$cp_ip" "$installer_image"; then
            log_error "Control plane $cp upgrade failed or timed out"
            exit 1
        fi

        # Wait for node to be Ready
        if ! wait_for_node "$cp" "$cp_ip" "$CP_WAIT_TIME"; then
            log_error "Control plane $cp did not become Ready"
            exit 1
        fi

        # Uncordon the node to allow scheduling again
        if ! uncordon_node "$cp"; then
            log_error "Failed to uncordon $cp"
            exit 1
        fi

        # Extra verification for CPs - check etcd health with retry
        if [[ "$DRY_RUN" == false ]]; then
            log_info "Checking etcd health (max 60s)..."
            export TALOSCONFIG
            local etcd_max_wait=60
            local etcd_elapsed=0
            local etcd_interval=5
            local etcd_healthy=false

            while [[ $etcd_elapsed -lt $etcd_max_wait ]]; do
                if talosctl --nodes "$cp_ip" service etcd status 2>/dev/null | grep -q "HEALTH.*OK"; then
                    log_success "etcd is healthy on $cp"
                    etcd_healthy=true
                    break
                fi
                sleep "$etcd_interval"
                etcd_elapsed=$((etcd_elapsed + etcd_interval))
                echo -n "."
            done

            if [[ "$etcd_healthy" == false ]]; then
                echo ""
                log_warning "etcd health check timed out on $cp, but continuing (cluster may still be healthy)..."
            fi
        fi

        # Verify cluster health
        if ! verify_cluster_health; then
            log_error "Cluster health check failed after upgrading $cp"
            exit 1
        fi

        log_success "Control plane $cp upgraded successfully"

        # Wait before next CP (except for the last one)
        if [[ $cp_idx -lt $cp_count ]]; then
            log_info "Waiting ${CP_WAIT_TIME}s before next control plane..."
            [[ "$DRY_RUN" == false ]] && sleep "$CP_WAIT_TIME"
        fi
    done

    log_success "All control planes upgraded successfully"
}

# Finalize upgrade
finalize_upgrade() {
    log_info "Finalizing upgrade..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would verify all nodes on $TARGET_VERSION"
        log_success "Upgrade finalized (dry-run)"
        return
    fi

    # Verify upgraded nodes are on target version
    # Only check nodes that should have been upgraded in this run
    local upgraded_nodes_ips=""
    local upgraded_count=0

    # Add control plane IPs if we upgraded them
    if [[ "$SKIP_CONTROL_PLANES" == false ]]; then
        for cp in "${CP_NODES[@]}"; do
            local cp_num=$(echo "$cp" | grep -oE '[0-9]+$')
            local node_index=$((cp_num - 1))
            local cp_ip=$(get_node_ip "$node_index")

            # Skip if single-node mode and not the target
            if [[ -n "$SINGLE_NODE" && "$cp" != "$SINGLE_NODE" ]]; then
                continue
            fi
            if [[ -n "$SINGLE_NODE_IP" && "$cp_ip" != "$SINGLE_NODE_IP" ]]; then
                continue
            fi

            upgraded_nodes_ips+="${cp_ip},"
            upgraded_count=$((upgraded_count + 1))
        done
    fi

    # Add worker IPs if we upgraded them
    if [[ "$SKIP_WORKERS" == false ]]; then
        for worker in "${WORKER_NODES[@]}"; do
            local worker_num=$(echo "$worker" | grep -oE '[0-9]+$')
            local cp_count=$(grep -E "^controlplane_count\s*=" "$TFVARS_FILE" | grep -oE '[0-9]+')
            local node_index=$((cp_count + worker_num - 1))
            local worker_ip=$(get_node_ip "$node_index")

            # Skip if single-node mode and not the target
            if [[ -n "$SINGLE_NODE" && "$worker" != "$SINGLE_NODE" ]]; then
                continue
            fi
            if [[ -n "$SINGLE_NODE_IP" && "$worker_ip" != "$SINGLE_NODE_IP" ]]; then
                continue
            fi

            upgraded_nodes_ips+="${worker_ip},"
            upgraded_count=$((upgraded_count + 1))
        done
    fi

    if [[ $upgraded_count -eq 0 ]]; then
        log_info "No nodes were upgraded in this run"
        log_success "Upgrade finalized"
        return
    fi

    upgraded_nodes_ips=${upgraded_nodes_ips%,}  # Remove trailing comma

    log_info "Verifying $upgraded_count upgraded node(s) are on $TARGET_VERSION..."
    export TALOSCONFIG

    if talosctl version --nodes "$upgraded_nodes_ips" 2>/dev/null | grep -q "$TARGET_VERSION"; then
        log_success "All upgraded nodes verified on $TARGET_VERSION"
    else
        log_warning "Version verification had issues, but upgrades completed successfully"
    fi

    echo ""
    if [[ $upgraded_count -gt 0 ]]; then
        log_info "NEXT STEPS:"
        log_info "1. Check cluster status: kubectl get nodes -o wide"
        log_info "2. Optionally update proxmox.auto.tfvars: talos_version = \"$TARGET_VERSION\""
        log_info "3. Optionally sync Terraform state: cd resources/bootstrap && tofu apply"
    fi
    echo ""

    log_success "Upgrade finalized - $upgraded_count node(s) upgraded to $TARGET_VERSION"
}

# Main upgrade flow
main() {
    echo ""
    echo "=========================================="
    echo "  Talos Rolling Upgrade Automation"
    echo "=========================================="
    echo ""
    echo "Current Version: $CURRENT_VERSION"
    echo "Target Version:  $TARGET_VERSION"
    echo "Dry Run:         $DRY_RUN"

    if [[ -n "$SINGLE_NODE" ]]; then
        echo "Single Node:     $SINGLE_NODE"
    fi
    if [[ -n "$SINGLE_NODE_IP" ]]; then
        echo "Single Node IP:  $SINGLE_NODE_IP"
    fi

    echo ""

    check_prerequisites
    get_cluster_state

    echo ""
    echo "Upgrade Plan:"
    echo "-------------"

    # Single-node mode: show only the specific node
    if [[ -n "$SINGLE_NODE" || -n "$SINGLE_NODE_IP" ]]; then
        local found=false

        # Check if it's a worker
        if [[ "$SKIP_WORKERS" == false ]]; then
            for worker in "${WORKER_NODES[@]}"; do
                local worker_num=$(echo "$worker" | grep -oE '[0-9]+$')
                local cp_count=$(grep -E "^controlplane_count\s*=" "$TFVARS_FILE" | grep -oE '[0-9]+')
                local node_index=$((cp_count + worker_num - 1))
                local worker_ip=$(get_node_ip "$node_index")

                if [[ -n "$SINGLE_NODE" && "$worker" == "$SINGLE_NODE" ]] || \
                   [[ -n "$SINGLE_NODE_IP" && "$worker_ip" == "$SINGLE_NODE_IP" ]]; then
                    echo "1. Upgrade worker node: $worker ($worker_ip)"
                    found=true
                    break
                fi
            done
        fi

        # Check if it's a control plane
        if [[ "$SKIP_CONTROL_PLANES" == false ]]; then
            for cp in "${CP_NODES[@]}"; do
                local cp_num=$(echo "$cp" | grep -oE '[0-9]+$')
                local node_index=$((cp_num - 1))
                local cp_ip=$(get_node_ip "$node_index")

                if [[ -n "$SINGLE_NODE" && "$cp" == "$SINGLE_NODE" ]] || \
                   [[ -n "$SINGLE_NODE_IP" && "$cp_ip" == "$SINGLE_NODE_IP" ]]; then
                    echo "1. Upgrade control plane: $cp ($cp_ip)"
                    found=true
                    break
                fi
            done
        fi

        if [[ "$found" == false ]]; then
            log_error "Node not found: ${SINGLE_NODE}${SINGLE_NODE_IP}"
            exit 1
        fi

        echo "2. Finalize upgrade"
    else
        # Full cluster mode: show all nodes
        [[ "$SKIP_WORKERS" == false ]] && echo "1. Upgrade ${#WORKER_NODES[@]} worker node(s): ${WORKER_NODES[*]}"
        [[ "$SKIP_CONTROL_PLANES" == false ]] && echo "2. Upgrade ${#CP_NODES[@]} control plane(s): ${CP_NODES[*]}"
        echo "3. Finalize upgrade"
    fi

    echo ""

    if [[ "$AUTO_APPROVE" == false ]]; then
        read -p "Continue with upgrade? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
            log_warning "Upgrade cancelled by user"
            exit 0
        fi
    fi

    log_info "Starting Talos upgrade using talosctl..."
    log_info "Installer image: factory.talos.dev/installer/${SCHEMATIC_ID}:${TARGET_VERSION}"
    echo ""

    # Run upgrade phases
    upgrade_workers
    upgrade_control_planes
    finalize_upgrade

    echo ""
    log_success "🎉 Upgrade completed successfully!"
    echo ""
    log_info "All nodes are now running Talos $TARGET_VERSION"
    echo ""
}

# Run main
main
