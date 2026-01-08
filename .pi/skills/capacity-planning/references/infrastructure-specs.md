# Infrastructure Specifications

This document details the hardware constraints and configuration of the homelab infrastructure for capacity planning purposes.

---

## OpenShift Cluster

### Hardware Summary

The OpenShift cluster consists of **3 Dell PowerEdge FC630 blade servers** running in a Dell M1000e chassis.

| Component | Total | Per Node Average |
|-----------|-------|------------------|
| **CPU Cores** | ~72 vCPUs | ~24 vCPUs |
| **Memory** | ~384 GB | ~128 GB |
| **Network** | Mixed | See node details |
| **Storage** | 2TB local LVM | ~667GB per node |

### Node-Specific Details

#### Node 2: wow-ocp-node2 (Master + Worker)
- **Model**: Dell PowerEdge FC630
- **CPU**: 2x Intel Xeon (exact model varies, ~12C/24T each)
- **Memory**: 128 GB DDR4 ECC
- **Network**: **4-port blade, 10 Gbps NICs** ✅
  - High bandwidth capability
  - Preferred for network-intensive workloads
  - Ideal for: Ingress controllers, storage traffic, media streaming
- **Storage**: 
  - Local: ~667GB LVM (lvms-vg1)
  - NFS: TrueNAS via VLAN 160 (10G capable)
- **Roles**: Master, Worker
- **Special Notes**: Primary node for bandwidth-heavy apps

#### Node 3: wow-ocp-node3 (Master + Worker)
- **Model**: Dell PowerEdge FC630
- **CPU**: 2x Intel Xeon (~12C/24T each)
- **Memory**: 128 GB DDR4 ECC
- **Network**: **4-port blade, 10 Gbps NICs** ✅
  - High bandwidth capability
  - Preferred for network-intensive workloads
  - Ideal for: Plex, Sonarr, Radarr, large data transfers
- **Storage**:
  - Local: ~667GB LVM (lvms-vg1)
  - NFS: TrueNAS via VLAN 160 (10G capable)
- **Roles**: Master, Worker
- **Special Notes**: Paired with Node 2 for high-bandwidth workloads

#### Node 4: wow-ocp-node4 (Master + Worker)
- **Model**: Dell PowerEdge FC630
- **CPU**: 2x Intel Xeon (~12C/24T each)
- **Memory**: 128 GB DDR4 ECC
- **Network**: **2-port blade, 1 Gbps hybrid NIC** ⚠️
  - Limited bandwidth (1G vs 10G)
  - Avoid for bandwidth-heavy workloads
  - Suitable for: Control plane, lightweight services, compute-only tasks
- **Storage**:
  - Local: ~667GB LVM (lvms-vg1)
  - NFS: TrueNAS via VLAN 160 (bottlenecked by 1G NIC)
- **Roles**: Master, Worker
- **Special Notes**: Avoid scheduling media apps or high I/O workloads here

### Cluster Networking

- **Pod Network**: 10.128.0.0/14 (internal)
- **Service Network**: 172.30.0.0/16 (internal)
- **Workload VLAN 130**: 172.16.130.0/24 (Multus bridge)
- **Management VLAN 110**: 172.16.110.0/24 (node access)
- **Storage VLAN 160**: 172.16.160.0/24 (NFS to TrueNAS)

**Node Affinity Recommendations:**
```yaml
# For bandwidth-heavy workloads (Plex, Sonarr, media apps)
nodeSelector:
  kubernetes.io/hostname: wow-ocp-node2  # or node3
# OR
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchExpressions:
      - key: kubernetes.io/hostname
        operator: In
        values:
        - wow-ocp-node2
        - wow-ocp-node3
```

### Cluster Capacity Targets

| Resource | Target Utilization | Threshold Warning | Threshold Critical |
|----------|-------------------|-------------------|-------------------|
| **CPU** | 70-80% | 85% | 90% |
| **Memory** | 70-80% | 85% | 90% |
| **Storage** | 60-70% | 80% | 90% |
| **Per-Node CPU** | 60-75% | 80% | 85% |
| **Per-Node Memory** | 60-75% | 80% | 85% |

