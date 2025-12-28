#!/bin/bash
# Test disaster recovery by creating a test PVC, backing it up, and restoring it
# Usage: ./scripts/test-restore.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_NAMESPACE="longhorn-dr-test"
TEST_PVC_NAME="dr-test-pvc"
TEST_POD_NAME="dr-test-pod"
TEST_DATA="Longhorn DR Test - $(date +%s)"
TEST_MOUNT_PATH="/data"

echo -e "${GREEN}🧪 Starting Longhorn Disaster Recovery Test${NC}"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${BLUE}🧹 Cleaning up test resources...${NC}"
    kubectl delete namespace $TEST_NAMESPACE --ignore-not-found=true --wait=false
    echo -e "${GREEN}✓ Cleanup initiated${NC}"
}

trap cleanup EXIT

# Step 1: Create test namespace
echo -e "${BLUE}[1/8] Creating test namespace...${NC}"
kubectl create namespace $TEST_NAMESPACE || true
echo -e "${GREEN}✓ Namespace created${NC}"
echo ""

# Step 2: Create test PVC
echo -e "${BLUE}[2/8] Creating test PVC...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TEST_PVC_NAME
  namespace: $TEST_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-standard
  resources:
    requests:
      storage: 1Gi
EOF

kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/$TEST_PVC_NAME -n $TEST_NAMESPACE --timeout=60s
echo -e "${GREEN}✓ PVC created and bound${NC}"
echo ""

# Step 3: Write test data to PVC
echo -e "${BLUE}[3/8] Writing test data to PVC...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $TEST_POD_NAME
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: writer
    image: busybox
    command:
      - /bin/sh
      - -c
      - |
        echo "$TEST_DATA" > $TEST_MOUNT_PATH/test-file.txt
        echo "File checksum: \$(md5sum $TEST_MOUNT_PATH/test-file.txt)"
        sleep 10
    volumeMounts:
    - name: data
      mountPath: $TEST_MOUNT_PATH
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: $TEST_PVC_NAME
  restartPolicy: Never
EOF

kubectl wait --for=condition=ready pod/$TEST_POD_NAME -n $TEST_NAMESPACE --timeout=60s
sleep 5
ORIGINAL_CHECKSUM=$(kubectl logs -n $TEST_NAMESPACE $TEST_POD_NAME | grep "File checksum:" | awk '{print $3}')
echo -e "${GREEN}✓ Test data written${NC}"
echo -e "  Original checksum: $ORIGINAL_CHECKSUM"
echo ""

# Step 4: Create snapshot
echo -e "${BLUE}[4/8] Creating volume snapshot...${NC}"
VOLUME_NAME=$(kubectl get pvc -n $TEST_NAMESPACE $TEST_PVC_NAME -o jsonpath='{.spec.volumeName}')
kubectl exec -n longhorn-system $(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}') -- \
  curl -X POST "http://localhost:9500/v1/volumes/$VOLUME_NAME?action=snapshotCreate" \
  -H "Content-Type: application/json" \
  -d '{"name":"dr-test-snapshot"}' > /dev/null 2>&1

sleep 5
echo -e "${GREEN}✓ Snapshot created${NC}"
echo ""

# Step 5: Create backup from snapshot
echo -e "${BLUE}[5/8] Creating backup to S3...${NC}"
kubectl exec -n longhorn-system $(kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[0].metadata.name}') -- \
  curl -X POST "http://localhost:9500/v1/volumes/$VOLUME_NAME?action=snapshotBackup" \
  -H "Content-Type: application/json" \
  -d '{"name":"dr-test-snapshot"}' > /dev/null 2>&1

echo -e "${YELLOW}  Waiting for backup to complete (this may take a minute)...${NC}"
sleep 30

# Wait for backup to complete
for i in {1..12}; do
    BACKUP_STATE=$(kubectl get backup -n longhorn-system -l longhornvolume=$VOLUME_NAME --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].status.state}' 2>/dev/null || echo "")
    if [ "$BACKUP_STATE" = "Completed" ]; then
        break
    fi
    echo -e "${YELLOW}  Backup state: $BACKUP_STATE... waiting${NC}"
    sleep 5
