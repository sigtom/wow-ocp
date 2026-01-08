# Platform Comparison: OpenShift Virtualization vs Proxmox

## Overview

This document helps you decide which virtualization platform to use for a given workload.

---

## OpenShift Virtualization (KubeVirt)

### Architecture
- **Technology**: KubeVirt on top of OpenShift/Kubernetes
- **Location**: Integrated with 3-node OpenShift cluster
- **Network**: Pod networking + Multus for additional networks (VLAN 130, etc.)
- **Storage**: Democratic CSI via TrueNAS Scale (NFS)
- **Management**: YAML manifests, GitOps (ArgoCD), oc/virtctl CLI

### Strengths
1. **Cluster Integration**
   - VMs run as pods, use same networking/storage as containers
   - Access via Services, Ingress, Routes
   - Share secrets, ConfigMaps with containerized apps
   - Unified RBAC and namespace isolation

2. **Live Migration**
   - Hot VM migration between nodes (requires RWX storage)
   - No downtime for maintenance or load balancing
   - Automatic failover on node failure

3. **GitOps Native**
   - Declarative VM definitions in Git
   - ArgoCD continuous sync and drift detection
   - Rollback to previous VM configurations
   - Infrastructure as code for VMs

4. **Cloud-Native Tooling**
   - Prometheus metrics for VM performance
   - Grafana dashboards
   - OpenShift logging integration
   - Automated backups via Velero

5. **Multi-Network Support**
   - Multus CNI for multiple interfaces
   - Bridge to physical VLANs (130, 140, etc.)
   - Mix pod network + external networks

### Limitations
1. **OS Support**
   - Best for Linux (RHEL, Ubuntu, Fedora)
   - Windows requires virtio-win drivers (extra complexity)
   - Legacy OS may have driver issues

2. **Hardware Passthrough**
   - Limited GPU/USB passthrough support
   - Requires additional node configuration
   - Not as mature as bare-metal hypervisor

3. **Resource Overhead**
   - virt-launcher pod per VM adds overhead
   - Less efficient than bare-metal hypervisor
   - Storage I/O through NFS (vs local ZFS)

4. **Complexity**
   - Steeper learning curve (Kubernetes + KubeVirt)
   - More moving parts (CDI, virt-operator, Multus)
   - Troubleshooting requires K8s knowledge

### Ideal Use Cases
- ✅ Production Linux VMs needing HA and live migration
- ✅ VMs that integrate with cluster services (databases, app servers)
- ✅ Workloads managed via GitOps pipeline
- ✅ VMs requiring rapid scaling or cloning
- ✅ Multi-tenant environments (namespace isolation)
- ✅ VMs needing OpenShift Routes/Ingress

### Not Ideal For
- ❌ Windows VMs (use Proxmox instead)
- ❌ Hardware passthrough requirements
- ❌ Legacy OS without modern drivers
- ❌ Workloads needing local ZFS storage
- ❌ Simple one-off VMs (Proxmox is easier)

---

## Proxmox VE (QEMU/KVM)

### Architecture
- **Technology**: Proxmox VE 9 on bare-metal blade
- **Host**: wow-prox1.sigtomtech.com (172.16.110.101)
- **Network**: VLAN 110 (management), bridged via vmbr0
- **Storage**: ZFS pool (TSVMDS01)
- **Management**: Proxmox Web UI, Ansible API calls, SSH

### Strengths
1. **Full Virtualization**
   - True hypervisor, better performance than nested
   - Local ZFS storage (fast, snapshots, compression)
   - Excellent Windows support
   - Mature driver ecosystem

2. **Hardware Passthrough**
   - Easy GPU passthrough (gaming VMs, ML workloads)
   - USB device passthrough
   - PCI device assignment
   - Direct disk passthrough

3. **Flexibility**
   - Mix VMs and LXC containers
   - Per-VM storage selection (ZFS, NFS, Ceph)
   - Custom VM configs via Proxmox GUI
   - Backup to Proxmox Backup Server

4. **Windows Support**
   - Native VirtIO drivers
   - RDP-friendly performance
   - Active Directory domain controllers
   - Windows-specific apps

5. **Simplicity**
   - Easier for one-off VMs
   - Intuitive web GUI
   - Less abstraction than Kubernetes
   - Direct KVM/QEMU control

### Limitations
1. **No Live Migration** (single host)
   - VM downtime for maintenance
   - Manual failover if host fails
   - No automatic HA

2. **Out-of-Cluster**
   - VMs isolated from OpenShift services
   - Manual networking to cluster workloads
   - Separate monitoring/logging setup

3. **Manual Management**
   - Ansible playbooks less declarative than GitOps
   - No automatic drift detection
   - Backup management separate from OCP

4. **Single Host**
   - All VMs on one physical machine
   - No distributed storage
   - Host maintenance = VM downtime

### Ideal Use Cases
- ✅ Windows VMs (Active Directory, RDP servers, Windows apps)
- ✅ Legacy OS requiring specific hardware or drivers
- ✅ Hardware passthrough (GPU for Plex transcoding, ML)
- ✅ One-off utility VMs (pfSense, network tools)
- ✅ VMs needing ZFS snapshots and local storage performance
- ✅ Development/testing environments

### Not Ideal For
- ❌ Production workloads requiring HA
- ❌ VMs needing integration with OpenShift services
- ❌ Workloads managed via GitOps
- ❌ Applications requiring automatic scaling
- ❌ VMs needing live migration

---

## Proxmox LXC Containers

### Architecture
- **Technology**: Linux Containers (LXC) on Proxmox
- **Isolation**: OS-level containerization (shared kernel)
- **Overhead**: Minimal (lighter than VMs)
- **Management**: Same as Proxmox VMs (API, GUI, Ansible)