**Rationale:**
- **70-80% target**: Leave headroom for spikes, node failures, rolling updates
- **15-20% buffer**: Allows for bursty workloads and maintenance windows
- **Don't exceed 90%**: Risk of scheduling failures, performance degradation

---

## Proxmox Host

### Hardware

- **Hostname**: wow-prox1.sigtomtech.com
- **Model**: Dell PowerEdge R730 (or similar)
- **CPU**: 2x Intel Xeon E5-2683 v4 (16C/32T each) = **32 cores, 64 threads**
- **Memory**: 256 GB DDR4 ECC
- **Network**: 
  - Management: VLAN 110 (172.16.110.101)
  - Storage: VLAN 160 to TrueNAS (NFS)
- **Local Storage**: SSDs for VM boot disks
- **Shared Storage**: TSVMDS01 (ZFS pool via NFS from TrueNAS)

### Current Allocation (as of Jan 2026)

| Resource | Total | Used | Available | Utilization |
|----------|-------|------|-----------|-------------|
| **CPU** | 32 cores | ~12 cores | ~20 cores | ~37% |
| **Memory** | 256 GB | ~80 GB | ~176 GB | ~31% |
| **VMs** | - | ~5 VMs | - | - |
| **LXCs** | - | ~3 LXCs | - | - |

**Capacity Notes:**
- Proxmox runs **out-of-cluster** on VLAN 110 (management network)
- No overcommit policy (resources dedicated to VMs/LXCs)
- Target utilization: 70-80% to maintain stability
- Storage via NFS (TSVMDS01), not local ZFS

### Proxmox vs OpenShift

**Use Proxmox for:**
- Windows VMs (better driver support)
- Hardware passthrough (GPU, USB)
- Isolated workloads (out-of-cluster)
- Legacy applications

**Use OpenShift for:**
- Linux production workloads
- GitOps-managed infrastructure
- Workloads needing HA and live migration
- Cluster-integrated services

---

## Storage Infrastructure

### TrueNAS Scale 25.10

- **Hostname**: wow-truenas.sigtomtech.com
- **IP**: 172.16.160.100 (VLAN 160, storage network)
- **Pool**: wow-ts10TB (ZFS)
- **Disks**: Multiple HDDs in RAIDZ configuration
- **Total Capacity**: ~11 TB usable (after RAID overhead and compression)

### Storage Breakdown

#### 1. NFS Static Storage (truenas-nfs)

**Purpose**: Large, read-write-many PVCs for shared data

- **StorageClass**: `truenas-nfs`
- **Access Mode**: ReadWriteMany (RWX)
- **Provisioner**: Democratic CSI (manual provisioning)
- **Dataset**: `wow-ts10TB/ocp-nfs-volumes/v/<pvc-name>`
- **Current Usage**: ~5-6 TB (as of Jan 2026)

**Use cases:**
- Media library: ~5 TB (static PV `media-library`)
- Plex metadata: ~100 GB
- Shared config files
- Live migration disks (KubeVirt VMs)

**Capacity:**
- **Target**: <70% (7.7 TB)
- **Warning**: 80% (8.8 TB)
- **Critical**: 90% (9.9 TB)

#### 2. NFS Dynamic Storage (truenas-nfs-dynamic)

**Purpose**: Automatically provisioned PVCs for applications

- **StorageClass**: `truenas-nfs-dynamic`
- **Access Mode**: ReadWriteOnce (RWO) or ReadWriteMany (RWX)
- **Provisioner**: Democratic CSI (dynamic provisioning)
- **Dataset**: `wow-ts10TB/ocp-nfs-volumes/v/<pvc-uuid>`
- **Current Usage**: ~500 GB (various app PVCs)

**Use cases:**
- Application databases (PostgreSQL, MySQL)
- Application persistent data
- Log storage
- Backup storage

#### 3. LVM Local Storage (lvms-vg1)

**Purpose**: Fast, local storage for ephemeral or small PVCs

- **StorageClass**: `lvms-vg1`
- **Access Mode**: ReadWriteOnce (RWO) only
- **Provisioner**: LVMS Operator (Logical Volume Manager Storage)
- **Location**: Local disks on Node 2, 3, 4
- **Total Capacity**: ~2 TB across all nodes (~667 GB per node)
- **Current Usage**: ~800 GB

