# Longhorn Disaster Recovery Runbook

## Recovery Objectives

- **RTO (Recovery Time Objective)**: < 4 hours
- **RPO (Recovery Point Objective)**: < 1 hour
- **Backup Location**: `s3://homelab-prd/longhorn-backup/` (Hetzner Object Storage nbg1)

## Prerequisites

- Kubernetes cluster admin access (kubeconfig)
- Hetzner Object Storage access credentials
- 1Password access to KubernetesSecrets vault
- Tools: kubectl, 1Password CLI, ArgoCD CLI (optional)

---

# Disaster Recovery Scenarios

## Scenario 1: Single Volume Recovery

**When to use**: A single PVC is corrupted or accidentally deleted.

### Step 1: Identify the Volume

```bash
kubectl get pvc -A
kubectl get volume -n longhorn-system
```

### Step 2: Find Available Backups

```bash
# Access Longhorn UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# Navigate to: Backup > Select volume > View backups

# Or via CLI
kubectl get backup -n longhorn-system -l longhornvolume=<volume-name>
```

### Step 3: Restore from Backup

**Option A: Restore to New PVC (Recommended)**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
  namespace: default
  annotations:
    longhorn.io/volume-from-backup: "s3://homelab-prd@nbg1/longhorn-backup/backupstore/<backup-name>"
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-standard
  resources:
    requests:
      storage: 10Gi
```

**Option B: Restore to Existing PVC**
1. Scale down application using the PVC
2. Delete the PVC (but NOT the PV)
3. Create new PVC with backup annotation
4. Scale up application

### Step 4: Verify Restoration

```bash
kubectl get pvc -n <namespace> <pvc-name>

# Mount temporarily to verify data
kubectl run -it --rm debug --image=busybox --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"<pvc-name>"}}],"containers":[{"name":"debug","image":"busybox","command":["/bin/sh"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}]}}'
```

### Step 5: Resume Application

```bash
kubectl scale deployment/<name> -n <namespace> --replicas=1
kubectl get pods -n <namespace>
```

**Estimated Time**: 15-30 minutes

---

## Scenario 2: Full Cluster Disaster Recovery

**When to use**: Complete cluster failure, data center loss, or Longhorn system corruption.

### Step 1: Deploy Base Cluster

Follow the Cluster Deployment - Bootstrap procedure to deploy a fresh Talos cluster.

### Step 2: Deploy GitOps Stack

Follow the ArgoCD Bootstrap procedure to deploy ArgoCD and Longhorn.

```bash
# Wait for all Longhorn pods to be ready
kubectl wait --for=condition=ready pod -n longhorn-system -l app=longhorn-manager --timeout=300s
```

### Step 3: Verify S3 Backup Target

```bash
kubectl get setting -n longhorn-system backup-target -o yaml
# Expected: value: s3://homelab-prd@nbg1/longhorn-backup/
```

### Step 4: Discover Available Backups

```bash
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# Navigate to: Backup → Click "Sync Backups"
```

### Step 5: Restore All Critical Volumes

For each critical volume:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <original-pvc-name>
  namespace: <original-namespace>
  annotations:
    longhorn.io/volume-from-backup: "s3://homelab-prd@nbg1/longhorn-backup/backupstore/<backup-name>"
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-standard
  resources:
    requests:
      storage: <original-size>
```

### Step 6: Restore ArgoCD Applications

```bash
# Force sync all applications
argocd app sync --all
```

### Step 7: Verify All Services

```bash
kubectl get pods -A | grep -v Running
kubectl get pvc -A | grep -v Bound
kubectl get applications -n argocd
```

**Estimated Time**: 2-4 hours (depending on data size)

---

## Scenario 3: Rollback After Failed Update

**When to use**: Application update corrupted data, need to revert to previous state.

### Step 1: Identify Snapshot Before Update

```bash
kubectl get volumesnapshot -n <namespace>
# Or via Longhorn UI: Volume > Snapshots
```

### Step 2: Revert to Snapshot

In Longhorn UI:
1. Select volume → "Snapshot" tab
2. Find snapshot before the update
3. Click "Revert"

### Step 3: Restart Application

```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

**Estimated Time**: 5-15 minutes

---

# Automated Scripts

## DR Test Script

Location: `resources/gitops-config/operators/longhorn/scripts/test-restore.sh`

**Test Flow:**
1. Creates test namespace and PVC
2. Writes test data with MD5 checksum
3. Creates Longhorn Snapshot (via CRD)
4. Creates Backup to S3 (via CRD)
5. Deletes original PVC (simulates disaster)
6. Restores PVC from S3 backup
7. Verifies data integrity via checksum comparison
8. Cleans up all test resources

**Example Output:**

```
🧪 Starting Longhorn Disaster Recovery Test
[1/8] Creating test namespace... ✓
[2/8] Creating test PVC... ✓
[3/8] Writing test data to PVC... ✓
  Original checksum: 684aa4e9ada6a1d5e2567d5bc32c5f2b
[4/8] Creating volume snapshot... ✓
[5/8] Creating backup to S3 from snapshot... ✓
[6/8] Simulating disaster - deleting original PVC... ✓
[7/8] Restoring PVC from S3 backup... ✓
[8/8] Verifying restored data... ✓
  Restored checksum: 684aa4e9ada6a1d5e2567d5bc32c5f2b

═══════════════════════════════════════════
✅ DISASTER RECOVERY TEST PASSED
═══════════════════════════════════════════
```

## Backup Validation Script

Location: `resources/gitops-config/operators/longhorn/scripts/validate-backups.sh`

**Features:**
- Checks all Longhorn volumes for backups
- Shows latest backup state and timestamp
- Color-coded output (green = success, yellow = warning, red = error)
- Exit code 1 if any volumes have backup issues

---

# Testing Procedures

## Monthly DR Test

**Schedule**: First Sunday of each month at 10:00

### Test Checklist

- [ ] Backup creation successful
- [ ] Backup uploaded to S3
- [ ] Restore PVC created
- [ ] Data integrity verified (checksum match)
- [ ] Application can mount and use restored volume
- [ ] RTO < 30 minutes for single volume
- [ ] Test documented

---

# Related Documentation

- [Longhorn Configuration](longhorn.md)
- [Longhorn Production-Grade Plan](longhorn-production-plan.md)
- [Cluster Deployment Bootstrap](../bootstrap/cluster-deployment-bootstrap.md)
