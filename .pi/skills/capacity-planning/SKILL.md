# Capacity Planning Skill

**Purpose**: Track and forecast resource allocation across OpenShift cluster and Proxmox infrastructure to prevent outages and optimize utilization.

**When to use**:
- Before deploying new workloads (estimate impact)
- Monthly capacity reviews
- When investigating performance issues (resource contention)
- When planning hardware upgrades
- After incidents related to resource exhaustion

## Prerequisites

### OpenShift Access
- Cluster admin access: `oc adm top nodes`
- Metrics server running (prometheus-operator)
- Access to all namespaces

### Proxmox Access
- SSH access: `ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101`
- API token: `PROXMOX_SRE_BOT_API_TOKEN`

### TrueNAS Access
- SSH access: `ssh root@172.16.160.100`
- Access to ZFS commands

## Capacity Thresholds

| Resource | Warning | Critical | Action |
|----------|---------|----------|--------|
| **CPU** | 85% | 90% | Defer non-critical workloads |
| **Memory** | 85% | 90% | No new deployments without removal |
| **Storage** | 80% | 90% | Cleanup or expand immediately |
| **Per-Node CPU** | 80% | 85% | Rebalance workloads |
| **Per-Node Memory** | 80% | 85% | Rebalance workloads |

## Workflows

### 1. Check Current Cluster Capacity

**Purpose**: Quick snapshot of overall cluster health and available capacity.

**Steps:**

1. **Run cluster capacity check:**
   ```bash
   ./scripts/cluster-capacity.sh
   ```

   **Output includes:**
   - Total cluster resources (CPU, memory)
   - Allocated vs available
   - Utilization percentage (color-coded)
   - Pod count vs capacity
   - Status indicator (HEALTHY, WARNING, CRITICAL)

2. **Review per-node utilization:**
   ```bash
   ./scripts/node-utilization.sh
   ```

   **Shows:**
   - Each node's CPU/memory allocation
   - Node labels and roles
   - Hot nodes (>80% utilized)
   - Recommendations for rebalancing

3. **Check storage capacity:**
   ```bash
   ./scripts/storage-capacity.sh
   ```

   **Reports:**
   - NFS storage (truenas-nfs, truenas-nfs-dynamic)
   - LVM storage (lvms-vg1)
   - TrueNAS pool usage
   - PVC count and total size
   - Storage health status

**Expected Results:**
- Green: <85% utilization, cluster healthy
- Yellow: 85-90%, defer non-critical workloads
- Red: >90%, critical capacity, cleanup required

**When to run:**
- Before deploying new workloads
- Daily during on-call rotation
- When investigating performance issues

---

### 2. Estimate Impact Before Deploying New Workload

**Purpose**: Calculate whether new deployment fits within capacity thresholds.

**Steps:**

1. **Gather deployment specs:**
   - CPU requests/limits per pod
   - Memory requests/limits per pod
   - Number of replicas
   - Storage requirements (PVCs)

2. **Run impact estimation:**
   ```bash
   ./scripts/estimate-impact.sh <cpu_cores> <memory_gb> <replicas>
   
   # Example: 3 replicas, 2 CPU and 4GB RAM each
   ./scripts/estimate-impact.sh 2 4 3
   ```

3. **Review output:**
   - Current cluster utilization
   - Resources requested by new workload
   - Projected utilization after deployment
   - **GO/NO-GO recommendation**

4. **Decision matrix:**
   - **GO** (Green): Projected utilization <85%
   - **CAUTION** (Yellow): 85-90%, proceed with monitoring
   - **NO-GO** (Red): >90%, defer or remove other workloads

**Example output:**
```
Current Cluster Utilization:
  CPU: 60.5/72 cores (84%)
  Memory: 280/384 GB (73%)

New Workload Request:
  CPU: 6 cores (3 replicas × 2 cores)
  Memory: 12 GB (3 replicas × 4 GB)

Projected Utilization:
  CPU: 66.5/72 cores (92%) ⚠ CRITICAL
  Memory: 292/384 GB (76%) ✓ OK

Recommendation: NO-GO
  CPU would exceed 90% threshold
  Options:
    1. Reduce replicas to 2 (4 cores total)
    2. Remove unused workloads
    3. Defer deployment
```

**When to use:**
- Before every production deployment
- During capacity planning meetings
- When sizing new applications

---

### 3. Generate Monthly Capacity Report