**Use cases:**
- Container image storage (ephemeral)
- Fast database workloads (latency-sensitive)
- Prometheus metrics storage (~100 GB)
- Temporary scratch space

**Capacity:**
- **Target**: <70% (1.4 TB)
- **Warning**: 80% (1.6 TB)
- **Critical**: 90% (1.8 TB)

#### 4. Prometheus Storage

**Special case**: Expanded from 20GB to 100GB in December 2025 after exhaustion.

- **PVC**: `prometheus-k8s-db-prometheus-k8s-0` (in `openshift-monitoring`)
- **StorageClass**: `lvms-vg1` (local, fast)
- **Size**: 100 GB
- **Usage**: ~60 GB (as of Jan 2026)
- **Retention**: 15 days (default)

**Monitoring:**
- Check monthly to avoid re-exhaustion
- Consider increasing retention if <70% used
- Alert at 80% to plan expansion

### Storage Network (VLAN 160)

- **Network**: 172.16.160.0/24
- **Gateway**: 172.16.160.1
- **TrueNAS**: 172.16.160.100
- **Bandwidth**: 10 Gbps on Node 2 & 3, 1 Gbps on Node 4
- **Protocol**: NFS v4.1
- **Mount Options**: `hard,nfsvers=4.1,noatime,nodiratime`

**Performance Notes:**
- Node 2 & 3: Full 10G speed (~1 GB/s throughput)
- Node 4: Bottlenecked at 1G (~125 MB/s throughput)
- Avoid scheduling bandwidth-heavy apps on Node 4

---

## Capacity Planning Guidelines

### Compute (CPU & Memory)

#### Cluster-Level

**Current (Jan 2026):**
- CPU: 72 vCPUs (Intel Xeon, ~2.4 GHz base, 3.0 GHz boost)
- Memory: 384 GB DDR4 ECC

**Allocation strategy:**
- Reserve 10% for system overhead (kube-system, monitoring, etc.)
- Reserve 10% for burst capacity
- Target 70-80% steady-state utilization

**Expansion triggers:**
- Sustained >80% for 2+ weeks
- Frequent pod evictions due to resource pressure
- New workload requires >20% of total capacity

**Expansion options:**
1. Add 4th worker node (requires new blade, ~$500-1000)
2. Upgrade RAM on existing nodes (max 128GB per node, ~$200 per 64GB module)
3. Offload non-critical workloads to Proxmox

#### Node-Level

**Imbalance indicators:**
- One node >85%, others <60%
- Frequent pod rescheduling due to resource constraints
- Performance degradation on specific node

**Rebalancing strategies:**
1. Use pod topology spread constraints
2. Adjust node affinity/anti-affinity
3. Drain and reschedule pods manually
4. Use descheduler operator (future)

### Storage

#### NFS (TrueNAS)

**Current capacity:**
- Total: ~11 TB usable
- Used: ~6 TB (55%)
- Available: ~5 TB (45%)

**Growth rate (estimated):**
- Media library: +500 GB/month (new content)
- Dynamic PVCs: +100 GB/month (app data)
- Snapshots: +50 GB/month (CSI snapshots)
- **Total**: ~650 GB/month (~6% per month)

**Forecast:**
- 80% threshold: ~8.8 TB (reached in ~4-5 months at current rate)
- 90% threshold: ~9.9 TB (reached in ~6-7 months)

**Expansion options:**
1. Add drives to existing vdev (if slots available)
2. Add new vdev to pool (expands capacity)
3. Migrate old media to cold storage (external archive)
4. Enable deduplication (if applicable, CPU-intensive)

**Cost:**
- 4TB HDD: ~$150 each
- 8TB HDD: ~$250 each
- Recommend adding 2-4 drives at a time for RAID resilvering speed

#### LVM (Local)

**Current capacity:**
- Total: ~2 TB across 3 nodes
- Used: ~800 GB (40%)
- Available: ~1.2 TB (60%)

**Growth rate:**
- Relatively stable (ephemeral storage)
- Prometheus: +5-10 GB/month
- New apps: variable

**Expansion limited by:**
- Local disk capacity on blades (limited slots)
- Cannot easily expand without hardware upgrade

**If LVM exhausted:**
1. Move large PVCs to NFS
2. Clean up unused local PVs
3. Reduce Prometheus retention
4. Upgrade to larger local disks (requires hardware swap)

