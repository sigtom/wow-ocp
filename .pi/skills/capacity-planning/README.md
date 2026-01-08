# Capacity Planning Skill

Track and forecast resource allocation across OpenShift cluster and Proxmox infrastructure to prevent outages and optimize utilization.

## Overview

This skill provides comprehensive capacity monitoring, analysis, and forecasting tools for the homelab infrastructure:
- **OpenShift Cluster:** 3x Dell FC630 blades (~72 vCPUs, ~384GB RAM)
- **Proxmox Host:** wow-prox1 (32C/64T, 256GB RAM)
- **Storage:** TrueNAS Scale (~11TB NFS + 2TB local LVM)

## Quick Start

### Check Current Capacity
```bash
# Overall cluster health
.pi/skills/capacity-planning/scripts/cluster-capacity.sh

# Per-node breakdown
.pi/skills/capacity-planning/scripts/node-utilization.sh

# Storage usage
.pi/skills/capacity-planning/scripts/storage-capacity.sh
```

### Before Deploying New Workload
```bash
# Estimate impact: 3 replicas × 2 CPU × 4GB RAM
.pi/skills/capacity-planning/scripts/estimate-impact.sh 2 4 3

# Will show GO/CAUTION/NO-GO recommendation
```

### Monthly Review
```bash
# Generate full report (text)
.pi/skills/capacity-planning/scripts/capacity-report.sh > capacity-$(date +%Y-%m).txt

# Generate markdown report
.pi/skills/capacity-planning/scripts/capacity-report.sh --markdown > capacity-$(date +%Y-%m).md
```

### Find Resource Hogs
```bash
# Top consumers
.pi/skills/capacity-planning/scripts/top-consumers.sh

# Proxmox capacity
.pi/skills/capacity-planning/scripts/proxmox-capacity.sh
```

## Capacity Thresholds

| Resource | Warning | Critical | Action |
|----------|---------|----------|--------|
| **CPU** | 85% | 90% | Defer non-critical workloads |
| **Memory** | 85% | 90% | No new deployments |
| **Storage** | 80% | 90% | Cleanup or expand |
| **Per-Node** | 80% | 85% | Rebalance workloads |

**Colors:**
- 🟢 **Green (<85%):** Healthy, proceed normally
- 🟡 **Yellow (85-90%):** Warning, defer non-critical
- 🔴 **Red (>90%):** Critical, block deployments

## Structure

```
capacity-planning/
├── SKILL.md                          # Main skill documentation
├── README.md                         # This file
├── references/
│   └── infrastructure-specs.md       # Hardware specs and constraints
├── templates/
│   └── capacity-report.md            # Monthly report template
└── scripts/
    ├── cluster-capacity.sh           # Overall cluster capacity
    ├── node-utilization.sh           # Per-node breakdown
    ├── storage-capacity.sh           # NFS and LVM usage
    ├── top-consumers.sh              # Top resource hogs
    ├── estimate-impact.sh            # Pre-deployment impact
    ├── proxmox-capacity.sh           # Proxmox VM/LXC usage
    └── capacity-report.sh            # Full monthly report
```

## Scripts

### cluster-capacity.sh
**Purpose:** Overall cluster health check

**Usage:**
```bash
./scripts/cluster-capacity.sh           # Full report
./scripts/cluster-capacity.sh --alert   # Alert mode (for cron)
```

**Output:**
- Total CPU, memory, pod capacity
- Allocated vs available
- Color-coded utilization bars
- Status: HEALTHY, WARNING, or CRITICAL

### node-utilization.sh
**Purpose:** Per-node resource breakdown

**Usage:**
```bash
./scripts/node-utilization.sh
```

**Output:**
- CPU/memory/pods per node
- Network capability (10G vs 1G)
- Hot node identification (>80%)
- Rebalancing recommendations

### storage-capacity.sh
**Purpose:** Storage usage across all storage classes

**Usage:**
```bash
./scripts/storage-capacity.sh               # Summary
./scripts/storage-capacity.sh --show-unused # Include unused PVCs
```

**Output:**
- TrueNAS ZFS pool usage
- PVC summary by StorageClass
- Prometheus storage check
- Unused PVC list (with --show-unused)

### top-consumers.sh
**Purpose:** Identify resource-intensive workloads

**Usage:**
```bash
./scripts/top-consumers.sh
```

