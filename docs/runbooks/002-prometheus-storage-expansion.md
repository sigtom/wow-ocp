# Runbook 002: Prometheus Storage Expansion

**Frequency:** Quarterly (as cluster grows)
**Impact:** Critical - Metrics collection stops, alerting fails
**Last Occurred:** 2025-12-31
**MTTR:** 15-30 minutes

---

## Symptoms

- Prometheus pods in `CrashLoopBackOff`
- Logs show: `level=error msg="opening storage failed" err="lock DB directory: resource temporarily unavailable"`
- Alternative error: `no space left on device`
- OpenShift Console shows "Prometheus Unavailable"
- Metrics dashboards show gaps or no data

**Quick Check:**
```bash
oc get pods -n openshift-monitoring | grep prometheus
oc logs -n openshift-monitoring prometheus-k8s-0 --tail=20
```

---

## Root Cause

**Technical Explanation:**
Prometheus stores metrics in a time-series database (TSDB) on a PVC. When the PVC reaches capacity:
1. Prometheus can no longer write new samples
2. WAL (Write-Ahead Log) gets corrupted or locked
3. Pod enters crash loop trying to recover

**Capacity Planning Failure:**
- 20Gi PVC was provisioned based on 1-node cluster assumptions
- Cluster grew to 3 nodes + 20+ workloads
- Scrape targets increased from ~50 to ~200
- Default retention (15 days) + high cardinality = fast fill

---

## Diagnosis Steps

### 1. Check PVC Usage
```bash
# Get PVC details
oc get pvc -n openshift-monitoring | grep prometheus

# Describe PVC to see size
oc describe pvc prometheus-k8s-db-prometheus-k8s-0 -n openshift-monitoring
```

### 2. Check Disk Usage Inside Pod (If Running)
```bash
oc exec -n openshift-monitoring prometheus-k8s-0 -c prometheus -- df -h /prometheus
```

**Problem Output:**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        20G   20G    0G 100% /prometheus
```

### 3. Check Prometheus Pod Events
```bash
oc describe pod prometheus-k8s-0 -n openshift-monitoring | grep -A 10 Events
```

**Look for:**
- `disk quota exceeded`
- `failed to open database`
- `no space left on device`

### 4. Check Prometheus Configuration
```bash
oc get configmap cluster-monitoring-config -n openshift-monitoring -o yaml
```

**Check retention settings:**
```yaml
data:
  config.yaml: |
    prometheusK8s:
      retention: 15d  # Default
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 20Gi  # TOO SMALL
```

---

## Resolution

### Quick Fix (Increase PVC Size)

#### Step 1: Edit PVC Directly
```bash
oc edit pvc prometheus-k8s-db-prometheus-k8s-0 -n openshift-monitoring
```

**Change:**
```yaml
spec:
  resources:
    requests:
      storage: 20Gi  # Change to 100Gi
```

**Save and exit.** The PVC will show `FileSystemResizePending`.

#### Step 2: Restart Prometheus Pod to Trigger Resize
```bash
oc delete pod prometheus-k8s-0 -n openshift-monitoring
```

**Note:** StatefulSet will recreate the pod automatically.

#### Step 3: Monitor Resize Progress
```bash
# Watch PVC status
oc get pvc prometheus-k8s-db-prometheus-k8s-0 -n openshift-monitoring -w

# Check TrueNAS expansion (if using NFS)
ssh truenas "zfs list | grep prometheus"
```

**Expected Timeline:**
- NFS PVC: Instant (ZFS quota change)
- Block storage: 1-5 minutes (filesystem resize)

### Permanent Fix (Update Cluster Monitoring Config)

#### Step 1: Update ConfigMap in Git

**File:** `infrastructure/monitoring/cluster-monitoring-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      retention: 15d
      volumeClaimTemplate:
        spec:
          storageClassName: truenas-nfs  # or lvms-vg1
          resources:
            requests:
              storage: 100Gi  # Increased from 20Gi
      resources:
        requests:
          cpu: 500m
          memory: 2Gi
        limits:
          cpu: 2000m
          memory: 8Gi
```

#### Step 2: Commit and Push
```bash
git add infrastructure/monitoring/cluster-monitoring-config.yaml
git commit -m "fix(monitoring): increase prometheus storage to 100Gi"
git push origin main
```

#### Step 3: Sync via ArgoCD
```bash
argocd app sync cluster-monitoring
argocd app wait cluster-monitoring --health
```

---

## Capacity Planning Formula

**Formula:**
```
PVC Size (GB) = (Samples/sec × Retention Days × 86400 × Sample Size) / 1,000,000,000
```

**Example (Current Cluster):**
- Scrape targets: 200
- Average samples per target: 500
- Total samples/sec: 200 × 500 / 60 = ~1,667 samples/sec
- Retention: 15 days
- Sample size: ~2 bytes (compressed)

```
PVC Size = (1667 × 15 × 86400 × 2) / 1,000,000,000 = ~43 GB
```

**Add 50% headroom:** 43 × 1.5 = ~65 GB
**Round up to:** 100 GB

---

## Alternative: Reduce Retention Period

If storage is constrained, reduce retention instead of expanding PVC:

```yaml
prometheusK8s:
  retention: 7d  # Reduced from 15d
  volumeClaimTemplate:
    spec:
      resources:
        requests:
          storage: 50Gi  # Half the size for half the retention