---

## Network Bandwidth Considerations

### Node 2 & 3 (10 Gbps)

**Capabilities:**
- Sustained: ~9 Gbps (~1.1 GB/s)
- Peak: ~10 Gbps (~1.25 GB/s)
- Latency: <1ms to TrueNAS (same rack)

**Ideal workloads:**
- Plex media streaming (4K transcoding)
- Sonarr/Radarr (large file downloads)
- Backup operations (Velero, pgBackRest)
- VM live migration (KubeVirt)

### Node 4 (1 Gbps)

**Capabilities:**
- Sustained: ~900 Mbps (~112 MB/s)
- Peak: ~1 Gbps (~125 MB/s)
- **10x slower than Node 2/3**

**Avoid:**
- Media streaming apps
- Large file transfers
- NFS-heavy workloads

**Suitable for:**
- Control plane components (API server, etcd)
- Lightweight services (DNS, monitoring exporters)
- Compute-only workloads (CPU-bound, no I/O)

---

## Historical Capacity Events

### December 2025: Prometheus Storage Exhaustion

**Incident:**
- Prometheus PVC filled to 100% (20GB)
- Metrics collection stopped
- Monitoring dashboards stale

**Resolution:**
1. Expanded PVC from 20GB to 100GB
2. Reduced retention from 30d to 15d
3. Added alert for >80% usage

**Lesson learned:**
- Monitor monitoring storage
- Plan for 5x growth over retention period
- Alert early (80%, not 95%)

### Ongoing: Media Library Growth

**Observation:**
- Media library grows ~500 GB/month (new TV shows, movies)
- Approaching 6 TB (55% of pool)

**Action plan:**
- Monitor monthly
- Plan TrueNAS expansion at 80% (Q2 2026)
- Consider cold storage archival (old content to external drives)

---

## Capacity Planning Schedule

### Daily
- Automated capacity checks (via cron or Prometheus)
- Alert on >85% CPU/memory or >80% storage

### Weekly
- Review top consumers
- Identify optimization opportunities
- Rebalance hot nodes

### Monthly
- Generate capacity report
- Review trends vs last month
- Plan expansions if needed
- Update forecast models

### Quarterly
- Hardware health check
- Firmware updates
- Capacity roadmap review
- Budget planning for expansions

---

## Contact and Resources

**Monitoring Dashboards:**
- Grafana: https://grafana.wow.sigtomtech.com
- Prometheus: https://prometheus.wow.sigtomtech.com
- OpenShift Console: https://console-openshift-console.apps.wow.sigtomtech.com

**Capacity Planning Tools:**
- Scripts: `.pi/skills/capacity-planning/scripts/`
- Reports: `/opt/capacity-reports/` (on bastion)

**Hardware Specs:**
- Dell FC630 Spec Sheet: https://www.dell.com/support/home/en-us/product-support/product/poweredge-fc630/docs
- Intel Xeon E5 v4: https://ark.intel.com/content/www/us/en/ark/products/series/91283/intel-xeon-processor-e5-v4-family.html

**For questions:**
- Team: ops@sigtomtech.com
- Documentation: wow-ocp repo, `.pi/skills/`

---

## Summary Table

| Component | Total Capacity | Current Usage | Available | Target | Warning | Critical |
|-----------|---------------|---------------|-----------|--------|---------|----------|
| **OCP CPU** | 72 vCPUs | ~60 vCPUs (83%) | ~12 vCPUs | 70-80% | 85% | 90% |
| **OCP Memory** | 384 GB | ~300 GB (78%) | ~84 GB | 70-80% | 85% | 90% |
| **NFS Storage** | 11 TB | ~6 TB (55%) | ~5 TB | 60-70% | 80% | 90% |
| **LVM Storage** | 2 TB | ~800 GB (40%) | ~1.2 TB | 60-70% | 80% | 90% |
| **Proxmox CPU** | 64 threads | ~12 cores (37%) | ~20 cores | 70-80% | 85% | 90% |
| **Proxmox Memory** | 256 GB | ~80 GB (31%) | ~176 GB | 70-80% | 85% | 90% |

**Note**: Usage percentages are estimates as of January 2026. Run capacity scripts for real-time data.