**Purpose**: Comprehensive report for management review and trend analysis.

**Steps:**

1. **Generate full capacity report:**
   ```bash
   ./scripts/capacity-report.sh > /tmp/capacity-report-$(date +%Y-%m).txt
   ```

2. **Review report sections:**
   - Executive summary (status and trends)
   - Compute utilization (CPU/memory by node)
   - Storage utilization (NFS, LVM, TrueNAS)
   - Top consumers (namespaces and pods)
   - Recommendations and action items
   - Capacity forecast (time to thresholds)

3. **Convert to Markdown format:**
   ```bash
   ./scripts/capacity-report.sh --markdown > capacity-report-$(date +%Y-%m).md
   ```

4. **Add to monthly review:**
   - Copy report to documentation repo
   - Share with team for review
   - Track trends month-over-month
   - Plan hardware upgrades if needed

**Template includes:**
- Executive Summary
  - Overall status (HEALTHY/WARNING/CRITICAL)
  - Key metrics vs last month
  - Notable changes
- Compute Utilization
  - Cluster-wide CPU/memory
  - Per-node breakdown
  - Trend chart (ASCII)
- Storage Utilization
  - NFS usage and PVC count
  - LVM usage
  - TrueNAS pool health
- Top Resource Consumers
  - Top 10 namespaces by CPU
  - Top 10 namespaces by memory
  - Top 10 PVCs by size
- Recommendations
  - Immediate actions (RED items)
  - Short-term improvements (YELLOW items)
  - Long-term planning (expansions)
- Capacity Forecast
  - Estimated time to 85% threshold
  - Estimated time to 90% threshold
  - Recommended expansion timeline

**Frequency:** Monthly, first week of month

---

### 4. Identify Resource Hogs and Optimization Opportunities

**Purpose**: Find inefficient workloads consuming excessive resources.

**Steps:**

1. **List top consumers:**
   ```bash
   ./scripts/top-consumers.sh
   ```

   **Output:**
   - Top 10 namespaces by CPU usage
   - Top 10 namespaces by memory usage
   - Top 10 pods by CPU usage
   - Top 10 pods by memory usage
   - Top 10 PVCs by size

2. **Analyze each top consumer:**

   **For CPU hogs:**
   ```bash
   # Check pod metrics
   oc adm top pods -n <namespace> --sort-by=cpu
   
   # Check resource requests vs actual usage
   oc describe pod <pod-name> -n <namespace> | grep -A5 "Requests"
   
   # Review HPA (Horizontal Pod Autoscaler) configuration
   oc get hpa -n <namespace>
   ```

   **For memory hogs:**
   ```bash
   # Check memory usage over time
   oc adm top pods -n <namespace> --sort-by=memory
   
   # Check for memory leaks (increasing trend)
   # Review pod logs for OOMKilled events
   oc get events -n <namespace> | grep OOMKilled
   ```

   **For storage hogs:**
   ```bash
   # List PVCs in namespace
   oc get pvc -n <namespace> -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,USED:.status.capacity.storage
   
   # Check actual usage (if metrics available)
   oc exec -n <namespace> <pod> -- df -h /mount/path
   ```

3. **Optimization recommendations:**

   **Over-provisioned workloads (requests >> actual usage):**
   - Reduce CPU/memory requests to match actual usage
   - Adjust limits to prevent resource hoarding
   - Consider VPA (Vertical Pod Autoscaler)

   **Under-provisioned workloads (requests << actual usage, throttled):**
   - Increase requests to match actual needs
   - Prevent CPU throttling and OOMKilled events
   - May need cluster expansion if no headroom

   **Idle workloads (low actual usage, can be scaled down):**
   - Scale down replicas during off-hours
   - Consider HPA for dynamic scaling
   - Move to lower-priority scheduling class

   **Storage waste:**
   - Unused PVCs (bound but no mounting pod)
   - Oversized PVCs (requested 100GB, using 5GB)
   - Old snapshots consuming space

4. **Take action:**

   **Rightsize workload:**
   ```bash
   # Edit deployment to adjust resources
   oc edit deployment <name> -n <namespace>
   
   # Update CPU/memory requests and limits
   # Verify with dry-run first
   ```

   **Remove unused PVCs:**
   ```bash
   # List PVCs not mounted by any pod
   ./scripts/storage-capacity.sh --show-unused
   
   # Delete after verification
   oc delete pvc <name> -n <namespace>
   ```

   **Scale down idle workloads:**
   ```bash
   # Scale deployment to 0 or fewer replicas
   oc scale deployment <name> --replicas=0 -n <namespace>
   ```