```

**Trade-off:** Lose historical metrics for debugging long-term trends.

---

## Prevention

### 1. Set Up Monitoring Alerts

**File:** `infrastructure/monitoring/prometheus-storage-alerts.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: prometheus-storage-alerts
  namespace: openshift-monitoring
spec:
  groups:
    - name: prometheus-storage
      rules:
        - alert: PrometheusStorageAlmostFull
          expr: |
            (kubelet_volume_stats_used_bytes{
              persistentvolumeclaim=~"prometheus-k8s-db-.*",
              namespace="openshift-monitoring"
            } / kubelet_volume_stats_capacity_bytes{
              persistentvolumeclaim=~"prometheus-k8s-db-.*",
              namespace="openshift-monitoring"
            }) > 0.80
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Prometheus storage is 80% full"
            description: "PVC {{ $labels.persistentvolumeclaim }} is {{ $value | humanizePercentage }} full"

        - alert: PrometheusStorageCritical
          expr: |
            (kubelet_volume_stats_used_bytes{
              persistentvolumeclaim=~"prometheus-k8s-db-.*",
              namespace="openshift-monitoring"
            } / kubelet_volume_stats_capacity_bytes{
              persistentvolumeclaim=~"prometheus-k8s-db-.*",
              namespace="openshift-monitoring"
            }) > 0.90
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Prometheus storage is 90% full - EXPAND NOW"
```

### 2. Monthly Capacity Review

**Schedule:** First Monday of each month

```bash
# Check current usage
oc exec -n openshift-monitoring prometheus-k8s-0 -c prometheus -- df -h /prometheus

# Check growth rate (samples ingested)
oc exec -n openshift-monitoring prometheus-k8s-0 -c prometheus -- \
  promtool tsdb analyze /prometheus
```

### 3. Enable Compaction (Automatic)

Prometheus automatically compacts old data, but verify it's working:

```bash
oc logs -n openshift-monitoring prometheus-k8s-0 -c prometheus | grep compact
```

**Expected:** Regular log entries like `msg="compact blocks" count=5 mint=xxx maxt=yyy`

---

## Troubleshooting

### Issue: PVC Resize Stuck in "FileSystemResizePending"

**Cause:** Pod not restarted to trigger filesystem resize.

**Fix:**
```bash
oc delete pod prometheus-k8s-0 -n openshift-monitoring
```

### Issue: Prometheus Still Crashes After Expansion

**Cause:** WAL corruption from previous out-of-space condition.

**Fix:**
```bash
# Scale down Prometheus StatefulSet
oc scale statefulset prometheus-k8s -n openshift-monitoring --replicas=0

# Clean WAL (DESTRUCTIVE - loses unflushed data)
oc debug node/<node-where-pvc-is-mounted>
chroot /host
cd /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~nfs/prometheus-k8s-db-prometheus-k8s-0
rm -rf wal/*
exit
exit

# Scale back up
oc scale statefulset prometheus-k8s -n openshift-monitoring --replicas=2
```

**⚠️ WARNING:** This loses unwritten metrics (usually <5 minutes).

### Issue: TrueNAS Refuses to Expand Quota

**Cause:** Parent dataset has quota set lower than child.

**Fix:**
```bash
ssh truenas

# Check parent quota
zfs get quota tank/k8s

# If lower than child, increase parent first
zfs set quota=500G tank/k8s

# Then increase child
zfs set quota=100G tank/k8s/prometheus-k8s-db-prometheus-k8s-0
```

---

## Related Issues

- **Issue:** LVM PVCs for Prometheus (high IOPS)
- **Runbook:** [001-lvm-operator-deadlock-recovery.md](001-lvm-operator-deadlock-recovery.md)
- **Documentation:** `infrastructure/monitoring/`

---

## Lessons Learned (2025-12-31)

1. **20Gi is too small** for any production cluster with >1 node
2. **Monitor PVC usage monthly** - don't wait for crash
3. **NFS expansion is instant** - no downtime for resize
4. **LVM expansion requires pod restart** - brief metrics gap
5. **Retention vs. Storage trade-off** - 7 days is often enough for homelab

---

## Verification Checklist

- [ ] Prometheus pods are `Running` (2/2 replicas)
- [ ] `oc exec` shows PVC is resized: `df -h /prometheus`
- [ ] OpenShift Console shows metrics graphs (no gaps)
- [ ] Alert `PrometheusPersistentVolumeFillingUp` is resolved
- [ ] Git manifest updated with new size
- [ ] ArgoCD shows `cluster-monitoring` as `Synced`

---

**Document Version:** 1.0
**Last Updated:** 2026-01-08
**Owner:** SRE Team