**Output:**
- Top 10 namespaces by CPU
- Top 10 namespaces by memory
- Top 10 pods by CPU
- Top 10 pods by memory
- Top 10 PVCs by size

### estimate-impact.sh
**Purpose:** Calculate capacity impact before deployment

**Usage:**
```bash
./scripts/estimate-impact.sh <cpu_cores> <memory_gb> <replicas>

# Example: 3 replicas, 2 CPU, 4GB RAM each
./scripts/estimate-impact.sh 2 4 3
```

**Output:**
- Current cluster utilization
- Resources requested by new workload
- Projected utilization after deployment
- **GO/CAUTION/NO-GO recommendation**

### proxmox-capacity.sh
**Purpose:** Track Proxmox VM/LXC resource allocation

**Usage:**
```bash
./scripts/proxmox-capacity.sh
```

**Output:**
- VM and LXC resource allocations
- Total CPU/memory utilization
- Storage usage
- Capacity status

### capacity-report.sh
**Purpose:** Generate comprehensive monthly report

**Usage:**
```bash
./scripts/capacity-report.sh                           # Text format
./scripts/capacity-report.sh --markdown                # Markdown format
./scripts/capacity-report.sh --markdown > report.md    # Save to file
```

**Output:**
- Executive summary
- Compute utilization (cluster and per-node)
- Storage utilization (all storage classes)
- Top consumers
- Recommendations
- Capacity forecast

## Typical Workflows

### Daily Operations
```bash
# Quick health check
./scripts/cluster-capacity.sh

# If warning/critical, investigate
./scripts/node-utilization.sh
./scripts/top-consumers.sh
```

### Before Deployment
```bash
# Estimate impact
./scripts/estimate-impact.sh <cpu> <ram> <replicas>

# If GO, proceed
# If CAUTION, monitor closely
# If NO-GO, cleanup or defer
```

### Weekly Review
```bash
# Check trends
./scripts/cluster-capacity.sh
./scripts/storage-capacity.sh

# Identify optimization opportunities
./scripts/top-consumers.sh
```

### Monthly Review
```bash
# Generate report
./scripts/capacity-report.sh --markdown > /opt/capacity-reports/capacity-$(date +%Y-%m).md

# Review report with team
# Compare to last month
# Plan expansions if needed
```

### Emergency Cleanup
```bash
# Find unused PVCs
./scripts/storage-capacity.sh --show-unused

# Find idle pods
oc adm top pods --all-namespaces --sort-by=cpu | tail -20

# Scale down non-critical workloads
oc scale deployment <name> --replicas=0 -n <namespace>
```

## Integration with Other Skills

- **vm-provisioning:** Check capacity before creating VMs
- **argocd-ops:** Review capacity impact of GitOps deployments
- **truenas-ops:** Detailed storage analysis and cleanup
- **openshift-debug:** Troubleshoot resource exhaustion
- **media-stack:** Monitor impact of media apps (Plex, Sonarr)

## Automated Monitoring

### Cron Job (Daily Alert)
```bash
# Add to crontab on bastion host
0 8 * * * /path/to/scripts/cluster-capacity.sh --alert | mail -s "Capacity Alert" ops@sigtomtech.com
```

### Prometheus Alerts (Recommended)
```yaml
# infrastructure/monitoring/alerts/capacity-alerts.yaml
- alert: ClusterCPUHighUsage
  expr: (1 - (sum(kube_node_status_allocatable{resource="cpu"}) - sum(kube_pod_container_resource_requests{resource="cpu"})) / sum(kube_node_status_allocatable{resource="cpu"})) > 0.85
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Cluster CPU capacity >85%"
```

## Troubleshooting

### Metrics Server Not Available
```bash
# Check metrics-server pod
oc get pods -n openshift-monitoring | grep metrics

# Alternative: use Prometheus metrics
oc get --raw /apis/metrics.k8s.io/v1beta1/nodes
```

### SSH to TrueNAS Fails
```bash
# Test connection
ssh -v root@172.16.160.100

# Verify routing from bastion
ping 172.16.160.100
```

### Proxmox API Token Expired
```bash
# Test token
curl -k -H "Authorization: PVEAPIToken=sre-bot@pve!sre-token=$PROXMOX_SRE_BOT_API_TOKEN" \
  https://172.16.110.101:8006/api2/json/nodes/wow-prox1/status

# Regenerate in Proxmox UI if needed
```

### Inaccurate Metrics
```bash
# Metrics lag by 1-2 minutes, wait and re-run
# Check Prometheus targets
oc get servicemonitor -n openshift-monitoring
```

