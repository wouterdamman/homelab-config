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
TFVARS_FILE="../proxmox.auto.tfvars"
TALOSCONFIG="$(pwd)/../output/talos-config.yaml"
KUBECONFIG="$(pwd)/../output/kube-config.yaml"

# Default wait times (in seconds)
WORKER_WAIT_TIME=300    # 5 minutes between workers
CP_WAIT_TIME=600        # 10 minutes between control planes

# Parse command line arguments
CURRENT_VERSION=""
TARGET_VERSION=""
DRY_RUN=false
SKIP_WORKERS=false
SKIP_CONTROL_PLANES=false
AUTO_APPROVE=false

usage() {
    echo "Usage: $0 --current <version> --target <version> [options]"
    echo ""
    echo "Options:"
    echo "  --current <version>       Current Talos version (e.g., v1.11.6)"
    echo "  --target <version>        Target Talos version (e.g., v1.12.0)"
    echo "  --dry-run                 Show what would be done without making changes"
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
    CLUSTER_CIDR=$(grep -E "^cluster_cidr\s*=" "$TFVARS_FILE" | sed 's/.*=\s*"\(.*\)".*/\1/')
    IP_OFFSET=$(grep -E "^ip_offset\s*=" "$TFVARS_FILE" | grep -oE '[0-9]+')
    ENV=$(grep -E "^env\s*=" "$TFVARS_FILE" | sed 's/.*=\s*"\(.*\)".*/\1/')

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

# Update tfvars file
update_tfvars() {
    local field="$1"
    local value="$2"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would update $field to: $value"
        return
    fi

    # Use sed to update the tfvars file
    case "$field" in
        "talos_version")
            sed -i.bak "s|^talos_version\s*=.*|talos_version = \"$value\"|" "$TFVARS_FILE"
            ;;
        "talos_update_version")
            # Check if line exists
            if grep -q "^talos_update_version" "$TFVARS_FILE"; then
                if [[ "$value" == "null" ]]; then
                    sed -i.bak "/^talos_update_version/d" "$TFVARS_FILE"
                else
                    sed -i.bak "s|^talos_update_version\s*=.*|talos_update_version = \"$value\"|" "$TFVARS_FILE"
                fi
            else
                # Add after talos_version
                sed -i.bak "/^talos_version/a\\
talos_update_version = \"$value\"" "$TFVARS_FILE"
            fi
            ;;
        "nodes_to_upgrade")
            # Check if line exists
            if grep -q "^nodes_to_upgrade" "$TFVARS_FILE"; then
                sed -i.bak "s|^nodes_to_upgrade\s*=.*|nodes_to_upgrade = $value|" "$TFVARS_FILE"
            else
                # Add at end of file
                echo "nodes_to_upgrade = $value" >> "$TFVARS_FILE"
            fi
            ;;
    esac
}

# Apply terraform changes
apply_terraform() {
    local description="$1"

    log_info "Applying: $description"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would run: tofu plan"
        return
    fi

    cd "$(dirname "$TFVARS_FILE")"

    # Run plan
    if ! tofu plan -out=tfplan; then
        log_error "Terraform plan failed"
        exit 1
    fi

    # Apply
    if ! tofu apply tfplan; then
        log_error "Terraform apply failed"
        rm -f tfplan
        exit 1
    fi

    rm -f tfplan
    log_success "Applied successfully"
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

    # Check critical pods
    local critical_pods=$(kubectl get pods -n kube-system --no-headers | grep -E "(cilium|etcd)" | grep -v "Running" | wc -l)
    if [[ $critical_pods -gt 0 ]]; then
        log_error "$critical_pods critical pod(s) are not Running"
        return 1
    fi

    log_success "Cluster is healthy"
    return 0
}

