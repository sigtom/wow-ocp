# Runbook 001: LVM Operator Deadlock Recovery

**Frequency:** Rare (Post-failure initialization attempts)
**Impact:** Critical - Prevents LVM storage provisioning cluster-wide
**Last Occurred:** 2025-12-31
**MTTR:** 30-45 minutes

---

## Symptoms

- `LVMCluster` resource stuck in error state
- `vg-manager` pods in `CrashLoopBackOff` or `Error` state
- New PVCs with `storageClassName: lvms-vg1` stuck in `Pending`
- Operator logs show: `thin pool already exists` or `device in use`

**Quick Check:**
```bash
oc get lvmcluster -n openshift-storage
oc get pods -n openshift-storage | grep vg-manager
```

---

## Root Cause

**Technical Explanation:**
When LVM operator initialization fails (power loss, operator crash, MCE deadlock), it leaves orphaned LVM metadata on nodes. The operator cannot automatically clean this up because it uses declarative reconciliation - it expects a clean slate but finds existing volume groups/thin pools that don't match the desired state.

**Why It Happens:**
1. Previous LVM provisioning attempt failed mid-creation
2. Operator left stale thin pools (`/dev/mapper/vg1-thin-pool`)
3. MCE (Multi-Cluster Engine) or other operators created conflicting LVM structures
4. Node crashed during VG initialization

---

## Diagnosis Steps

### 1. Check LVMCluster Status
```bash
oc get lvmcluster -n openshift-storage -o yaml
```

**Look for:**
- `status.conditions` showing errors
- `status.deviceClassStatuses` with failed states

### 2. Check vg-manager Logs
```bash
oc logs -n openshift-storage -l app.kubernetes.io/component=vg-manager --tail=100
```

**Common Error Patterns:**
- `thin pool "vg1-thin-pool" already exists`
- `device /dev/disk/by-path/XXX is already part of a volume group`
- `failed to create volume group: device in use`

### 3. Verify Node-Level LVM State
```bash
# Choose the problematic node from vg-manager logs
oc debug node/<node-name>

# Inside debug pod
chroot /host

# List volume groups (should be empty or show stale "vg1")
vgs

# List logical volumes (may show orphaned thin pools)
lvs

# List physical volumes
pvs
```

**Expected Output (Clean State):**
```
# vgs
  No volume groups found

# lvs
  No volume groups found
```

**Problem Output (Deadlock):**
```
# vgs
  VG  #PV #LV #SN Attr   VSize   VFree
  vg1   1   1   0 wz--n- 447.13g 447.13g

# lvs
  LV        VG  Attr       LSize   Pool Origin Data%  Meta%
  thin-pool vg1 twi-a-tz-- 447.13g             0.00   0.00
```

---

## Resolution

### Step 1: Backup Current LVMCluster Manifest
```bash
oc get lvmcluster -n openshift-storage -o yaml > /tmp/lvmcluster-backup.yaml
```

### Step 2: Delete LVMCluster Resource (Operator Will Recreate)
```bash
oc delete lvmcluster -n openshift-storage <lvmcluster-name>
```

**⚠️ WARNING:** This does NOT delete data on existing PVCs. It only removes the CRD instance.

### Step 3: Clean LVM Metadata on Affected Nodes

**For EACH node showing the issue:**

```bash
# Start debug session
oc debug node/<node-name>
chroot /host

# Remove thin pool first
lvremove /dev/vg1/thin-pool
# Answer 'y' to confirm

# Remove volume group
vgremove vg1
# Answer 'y' to confirm

# Remove physical volume (optional, operator will reinitialize)
pvremove /dev/disk/by-path/<disk-identifier>
# Answer 'y' to confirm

# Exit debug pod
exit
exit
```

### Step 4: Wait for Operator Reconciliation

The LVMS operator will automatically detect the deletion and recreate the `LVMCluster` from the manifest in Git (via ArgoCD).

```bash
# Watch for recreation
oc get lvmcluster -n openshift-storage -w

# Should eventually show:
# NAME          STATUS   AGE
# lvmcluster    Ready    2m
```

### Step 5: Verify Volume Group Initialization

```bash
# Check all nodes
for node in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do
  echo "=== $node ==="
  oc debug $node -- chroot /host vgs
done
```

**Expected Output (Success):**
```
=== node/wow-ocp-node2 ===
  VG  #PV #LV #SN Attr   VSize   VFree
  vg1   1   0   0 wz--n- 447.13g 447.13g
```

### Step 6: Test PVC Creation

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-lvm-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: lvms-vg1
EOF

# Verify binding
oc get pvc test-lvm-pvc -n default -w
# Should show: Bound

# Cleanup
oc delete pvc test-lvm-pvc -n default
```

---

## Prevention

### 1. Use Hardware-Specific Device Paths
**BAD:**
```yaml
deviceSelector:
  paths:
    - /dev/sdb
```

**GOOD:**
```yaml
deviceSelector:
  paths:
    - /dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:1:0
  optionalPaths:
    - /dev/disk/by-path/pci-0000:03:00.0-scsi-0:0:1:0  # If blade hot-swapped
```

### 2. Monitor LVM Operator Health

Add to your monitoring stack:
```yaml
apiVersion: v1
kind: PrometheusRule
metadata:
  name: lvm-operator-alerts
  namespace: openshift-storage
spec:
  groups:
    - name: lvm-operator
      rules:
        - alert: LVMVGManagerCrashLoop
          expr: |
            rate(kube_pod_container_status_restarts_total{
              namespace="openshift-storage",
              container="vg-manager"
            }[15m]) > 0
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "LVM VG Manager in CrashLoopBackOff"
            description: "VG Manager pod {{ $labels.pod }} has restarted {{ $value }} times in 15m"
```

### 3. Document Device Topology Changes

Whenever blades are hot-swapped or disks replaced:
1. Update `infrastructure/storage/lvms/base/lvmcluster.yaml` with new `by-path` IDs
2. Commit to Git with description of hardware change
3. Verify ArgoCD sync completes without errors

---

## Rollback Plan

If LVM cleanup fails or causes instability:

### Option 1: Revert to Last Known Good State
```bash
# Apply backed-up manifest
oc apply -f /tmp/lvmcluster-backup.yaml
```

### Option 2: Disable LVM Operator (Emergency)
```bash
# Scale down operator
oc scale deployment lvms-operator -n openshift-storage --replicas=0

# Delete all LVMCluster instances
oc delete lvmcluster --all -n openshift-storage
```

**⚠️ Impact:** All LVM-backed PVCs will become unusable until operator is restored.

---

## Related Issues

- **Issue:** Prometheus storage exhaustion (used LVM)
- **Runbook:** [002-prometheus-storage-expansion.md](002-prometheus-storage-expansion.md)
- **Documentation:** `infrastructure/storage/lvms/base/`

---

## Lessons Learned (2025-12-31)

1. **Never use generic device paths** (`/dev/sdb`) - they change on reboot or hardware swap
2. **LVM operator cannot self-heal** from stale metadata - requires manual intervention
3. **MCE operator interactions** - Check for conflicting LVM usage from other operators
4. **Test LVM changes in Proxmox first** - Easier to snapshot/rollback VMs than bare metal

---

## Verification Checklist

- [ ] `oc get lvmcluster -n openshift-storage` shows `Ready`
- [ ] All `vg-manager` pods are `Running` (1/1)
- [ ] `vgs` shows Volume Groups on all worker nodes
- [ ] Test PVC creation/binding succeeds
- [ ] ArgoCD shows `lvms` application as `Synced` and `Healthy`
- [ ] No alerts firing in Prometheus for LVM components

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Owner:** SRE Team
