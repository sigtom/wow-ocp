# Homelab Capacity Planning Report
**Date:** YYYY-MM-DD  
**Period:** Month YYYY  
**Prepared by:** [Your Name]

---

## Executive Summary

### Overall Status
- **Cluster Health:** [HEALTHY | WARNING | CRITICAL]
- **CPU Utilization:** XX% (Target: 70-80%, Warning: 85%, Critical: 90%)
- **Memory Utilization:** XX% (Target: 70-80%, Warning: 85%, Critical: 90%)
- **Storage Utilization:** XX% (Target: 60-70%, Warning: 80%, Critical: 90%)

### Key Highlights
- [Notable changes from last month]
- [Any capacity incidents or near-misses]
- [Major deployments or removals]

### Action Items
- [ ] [Immediate action 1]
- [ ] [Short-term action 2]
- [ ] [Long-term planning item 3]

---

## Compute Utilization

### OpenShift Cluster

#### Cluster-Wide Metrics
| Metric | Total | Allocated | Available | Utilization | Status |
|--------|-------|-----------|-----------|-------------|--------|
| **CPU** | XX cores | XX cores | XX cores | XX% | [OK/WARN/CRIT] |
| **Memory** | XX GB | XX GB | XX GB | XX% | [OK/WARN/CRIT] |
| **Pods** | XX capacity | XX running | XX available | XX% | [OK/WARN/CRIT] |

#### Per-Node Breakdown

**Node 2 (wow-ocp-node2) - 10G Network**
- CPU: XX/XX cores (XX%)
- Memory: XX/XX GB (XX%)
- Pods: XX/XX (XX%)
- Status: [OK/WARN/CRIT]
- Notes: [Preferred for bandwidth-heavy workloads]

**Node 3 (wow-ocp-node3) - 10G Network**
- CPU: XX/XX cores (XX%)
- Memory: XX/XX GB (XX%)
- Pods: XX/XX (XX%)
- Status: [OK/WARN/CRIT]
- Notes: [Preferred for bandwidth-heavy workloads]

**Node 4 (wow-ocp-node4) - 1G Network**
- CPU: XX/XX cores (XX%)
- Memory: XX/XX GB (XX%)
- Pods: XX/XX (XX%)
- Status: [OK/WARN/CRIT]
- Notes: [Avoid for NFS-heavy or media workloads]

#### Hot Nodes
- [List any nodes >80% utilization]
- [Recommendations for rebalancing]

### Proxmox Host (wow-prox1)

| Metric | Total | Allocated | Available | Utilization | Status |
|--------|-------|-----------|-----------|-------------|--------|
| **CPU** | 32 cores (64 threads) | XX cores | XX cores | XX% | [OK/WARN/CRIT] |
| **Memory** | 256 GB | XX GB | XX GB | XX% | [OK/WARN/CRIT] |
| **VMs** | - | XX | - | - | - |
| **LXCs** | - | XX | - | - | - |

#### VM/LXC List
- [List major VMs and their resource allocation]
- [Note any underutilized VMs that could be migrated]

---

## Storage Utilization

### TrueNAS ZFS Pool (wow-ts10TB)

| Metric | Total | Used | Available | Utilization | Status |
|--------|-------|------|-----------|-------------|--------|
| **Pool** | XX TB | XX TB | XX TB | XX% | [OK/WARN/CRIT] |

#### Datasets
- **Media Library (static):** XX TB
- **OCP Dynamic PVCs:** XX TB
- **Snapshots:** XX GB

### OpenShift Storage Classes

#### NFS Storage (truenas-nfs)
- **PVC Count:** XX
- **Total Size:** XX GB
- **Largest PVCs:**
  1. namespace/pvc-name: XX GB
  2. namespace/pvc-name: XX GB
  3. namespace/pvc-name: XX GB

#### NFS Dynamic Storage (truenas-nfs-dynamic)
- **PVC Count:** XX
- **Total Size:** XX GB

#### LVM Local Storage (lvms-vg1)
- **Total:** ~2 TB
- **Used:** XX GB (XX%)
- **Prometheus PVC:** XX/100 GB (XX%)
- **Notes:** [Check monthly to avoid Prometheus exhaustion]

---

## Top Resource Consumers

### Top 10 Namespaces by CPU
1. namespace-1: XXm
2. namespace-2: XXm
3. ...

### Top 10 Namespaces by Memory
1. namespace-1: XXMi
2. namespace-2: XXMi
3. ...

### Top 10 Pods by CPU
1. namespace/pod-1: XXm
2. namespace/pod-2: XXm
3. ...

### Top 10 Pods by Memory
1. namespace/pod-1: XXMi
2. namespace/pod-2: XXMi
3. ...

### Top 10 PVCs by Size
1. namespace/pvc-1: XX GB
2. namespace/pvc-2: XX GB
3. ...

### Analysis
- [Are top consumers justified? Production workloads or resource waste?]
- [Optimization opportunities identified]

---

## Recommendations

