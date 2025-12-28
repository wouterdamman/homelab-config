#!/bin/bash
# Validate all Longhorn backups are successfully uploaded to S3
# Usage: ./scripts/validate-backups.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🔍 Validating Longhorn backups...${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl is not installed${NC}"
    exit 1
fi

# Get all volumes
VOLUMES=$(kubectl get volume -n longhorn-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -z "$VOLUMES" ]; then
    echo -e "${YELLOW}⚠️  No Longhorn volumes found${NC}"
    exit 0
fi

TOTAL_VOLUMES=0
VOLUMES_WITH_BACKUPS=0
VOLUMES_WITHOUT_BACKUPS=0
FAILED_BACKUPS=0

for volume in $VOLUMES; do
    TOTAL_VOLUMES=$((TOTAL_VOLUMES + 1))
    echo -e "${NC}Checking volume: ${YELLOW}$volume${NC}"

    # Get all backups for this volume
    BACKUPS=$(kubectl get backup -n longhorn-system -l longhornvolume=$volume -o json 2>/dev/null)
    BACKUP_COUNT=$(echo "$BACKUPS" | jq '.items | length')

    if [ "$BACKUP_COUNT" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠️  No backups found${NC}"
        VOLUMES_WITHOUT_BACKUPS=$((VOLUMES_WITHOUT_BACKUPS + 1))
        continue
    fi

    # Get latest backup
    LATEST_BACKUP=$(echo "$BACKUPS" | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')
    LATEST_STATE=$(echo "$BACKUPS" | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .status.state // "Unknown"')
    LATEST_TIME=$(echo "$BACKUPS" | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.creationTimestamp')

    if [ "$LATEST_STATE" = "Completed" ]; then
        echo -e "  ${GREEN}✓${NC} Latest backup: $LATEST_BACKUP"
        echo -e "    State: ${GREEN}Completed${NC}"
        echo -e "    Time: $LATEST_TIME"
        echo -e "    Total backups: $BACKUP_COUNT"
        VOLUMES_WITH_BACKUPS=$((VOLUMES_WITH_BACKUPS + 1))
    else
        echo -e "  ${RED}✗${NC} Latest backup: $LATEST_BACKUP"
        echo -e "    State: ${RED}$LATEST_STATE${NC}"
        echo -e "    Time: $LATEST_TIME"
        FAILED_BACKUPS=$((FAILED_BACKUPS + 1))
    fi

    echo ""
done

# Summary
echo "═══════════════════════════════════════════"
echo -e "${GREEN}Summary:${NC}"
echo "  Total volumes: $TOTAL_VOLUMES"
echo -e "  Volumes with successful backups: ${GREEN}$VOLUMES_WITH_BACKUPS${NC}"
echo -e "  Volumes without backups: ${YELLOW}$VOLUMES_WITHOUT_BACKUPS${NC}"
echo -e "  Volumes with failed backups: ${RED}$FAILED_BACKUPS${NC}"

if [ $FAILED_BACKUPS -gt 0 ] || [ $VOLUMES_WITHOUT_BACKUPS -gt 0 ]; then
    echo ""
    echo -e "${RED}⚠️  Some volumes have backup issues!${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}✅ All volumes have successful backups${NC}"
    exit 0
fi