**When to run:**
- Weekly during operations review
- When capacity thresholds are approaching
- After major deployments
- During cost optimization initiatives

---

### 5. Alert Threshold Checks

**Purpose**: Proactive alerting before capacity becomes critical.

**Steps:**

1. **Run automated threshold check:**
   ```bash
   ./scripts/cluster-capacity.sh --alert
   ```

   **Checks:**
   - Cluster CPU >85% (WARNING)
   - Cluster CPU >90% (CRITICAL)
   - Cluster memory >85% (WARNING)
   - Cluster memory >90% (CRITICAL)
   - Any node >80% (WARNING)
   - Storage >80% (WARNING)
   - Storage >90% (CRITICAL)

2. **Review alert output:**
   ```
   CLUSTER CAPACITY ALERT

   [CRITICAL] CPU utilization: 92% (>90%)
     Current: 66.2/72 cores
     Action: No new deployments until <90%

   [WARNING] Node wow-ocp-node2: 88% memory
     Current: 115/128 GB
     Action: Rebalance workloads

   [OK] Storage: 62% used
   ```

3. **Integration with monitoring:**

   **Prometheus alerts (recommended):**
   ```yaml
   # infrastructure/monitoring/alerts/capacity-alerts.yaml
   - alert: ClusterCPUHighUsage
     expr: (sum(kube_node_status_allocatable{resource="cpu"}) - sum(kube_pod_container_resource_requests{resource="cpu"})) / sum(kube_node_status_allocatable{resource="cpu"}) < 0.15
     for: 5m
     labels:
       severity: warning
     annotations:
       summary: "Cluster CPU capacity <15% available"
   ```

   **Cron job for daily checks:**
   ```bash
   # Add to cron on bastion host
   0 8 * * * /path/to/scripts/cluster-capacity.sh --alert | mail -s "Capacity Alert" ops@sigtomtech.com
   ```

4. **Alert response procedures:**

   **WARNING (85-90%):**
   - Notify team in Slack/email
   - Defer non-critical deployments
   - Identify optimization opportunities
   - Schedule cleanup tasks

   **CRITICAL (>90%):**
   - Page on-call engineer
   - Block all new deployments
   - Immediate cleanup required
   - Escalate to management if expansion needed

**When to run:**
- Automated daily via cron
- Before and after deployments
- During on-call handoff

---

### 6. Check Proxmox Capacity

**Purpose**: Track VM/LXC resource allocation on standalone Proxmox host.

**Steps:**

1. **Run Proxmox capacity check:**
   ```bash
   ./scripts/proxmox-capacity.sh
   ```

   **Output includes:**
   - Total CPU cores and memory
   - Allocated to VMs and LXCs
   - Available capacity
   - Per-VM/LXC resource breakdown
   - Storage usage on TSVMDS01

2. **Compare to hardware limits:**
   - Proxmox host: 2x E5-2683 v4 (32C/64T), 256GB RAM
   - Target utilization: 70-80%
   - No overcommit (dedicated resources)

3. **Rebalance if needed:**
   - Move VMs to OpenShift if appropriate
   - Consolidate underutilized VMs
   - Scale down development VMs

**When to run:**
- Before creating new Proxmox VMs
- Monthly capacity review
- When Proxmox host performance degrades

---

## Key Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `cluster-capacity.sh` | Overall cluster capacity | `./scripts/cluster-capacity.sh` |
| `node-utilization.sh` | Per-node breakdown | `./scripts/node-utilization.sh` |
| `storage-capacity.sh` | Storage usage (NFS, LVM) | `./scripts/storage-capacity.sh` |
| `top-consumers.sh` | Top resource hogs | `./scripts/top-consumers.sh` |
| `estimate-impact.sh` | Pre-deployment sizing | `./scripts/estimate-impact.sh 2 4 3` |
| `proxmox-capacity.sh` | Proxmox VM/LXC usage | `./scripts/proxmox-capacity.sh` |
| `capacity-report.sh` | Full monthly report | `./scripts/capacity-report.sh` |

---

## Troubleshooting

