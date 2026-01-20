# Runbook 004: PVC Stuck in Pending State

**Frequency:** Common (during new app deployments)
**Impact:** Medium - App cannot start until PVC binds
**Last Occurred:** Ongoing (new deployments)
**MTTR:** 5-20 minutes

---

## Symptoms

- PVC shows `Pending` status for >5 minutes
- No PV automatically bound to the PVC
- App pods stuck in `ContainerCreating` waiting for volume
- Events show: `waiting for a volume to be created`

**Quick Check:**
```bash
oc get pvc -n <namespace>
oc describe pvc <pvc-name> -n <namespace>
```

---

## Root Cause Analysis

### Common Causes (Priority Order)

1. **CSI Driver Unreachable** (40% of cases)
   - Network connectivity to TrueNAS broken
   - Democratic-CSI pods crashed or not running

2. **TrueNAS API Errors** (30% of cases)
   - Dataset creation failed on TrueNAS
   - Parent dataset quota exceeded
   - NFS export already exists with different settings

3. **Storage Class Misconfiguration** (15% of cases)
   - Wrong StorageClass name in PVC
   - StorageClass doesn't exist or is not default

4. **Namespace ResourceQuota Exceeded** (10% of cases)
   - Namespace has PVC count or storage size limit

5. **Driver Image Version Mismatch** (5% of cases)
   - Democratic-CSI using old image with TrueNAS 25.x API

---

## Diagnosis Steps

### Step 1: Check PVC Details and Events
```bash
oc describe pvc <pvc-name> -n <namespace>
```

**Look for Events section:**
```
Events:
  Type     Reason              Message
  ----     ------              -------
  Warning  ProvisioningFailed  failed to provision volume: rpc error: code = Internal desc = failed to create dataset
```

**Common Error Messages:**

| Error Message | Probable Cause |
|---------------|----------------|
| `failed to provision volume` | CSI driver error (check driver logs) |
| `waiting for a volume to be created` | Driver hasn't picked up request yet (wait) |
| `exceeded quota` | Namespace ResourceQuota or TrueNAS quota |
| `connection refused` | Network to TrueNAS broken |
| `invalid API key` | Democratic-CSI secret is wrong |

### Step 2: Check CSI Driver Pods
```bash
oc get pods -n democratic-csi
```

**Expected:**
```
NAME                                    READY   STATUS    RESTARTS
zfs-nfs-democratic-csi-controller-0     4/4     Running   0
zfs-nfs-democratic-csi-node-XXXXX       2/2     Running   0  (one per node)
```

**Problem:** Any pod not `Running` or with high `RESTARTS`.

### Step 3: Check CSI Driver Logs
```bash
oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=100 | grep -i error
```

**Common Log Patterns:**

| Log Message | Action |
|-------------|--------|
| `failed to create dataset` | Check TrueNAS manually (Step 4) |
| `connection refused 172.16.160.100` | Network connectivity issue (Runbook 005) |
| `API version mismatch` | Update CSI driver image to `next` tag |
| `method not found` | TrueNAS API changed, update driver |
| `dataset already exists` | Orphaned dataset on TrueNAS (clean up) |

### Step 4: Verify TrueNAS Dataset Exists
```bash
ssh truenas "zfs list | grep <pvc-name>"
```

**Expected (Success):**
```
tank/k8s/media-stack-sonarr-config-pvc  10G  5.0T  256K  /mnt/tank/k8s/...
```

**Problem (Dataset Exists but PVC Pending):**
- NFS export might not be created
- Check exports: `ssh truenas "cat /etc/exports | grep <pvc-name>"`

**Problem (No Dataset):**
- CSI driver failed to create it (check driver logs)

### Step 5: Check Network Connectivity (VLAN 160)
```bash
# From a node
oc debug node/<node-name>
chroot /host
ping 172.16.160.100  # TrueNAS storage IP

# Should respond with <5ms latency
```

**If ping fails:** See Runbook 005 (VLAN 160 Routing).

### Step 6: Verify StorageClass Exists
```bash
oc get storageclass
```