## Best Practices

1. **Proactive Monitoring**
   - Run capacity checks before deployments
   - Review trends weekly
   - Set up automated alerts

2. **Resource Requests**
   - Always set CPU/memory requests
   - Requests ≈ average usage
   - Limits ≈ peak usage

3. **Capacity Buffer**
   - Maintain 15-20% headroom
   - Don't push to 100%
   - Plan expansion at 80% sustained

4. **Regular Cleanup**
   - Remove unused PVCs monthly
   - Scale down idle deployments
   - Archive old data

5. **Balanced Nodes**
   - Spread workloads evenly
   - Use node affinity for specialized hardware
   - Avoid single-node hotspots

## Hardware Constraints

### OpenShift Nodes
- **Node 2 & 3:** 10G NICs (4-port) - Preferred for bandwidth-heavy workloads
- **Node 4:** 1G NIC (2-port) - Avoid for media apps, NFS-heavy workloads

**Node Selection:**
```yaml
# For bandwidth-heavy workloads
nodeSelector:
  kubernetes.io/hostname: wow-ocp-node2  # or node3
```

### Proxmox
- **CPU:** 32 cores (64 threads)
- **Memory:** 256GB
- **Target:** 70-80% utilization (no overcommit)

### Storage
- **TrueNAS:** ~11TB total
- **NFS:** 10G on Node 2/3, 1G on Node 4
- **LVM:** ~2TB local, faster but limited

See `references/infrastructure-specs.md` for complete details.

## Expansion Guidelines

### When to Expand
- Sustained >80% utilization for 2+ weeks
- Forecasted to hit 85% within 2 months
- Recurring critical alerts

### Expansion Options

**Compute:**
1. Add 4th worker node (~$500-1000 used blade)
2. Upgrade RAM (~$200 per 64GB)
3. Migrate workloads to Proxmox

**Storage:**
1. Expand TrueNAS pool (~$150 per 4TB HDD)
2. Add secondary NFS export
3. Offload media to separate pool

## Examples

### Example 1: Pre-Deployment Check
```bash
# Planning to deploy new app: 4 replicas, 2 CPU, 8GB each
$ ./scripts/estimate-impact.sh 2 8 4

Current Cluster Utilization:
  CPU: 60.5/72 cores (84%)
  Memory: 280/384 GB (73%)

New Workload Request:
  CPU: 8 cores (4 replicas × 2 cores)
  Memory: 32 GB (4 replicas × 8 GB)

Projected Utilization:
  CPU: 68.5/72 cores (95%) ⚠ CRITICAL
  Memory: 312/384 GB (81%) ✓ OK

Recommendation: NO-GO
  Options:
    1. Reduce replicas to 3 (6 cores total)
    2. Remove unused workloads
    3. Defer deployment

# Decision: Scale down to 3 replicas
$ ./scripts/estimate-impact.sh 2 8 3
# Now shows GO - safe to deploy
```

### Example 2: Monthly Review
```bash
# Generate January 2026 report
$ ./scripts/capacity-report.sh --markdown > /opt/capacity-reports/capacity-2026-01.md

# Compare to December 2025
$ diff /opt/capacity-reports/capacity-2025-12.md /opt/capacity-reports/capacity-2026-01.md

# Review findings:
# - CPU increased from 78% to 84% (+6%)
# - Storage grew by 600GB (media library)
# - Recommendations: Plan expansion in Q2 2026
```

### Example 3: Emergency Cleanup
```bash
# Critical alert: CPU at 92%
$ ./scripts/top-consumers.sh | head -20
# Identifies: old-dev-env namespace consuming 8 CPU cores

# Scale down
$ oc scale deployment --all --replicas=0 -n old-dev-env

# Verify
$ ./scripts/cluster-capacity.sh
# CPU now at 81% - back to safe levels
```

## References

- Infrastructure specs: `references/infrastructure-specs.md`
- Main skill documentation: `SKILL.md`
- Monthly report template: `templates/capacity-report.md`
- OpenShift docs: https://docs.openshift.com/container-platform/
- Kubernetes resource management: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

## Contributing

When improving capacity planning:
1. Test scripts on non-production first
2. Update thresholds based on real-world experience
3. Document capacity incidents and lessons learned
4. Share findings in monthly reviews

## License

Part of wow-ocp homelab infrastructure. Internal use only.
