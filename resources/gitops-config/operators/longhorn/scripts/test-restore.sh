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
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
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
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      runAsNonRoot: true
      runAsUser: 1000
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

# Step 4: Create snapshot using Longhorn CRD
echo -e "${BLUE}[4/8] Creating volume snapshot...${NC}"
VOLUME_NAME=$(kubectl get pvc -n $TEST_NAMESPACE $TEST_PVC_NAME -o jsonpath='{.spec.volumeName}')

# Create a snapshot directly on the volume
echo -e "${YELLOW}  Creating snapshot on volume $VOLUME_NAME...${NC}"
SNAPSHOT_NAME="dr-test-$(date +%s)"

cat <<EOF | kubectl apply --warnings-as-errors=false -f -
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: $SNAPSHOT_NAME
  namespace: longhorn-system
  labels:
    longhornvolume: $VOLUME_NAME
spec:
  volume: $VOLUME_NAME
  createSnapshot: true
EOF

# Wait for snapshot to be ready
echo -e "${YELLOW}  Waiting for snapshot to be created...${NC}"
for i in {1..12}; do
    SNAPSHOT_READY=$(kubectl get snapshot -n longhorn-system $SNAPSHOT_NAME -o jsonpath='{.status.readyToUse}' 2>/dev/null || echo "false")
    if [ "$SNAPSHOT_READY" = "true" ]; then
        break
    fi
    echo -e "${YELLOW}  Snapshot not ready yet... waiting (attempt $i/12)${NC}"
    sleep 5
done

if [ "$SNAPSHOT_READY" != "true" ]; then
    echo -e "${RED}✗ Snapshot creation failed or timed out${NC}"
    echo -e "${YELLOW}Debug: kubectl get snapshot -n longhorn-system $SNAPSHOT_NAME -o yaml${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Snapshot created${NC}"
echo ""

# Step 5: Create backup from snapshot
echo -e "${BLUE}[5/8] Creating backup to S3 from snapshot...${NC}"

# Trigger backup by creating a Backup CRD
BACKUP_NAME="backup-$SNAPSHOT_NAME"
cat <<EOF | kubectl apply --warnings-as-errors=false -f -
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: $BACKUP_NAME
  namespace: longhorn-system
  labels:
    longhornvolume: $VOLUME_NAME
    snapshot: $SNAPSHOT_NAME
spec:
  snapshotName: $SNAPSHOT_NAME
  labels:
    test: dr-restore
EOF

echo -e "${YELLOW}  Waiting for backup to complete (this may take a minute)...${NC}"
sleep 10

# Wait for backup to complete
for i in {1..30}; do
    BACKUP_STATE=$(kubectl get backup -n longhorn-system $BACKUP_NAME -o jsonpath='{.status.state}' 2>/dev/null || echo "")
    if [ "$BACKUP_STATE" = "Completed" ]; then
        break
    elif [ "$BACKUP_STATE" = "Error" ]; then
        echo -e "${RED}✗ Backup failed with error state${NC}"
        kubectl get backup -n longhorn-system $BACKUP_NAME -o yaml
        exit 1
    fi
    echo -e "${YELLOW}  Backup state: $BACKUP_STATE... waiting (attempt $i/30)${NC}"
    sleep 5
done

if [ "$BACKUP_STATE" != "Completed" ]; then
    echo -e "${RED}✗ Backup failed or timed out (state: $BACKUP_STATE)${NC}"
    echo -e "${YELLOW}Debug: kubectl get backup -n longhorn-system $BACKUP_NAME -o yaml${NC}"
    exit 1
fi

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
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
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
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      runAsNonRoot: true
      runAsUser: 1000
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