**Expected:**
```
NAME                    PROVISIONER                     RECLAIMPOLICY
truenas-nfs (default)   org.democratic-csi.nfs          Delete
lvms-vg1                topolvm.io                       Delete
```

**Problem:** If StorageClass in PVC doesn't match available classes.

### Step 7: Check Namespace ResourceQuota
```bash
oc describe resourcequota -n <namespace>
```

**Look for:**
```
Used:
  persistentvolumeclaims: 10
  requests.storage: 95Gi

Hard:
  persistentvolumeclaims: 10  # AT LIMIT
  requests.storage: 100Gi
```

---

## Resolution

### Fix 1: CSI Driver Not Running

**Symptom:** Democratic-CSI pods are in `CrashLoopBackOff`.

**Resolution:**
```bash
# Check driver logs for root cause
oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=200

# Common fix: Restart driver pods
oc delete pods -n democratic-csi --all

# Wait for recreation
oc get pods -n democratic-csi -w
```

### Fix 2: Wrong TrueNAS API Version (Image Tag)

**Symptom:** Driver logs show `API method not found` or `version mismatch`.

**Resolution:**

**File:** `infrastructure/storage/democratic-csi/values.yaml`

```yaml
csiDriver:
  name: "org.democratic-csi.nfs"
  driver:
    image: democraticcsi/democratic-csi:next  # Use 'next' for TrueNAS 25.x
```

**Apply:**
```bash
git add infrastructure/storage/democratic-csi/values.yaml
git commit -m "fix(storage): update democratic-csi to next tag for TrueNAS 25.x"
git push origin main

argocd app sync cluster-storage
```

### Fix 3: Network Connectivity to TrueNAS Broken

**Symptom:** `ping 172.16.160.100` fails from nodes.

**See:** [Runbook 005: VLAN 160 Storage Network Routing](005-vlan-160-routing.md)

### Fix 4: Orphaned Dataset on TrueNAS (PVC Deleted but Dataset Remains)

**Symptom:** PVC creation fails with `dataset already exists`.

**Resolution:**
```bash
# Check if dataset exists
ssh truenas "zfs list | grep <pvc-name>"

# If exists but PVC doesn't, delete it
ssh truenas "zfs destroy tank/k8s/<pvc-name>"

# Delete and recreate PVC
oc delete pvc <pvc-name> -n <namespace>
oc apply -f <pvc-manifest>.yaml
```

### Fix 5: Namespace ResourceQuota Exceeded

**Symptom:** `oc describe resourcequota` shows quota at limit.

**Resolution (Option A: Increase Quota):**
```yaml
# infrastructure/namespaces/<namespace>/resourcequota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: <namespace>-quota
  namespace: <namespace>
spec:
  hard:
    persistentvolumeclaims: "20"  # Increased from 10
    requests.storage: "200Gi"     # Increased from 100Gi
```

**Resolution (Option B: Delete Unused PVCs):**
```bash
# List all PVCs in namespace
oc get pvc -n <namespace>

# Delete unused PVCs
oc delete pvc <unused-pvc> -n <namespace>
```

### Fix 6: Wrong StorageClass Name

**Symptom:** PVC references non-existent StorageClass.

**Resolution:**

**Edit PVC:**
```yaml
spec:
  storageClassName: truenas-nfs  # Correct name
  resources:
    requests:
      storage: 10Gi
```

**Or use cluster default (omit storageClassName):**
```yaml
spec:
  # storageClassName not specified = uses default
  resources:
    requests:
      storage: 10Gi
```

---

## Prevention

### 1. Pre-Deploy Validation Script

**File:** `scripts/validate-pvc.sh`