### Strengths
1. **Resource Efficiency**
   - Lower CPU/memory overhead than VMs
   - Faster startup (seconds vs minutes)
   - Higher density on single host

2. **Linux Native**
   - Direct kernel access
   - Near-native performance
   - Standard systemd, networking, storage

3. **Quick Provisioning**
   - Template-based deployment
   - Cloud-init support
   - Fast cloning

4. **Cost Effective**
   - Run more workloads on same hardware
   - Less RAM per instance
   - Ideal for micro-services

### Limitations
1. **Linux Only**
   - Cannot run Windows
   - Shared kernel (all must be Linux)
   - Limited isolation vs full VMs

2. **No Kernel Modules**
   - Can't load custom kernel modules
   - Limited hardware access
   - No privileged operations (unless privileged LXC)

3. **Less Isolation**
   - Security boundary weaker than VMs
   - Kernel vulnerabilities affect all containers
   - Not suitable for untrusted workloads

### Ideal Use Cases
- ✅ Simple Linux services (web servers, databases)
- ✅ Development and testing environments
- ✅ Network utilities (DNS, DHCP, monitoring agents)
- ✅ Lightweight applications (scripts, cron jobs)
- ✅ Multiple isolated instances of same service

### Not Ideal For
- ❌ Windows workloads
- ❌ Workloads requiring custom kernel modules
- ❌ Untrusted or multi-tenant environments
- ❌ Applications needing full VM isolation
- ❌ Services requiring hardware passthrough

---

## Decision Matrix

| Requirement | OpenShift Virt | Proxmox VM | Proxmox LXC |
|-------------|----------------|------------|-------------|
| **Linux VM** | ✅ Best | ✅ Good | ❌ Use LXC instead |
| **Windows VM** | ⚠️ Possible | ✅ Best | ❌ Not supported |
| **Live Migration** | ✅ Yes (RWX) | ❌ No | ❌ No |
| **GitOps Managed** | ✅ Native | ⚠️ Via Ansible | ⚠️ Via Ansible |
| **Cluster Integration** | ✅ Native | ❌ Manual | ❌ Manual |
| **Hardware Passthrough** | ⚠️ Limited | ✅ Full | ❌ Limited |
| **Resource Efficiency** | ⚠️ Overhead | ✅ Good | ✅ Best |
| **Setup Complexity** | ⚠️ High | ✅ Low | ✅ Low |
| **HA / Failover** | ✅ Automatic | ❌ Manual | ❌ Manual |
| **Local ZFS Storage** | ❌ NFS only | ✅ Yes | ✅ Yes |
| **Fast Provisioning** | ⚠️ Minutes | ✅ Minutes | ✅ Seconds |
| **OS Support** | Linux (RHEL, Ubuntu) | Any | Linux only |

---

## Recommended Strategy

### Use OpenShift Virtualization for:
- **Production Linux VMs**: Database servers, app servers requiring HA
- **Cluster-Integrated Services**: VMs exposing services to pods
- **GitOps Workflows**: Infrastructure fully tracked in Git

### Use Proxmox VMs for:
- **Windows Workloads**: Domain controllers, RDP hosts, Windows apps
- **Hardware Needs**: GPU passthrough, USB devices, legacy hardware
- **Standalone Services**: VMs not needing cluster integration

### Use Proxmox LXC for:
- **Lightweight Linux Services**: Utility containers, dev/test
- **High Density**: Many small isolated environments
- **Quick Experiments**: Rapid spin-up/teardown

---

## Example Scenarios

### Scenario 1: Production PostgreSQL Database
**Choice**: OpenShift Virtualization
- Needs HA and live migration
- Integration with app pods via Service
- Managed via ArgoCD GitOps
- RWX storage for shared disk

### Scenario 2: Windows Active Directory DC
**Choice**: Proxmox VM
- Windows requires full VM
- Out-of-cluster is fine (VLAN 110)
- Proxmox has better Windows driver support
- Local ZFS for fast AD database

### Scenario 3: Dev Environment for Testing
**Choice**: Proxmox LXC
- Lightweight, fast startup
- Lower resource usage
- Easy to snapshot/clone
- Not production-critical

### Scenario 4: Plex Media Server
**Choice**: Proxmox VM (with GPU passthrough)
- Needs GPU for transcoding
- Hardware passthrough easiest on bare-metal hypervisor
- Out-of-cluster isolation fine
- Local ZFS for fast media access

### Scenario 5: GitOps-Managed Web Server
**Choice**: OpenShift Virtualization
- Fully declarative in Git
- Exposed via OpenShift Route
- Automatic scaling potential
- Integration with CI/CD pipeline

### Scenario 6: DNS Resolver for Lab
**Choice**: Proxmox LXC
- Lightweight, efficient
- Simple utility service
- Fast recovery if needed
- Low resource footprint

---

## Migration Between Platforms

### Proxmox → OpenShift
1. Export disk as raw/qcow2
2. Upload to OpenShift via CDI/virtctl
3. Create VM referencing uploaded disk
4. Adjust cloud-init/network for pod environment

### OpenShift → Proxmox
1. Snapshot VM disk to PVC
2. Export PVC to local file (oc cp, or mount PVC to pod)
3. Upload to Proxmox storage
4. Create VM using imported disk

### LXC → OpenShift
**Not recommended**: Convert LXC to full VM, or rebuild as container/VM

---

## Summary

- **OpenShift Virtualization**: Best for production Linux VMs needing HA, GitOps, cluster integration
- **Proxmox VM**: Best for Windows, hardware passthrough, standalone services
- **Proxmox LXC**: Best for lightweight Linux services, dev/test, high-density workloads

Choose based on OS, HA requirements, integration needs, and resource efficiency.