done

if [ "$BACKUP_STATE" != "Completed" ]; then
    echo -e "${RED}✗ Backup failed or timed out (state: $BACKUP_STATE)${NC}"
    exit 1
fi

BACKUP_NAME=$(kubectl get backup -n longhorn-system -l longhornvolume=$VOLUME_NAME --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
BACKUP_URL=$(kubectl get backup -n longhorn-system $BACKUP_NAME -o jsonpath='{.status.url}')
echo -e "${GREEN}✓ Backup completed${NC}"
echo -e "  Backup URL: $BACKUP_URL"
echo ""

# Step 6: Delete original PVC
echo -e "${BLUE}[6/8] Simulating disaster - deleting original PVC...${NC}"
kubectl delete pod -n $TEST_NAMESPACE $TEST_POD_NAME --wait=false
sleep 5
kubectl delete pvc -n $TEST_NAMESPACE $TEST_PVC_NAME
echo -e "${GREEN}✓ Original PVC deleted${NC}"
echo ""

# Step 7: Restore from backup
echo -e "${BLUE}[7/8] Restoring PVC from S3 backup...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${TEST_PVC_NAME}-restored
  namespace: $TEST_NAMESPACE
  annotations:
    longhorn.io/volume-from-backup: "$BACKUP_URL"
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-standard
  resources:
    requests:
      storage: 1Gi
EOF

kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/${TEST_PVC_NAME}-restored -n $TEST_NAMESPACE --timeout=120s
echo -e "${GREEN}✓ PVC restored from backup${NC}"
echo ""

# Step 8: Verify restored data
echo -e "${BLUE}[8/8] Verifying restored data...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD_NAME}-verify
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: reader
    image: busybox
    command:
      - /bin/sh
      - -c
      - |
        if [ ! -f $TEST_MOUNT_PATH/test-file.txt ]; then
          echo "ERROR: Test file not found!"
          exit 1
        fi
        echo "Restored data: \$(cat $TEST_MOUNT_PATH/test-file.txt)"
        echo "File checksum: \$(md5sum $TEST_MOUNT_PATH/test-file.txt)"
        sleep 5
    volumeMounts:
    - name: data
      mountPath: $TEST_MOUNT_PATH
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${TEST_PVC_NAME}-restored
  restartPolicy: Never
EOF

kubectl wait --for=condition=ready pod/${TEST_POD_NAME}-verify -n $TEST_NAMESPACE --timeout=60s
sleep 5

RESTORED_DATA=$(kubectl logs -n $TEST_NAMESPACE ${TEST_POD_NAME}-verify | grep "Restored data:" | cut -d: -f2-)
RESTORED_CHECKSUM=$(kubectl logs -n $TEST_NAMESPACE ${TEST_POD_NAME}-verify | grep "File checksum:" | awk '{print $3}')

echo -e "${GREEN}✓ Data verification complete${NC}"
echo ""

# Results
echo "═══════════════════════════════════════════"
echo -e "${GREEN}DR Test Results:${NC}"
echo ""
echo "Original data:  $TEST_DATA"
echo "Restored data: $RESTORED_DATA"
echo ""
echo "Original checksum:  $ORIGINAL_CHECKSUM"
echo "Restored checksum:  $RESTORED_CHECKSUM"
echo ""

if [ "$ORIGINAL_CHECKSUM" = "$RESTORED_CHECKSUM" ]; then
    echo -e "${GREEN}✅ SUCCESS: Data integrity verified!${NC}"
    echo -e "${GREEN}✅ Disaster Recovery test PASSED${NC}"
    exit 0
else
    echo -e "${RED}❌ FAILED: Data checksums do not match!${NC}"
    echo -e "${RED}❌ Disaster Recovery test FAILED${NC}"
    exit 1
fi