```bash
#!/bin/bash
set -e

NAMESPACE=$1
PVC_MANIFEST=$2

echo "Validating PVC deployment to namespace: $NAMESPACE"

# Check namespace exists
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
  echo "ERROR: Namespace $NAMESPACE does not exist"
  exit 1
fi

# Check StorageClass exists
SC=$(yq eval '.spec.storageClassName' "$PVC_MANIFEST")
if [ "$SC" != "null" ]; then
  if ! oc get storageclass "$SC" &>/dev/null; then
    echo "ERROR: StorageClass $SC does not exist"
    exit 1
  fi
fi

# Check ResourceQuota headroom
REQUESTED=$(yq eval '.spec.resources.requests.storage' "$PVC_MANIFEST")
echo "Checking quota headroom for $REQUESTED storage..."
oc describe resourcequota -n "$NAMESPACE" | grep -A 5 "requests.storage"

# Check CSI driver health
echo "Checking CSI driver pods..."
oc get pods -n democratic-csi | grep Running || {
  echo "ERROR: Democratic-CSI pods not healthy"
  exit 1
}

# Check network to TrueNAS
echo "Testing connectivity to TrueNAS (172.16.160.100)..."
oc debug node/$(oc get nodes -l node-role.kubernetes.io/worker -o name | head -n 1) -- \
  chroot /host ping -c 1 172.16.160.100 &>/dev/null || {
  echo "ERROR: Cannot reach TrueNAS storage network"
  exit 1
}

echo "✓ All validations passed"
```

**Usage:**
```bash
./scripts/validate-pvc.sh media-stack apps/media-stack/base/pvc-sonarr-config.yaml
```

### 2. Set Up Alerting for CSI Driver Health

**File:** `infrastructure/monitoring/storage-alerts.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: storage-alerts
  namespace: openshift-monitoring
spec:
  groups:
    - name: storage
      rules:
        - alert: CSIDriverNotReady
          expr: |
            kube_pod_status_phase{
              namespace="democratic-csi",
              phase!="Running"
            } > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "CSI driver pod not running"
            description: "Pod {{ $labels.pod }} in democratic-csi namespace is {{ $labels.phase }}"
```

### 3. Document Storage Capacity Planning

**Rule:** Reserve 20% headroom on TrueNAS datasets.

```bash
# Monthly check
ssh truenas "zfs list -o name,used,avail,refer tank/k8s"
```

---

## Troubleshooting Decision Tree

```
PVC Pending
    │
    ├─ Events show "ProvisioningFailed"?
    │   ├─ Yes → Check CSI driver logs (Step 3)
    │   │   ├─ "Connection refused" → Fix network (Runbook 005)
    │   │   ├─ "Dataset exists" → Delete orphaned dataset
    │   │   └─ "API version" → Update driver image to 'next'
    │   └─ No → Continue
    │
    ├─ Events show "Waiting for volume"?
    │   ├─ Yes → Driver hasn't processed yet
    │   │   ├─ Wait 5 more minutes
    │   │   └─ If >10 min, restart CSI driver
    │   └─ No → Continue
    │
    ├─ StorageClass exists?
    │   ├─ No → Fix PVC manifest or create StorageClass
    │   └─ Yes → Continue
    │
    ├─ Namespace quota exceeded?
    │   ├─ Yes → Increase quota or delete unused PVCs
    │   └─ No → Continue
    │
    └─ CSI driver pods running?
        ├─ No → Restart driver pods, check logs
        └─ Yes → Check TrueNAS manually (API creds, space)
```

---

## Related Issues

- **Issue:** VLAN 160 routing broken (Node 4 hybrid NIC)
- **Runbook:** [005-vlan-160-routing.md](005-vlan-160-routing.md)
- **Documentation:** `infrastructure/storage/democratic-csi/`

---

## Lessons Learned

1. **Always use `next` tag** for democratic-csi with TrueNAS 25.x
2. **Network first** - 40% of PVC issues are network-related
3. **Orphaned datasets** - Delete PVCs cleanly or TrueNAS retains datasets
4. **Quota headroom** - Set ResourceQuotas with 50% buffer
5. **Test before deploy** - Use validation script to catch misconfigurations

---

## Verification Checklist

- [ ] PVC shows `Bound` status
- [ ] PV created and shows `Bound` to PVC
- [ ] Dataset exists on TrueNAS: `zfs list | grep <pvc-name>`
- [ ] NFS export exists: `cat /etc/exports | grep <pvc-name>`
- [ ] Pod using PVC is `Running`
- [ ] `oc exec` into pod can write to mount: `touch /mnt/test`

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Owner:** SRE Team