### Immediate Actions (RED - Critical)
_[List any critical capacity issues requiring immediate attention]_

- [ ] None currently

OR

- [ ] [Action 1: Scale down X to free Y resources]
- [ ] [Action 2: Clean up unused PVCs]

### Short-Term Actions (YELLOW - Warning)
_[List warning-level issues or optimization opportunities]_

- [ ] [Action 1: Review namespace X resource requests vs actual usage]
- [ ] [Action 2: Plan storage cleanup]

### Long-Term Planning (GREEN - Proactive)
_[Strategic initiatives for capacity management]_

- [ ] [Plan cluster expansion if trends continue]
- [ ] [Budget for additional storage (Q2 2026)]
- [ ] [Evaluate workload migration opportunities]

---

## Capacity Forecast

### Growth Trends (vs Last Month)

| Metric | Last Month | This Month | Change | Growth Rate |
|--------|-----------|------------|--------|-------------|
| **CPU Usage** | XX% | XX% | +X% | X%/month |
| **Memory Usage** | XX% | XX% | +X% | X%/month |
| **Storage Used** | XX TB | XX TB | +X TB | X TB/month |

### Projected Time to Thresholds

**CPU:**
- Time to 85% (Warning): [X months]
- Time to 90% (Critical): [X months]

**Memory:**
- Time to 85% (Warning): [X months]
- Time to 90% (Critical): [X months]

**Storage:**
- Time to 80% (Warning): [X months]
- Time to 90% (Critical): [X months]
- **Media growth:** ~500 GB/month
- **Dynamic PVCs:** ~100 GB/month

### Expansion Planning

**If no action taken:**
- Cluster CPU will hit 85% by [Month Year]
- Storage will hit 80% by [Month Year]

**Recommended actions:**
1. [Plan hardware procurement by X date]
2. [Clean up X GB storage by Y date]
3. [Optimize Z workload by A date]

---

## Incidents and Events

### Capacity-Related Incidents
_[List any incidents related to capacity exhaustion]_

- **YYYY-MM-DD:** [Description]
  - **Root cause:** [Cause]
  - **Resolution:** [How resolved]
  - **Prevention:** [Measures taken]

### Major Deployments
_[List significant new deployments this month]_

- **Project X:** [Resources: X CPU, Y GB RAM, Z GB storage]
- **Project Y:** [Resources: ...]

### Decommissions/Cleanups
_[List workloads removed or scaled down]_

- **Removed:** [Old workload, freed X resources]
- **Scaled down:** [Workload Y, freed Z resources]

---

## Infrastructure Changes

### Hardware
- [Any hardware additions, failures, or upgrades]

### Software
- [OpenShift version upgrades]
- [Storage backend changes]
- [Monitoring improvements]

### Networking
- [Network infrastructure changes]
- [VLAN modifications]

---

## Cost Analysis (Optional)

### Current Infrastructure Costs
- **Electricity:** ~$XX/month (estimated)
- **Hardware depreciation:** ~$XX/month
- **Total operational cost:** ~$XX/month

### Expansion Cost Estimates
- **New blade (worker node):** ~$500-1000
- **RAM upgrade (64GB):** ~$200
- **Storage expansion (4TB HDD x4):** ~$600

### ROI on Optimization
- [Estimated savings from rightsize/cleanup]

---

## Action Items for Next Month

### Capacity Management
- [ ] Monitor trends weekly
- [ ] Review top consumers
- [ ] Clean up unused resources

### Expansion Planning
- [ ] [If needed] Procure hardware by [date]
- [ ] [If needed] Plan storage expansion

### Documentation
- [ ] Update capacity planning docs
- [ ] Archive this report
- [ ] Prepare next month's report template

---

## Report Metadata

- **Generated:** YYYY-MM-DD HH:MM:SS TZ
- **Generated by:** [Your name/tool]
- **Report period:** [Month YYYY]
- **Data sources:** 
  - OpenShift metrics (prometheus, metrics-server)
  - Proxmox API
  - TrueNAS SSH
  - Capacity planning scripts
- **Next review:** [First week of next month]

---

## Appendix

### Scripts Used
```bash
# Generate this report
./scripts/capacity-report.sh --markdown > capacity-YYYY-MM.md

# Individual checks
./scripts/cluster-capacity.sh
./scripts/node-utilization.sh
./scripts/storage-capacity.sh
./scripts/top-consumers.sh
./scripts/proxmox-capacity.sh
```

### Historical Reports
- Previous report: `/opt/capacity-reports/capacity-YYYY-MM.md`
- Compare: `diff capacity-2025-12.md capacity-2026-01.md`

### References
- Infrastructure specs: `.pi/skills/capacity-planning/references/infrastructure-specs.md`
- Capacity planning skill: `.pi/skills/capacity-planning/SKILL.md`

---

**Report Status:** [DRAFT | FINAL]  
**Reviewed by:** [Team lead]  
**Approved by:** [Manager]  
**Date finalized:** YYYY-MM-DD