### Metrics Server Not Available
```bash
# Check metrics-server pod
oc get pods -n openshift-monitoring | grep metrics

# If missing, metrics from Prometheus
oc get --raw /apis/metrics.k8s.io/v1beta1/nodes
```

### SSH Access to TrueNAS Fails
```bash
# Test connection
ssh -v root@172.16.160.100

# Check SSH key permissions
ls -l ~/.ssh/id_rsa

# Verify VLAN 160 routing from bastion/node
ping 172.16.160.100
```

### Proxmox API Token Expired
```bash
# Verify token
curl -k -H "Authorization: PVEAPIToken=sre-bot@pve!sre-token=$PROXMOX_SRE_BOT_API_TOKEN" \
  https://172.16.110.101:8006/api2/json/nodes/wow-prox1/status

# Regenerate token in Proxmox UI if needed
```

### Inaccurate CPU/Memory Metrics
```bash
# Metrics lag behind by ~1-2 minutes
# Wait and re-run script

# Check Prometheus targets
oc get servicemonitor -n openshift-monitoring

# Verify node-exporter running
oc get pods -n openshift-monitoring | grep node-exporter
```

---

## Best Practices

1. **Proactive Monitoring**
   - Run capacity checks before deployments
   - Review trends weekly
   - Set up automated alerts

2. **Resource Requests**
   - Always set CPU/memory requests
   - Requests ≈ average usage, Limits ≈ peak usage
   - Avoid request=0 (breaks scheduling)

3. **Capacity Buffer**
   - Maintain 15-20% headroom for spikes
   - Don't push to 100% utilization
   - Plan expansion at 80% sustained

4. **Regular Cleanup**
   - Remove unused PVCs monthly
   - Scale down idle deployments
   - Archive old data to cold storage

5. **Balanced Nodes**
   - Spread workloads evenly across nodes
   - Use node affinity for specialized hardware
   - Avoid single-node hotspots

6. **Storage Strategy**
   - Use LVM for small, fast PVCs (<10GB)
   - Use NFS for large, shared PVCs (>10GB)
   - Monitor TrueNAS pool regularly

---

## Integration with Other Skills

- **vm-provisioning**: Check capacity before creating VMs
- **argocd-ops**: Review capacity impact of GitOps deployments
- **truenas-ops**: Detailed storage analysis and cleanup
- **openshift-debug**: Troubleshoot resource exhaustion issues
- **media-stack**: Monitor impact of media apps (Plex, Sonarr)

---

## Monthly Checklist

**Week 1:**
- [ ] Generate capacity report (`capacity-report.sh`)
- [ ] Review trends vs last month
- [ ] Identify top consumers
- [ ] Share report with team

**Week 2:**
- [ ] Cleanup unused PVCs
- [ ] Rightsize over-provisioned workloads
- [ ] Review storage snapshots

**Week 3:**
- [ ] Test capacity thresholds
- [ ] Verify alert notifications
- [ ] Update forecast models

**Week 4:**
- [ ] Plan next month's expansions
- [ ] Review optimization opportunities
- [ ] Document changes in capacity report

---

## Capacity Expansion Guidelines

**When to expand:**
- Sustained >80% utilization for 2+ weeks
- Forecasted to hit 85% within 2 months
- Recurring critical alerts

**Expansion options:**

**Compute (CPU/Memory):**
1. Add 4th worker node (requires new blade)
2. Upgrade existing blade RAM (max 128GB per node)
3. Migrate low-priority workloads to Proxmox

**Storage:**
1. Expand TrueNAS pool (add drives or vdev)
2. Add secondary NFS export
3. Offload media to separate pool

**Cost considerations:**
- New blade: ~$500-1000 (used Dell FC630)
- RAM upgrade: ~$200 per 64GB
- Storage drives: ~$150 per 4TB HDD

---

## Quick Reference

**Check capacity before deployment:**
```bash
./scripts/estimate-impact.sh <cpu> <ram> <replicas>
```

**Monthly report:**
```bash
./scripts/capacity-report.sh --markdown > report-$(date +%Y-%m).md
```

**Top consumers:**
```bash
./scripts/top-consumers.sh | head -20
```

**Emergency cleanup:**
```bash
# Find unused PVCs
./scripts/storage-capacity.sh --show-unused

# Find idle pods
oc adm top pods --all-namespaces --sort-by=cpu | tail -20
```

**Alert check:**
```bash
./scripts/cluster-capacity.sh --alert
```