# Upgrade workers
upgrade_workers() {
    if [[ "$SKIP_WORKERS" == true ]]; then
        log_warning "Skipping worker upgrades"
        return
    fi

    log_info "Starting worker node upgrades..."

    local upgraded_nodes=()

    for worker in "${WORKER_NODES[@]}"; do
        log_info "Upgrading worker: $worker"

        # Add to upgrade list
        upgraded_nodes+=("\"$worker\"")
        local nodes_json="[$(IFS=,; echo "${upgraded_nodes[*]}")]"

        update_tfvars "nodes_to_upgrade" "$nodes_json"
        apply_terraform "Upgrade $worker"

        # Calculate IP for this worker (CPs come first, then workers)
        local worker_num=$(echo "$worker" | grep -oE '[0-9]+$')
        local cp_count=$(grep -E "^controlplane_count\s*=" "$TFVARS_FILE" | grep -oE '[0-9]+')
        local node_index=$((cp_count + worker_num - 1))
        local worker_ip=$(get_node_ip "$node_index")

        # Wait for node
        if ! wait_for_node "$worker" "$worker_ip" "$WORKER_WAIT_TIME"; then
            log_error "Worker $worker upgrade failed or timed out"
            exit 1
        fi

        # Verify health
        if ! verify_cluster_health; then
            log_error "Cluster health check failed after upgrading $worker"
            exit 1
        fi

        log_success "Worker $worker upgraded successfully"

        # Wait before next worker (except for the last one)
        if [[ "$worker" != "${WORKER_NODES[-1]}" ]]; then
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

    # Get already upgraded nodes (workers)
    local upgraded_nodes=()
    for worker in "${WORKER_NODES[@]}"; do
        upgraded_nodes+=("\"$worker\"")
    done

    for cp in "${CP_NODES[@]}"; do
        log_info "Upgrading control plane: $cp"

        # Add to upgrade list
        upgraded_nodes+=("\"$cp\"")
        local nodes_json="[$(IFS=,; echo "${upgraded_nodes[*]}")]"

        update_tfvars "nodes_to_upgrade" "$nodes_json"
        apply_terraform "Upgrade $cp"

        # Calculate IP for this CP (CPs are indexed from 0)
        local cp_num=$(echo "$cp" | grep -oE '[0-9]+$')
        local node_index=$((cp_num - 1))
        local cp_ip=$(get_node_ip "$node_index")

        # Wait for node
        if ! wait_for_node "$cp" "$cp_ip" "$CP_WAIT_TIME"; then
            log_error "Control plane $cp upgrade failed or timed out"
            exit 1
        fi

        # Extra verification for CPs - check etcd health
        if [[ "$DRY_RUN" == false ]]; then
            log_info "Checking etcd health..."
            export TALOSCONFIG
            if ! talosctl --nodes "$cp_ip" service etcd status 2>/dev/null | grep -q "STATE.*Running"; then
                log_warning "etcd may not be healthy on $cp, but continuing..."
            fi
        fi

        # Verify cluster health
        if ! verify_cluster_health; then
            log_error "Cluster health check failed after upgrading $cp"
            exit 1
        fi

        log_success "Control plane $cp upgraded successfully"

        # Wait before next CP (except for the last one)
        if [[ "$cp" != "${CP_NODES[-1]}" ]]; then
            log_info "Waiting ${CP_WAIT_TIME}s before next control plane..."
            [[ "$DRY_RUN" == false ]] && sleep "$CP_WAIT_TIME"
        fi
    done

    log_success "All control planes upgraded successfully"
}

# Finalize upgrade
finalize_upgrade() {
    log_info "Finalizing upgrade..."

    # Update base version to target
    update_tfvars "talos_version" "$TARGET_VERSION"
    update_tfvars "talos_update_version" "null"
    update_tfvars "nodes_to_upgrade" "[]"

    apply_terraform "Finalize upgrade to $TARGET_VERSION"

    log_success "Upgrade finalized - all nodes now on $TARGET_VERSION"
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
    echo ""

    check_prerequisites
    get_cluster_state

    echo ""
    echo "Upgrade Plan:"
    echo "-------------"
    [[ "$SKIP_WORKERS" == false ]] && echo "1. Upgrade ${#WORKER_NODES[@]} worker node(s): ${WORKER_NODES[*]}"
    [[ "$SKIP_CONTROL_PLANES" == false ]] && echo "2. Upgrade ${#CP_NODES[@]} control plane(s): ${CP_NODES[*]}"
    echo "3. Finalize upgrade"
    echo ""

    if [[ "$AUTO_APPROVE" == false ]]; then
        read -p "Continue with upgrade? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
            log_warning "Upgrade cancelled by user"
            exit 0
        fi
    fi

    # Set upgrade version in tfvars
    log_info "Configuring upgrade to $TARGET_VERSION..."
    update_tfvars "talos_update_version" "$TARGET_VERSION"
    update_tfvars "nodes_to_upgrade" "[]"

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
