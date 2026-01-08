---
name: openshift-debug
description: Troubleshooting workflows for OpenShift 4.20 homelab. Diagnose PVC pending issues, pod crashes, CSI driver problems, storage network connectivity (VLAN 160), and operator failures. Use when debugging cluster issues or investigating stuck resources.
---

# OpenShift Debug

Troubleshooting toolkit for OpenShift 4.20 homelab operations. Focused on common failure modes in a hybrid blade infrastructure with TrueNAS storage backend.

## Prerequisites

- `oc` CLI configured with cluster admin access
- SSH access to cluster nodes (for network debugging)
- Access to TrueNAS management interface (172.16.160.100)

## Quick Diagnostics

### PVC Stuck in Pending

```bash
{baseDir}/scripts/check-pvc.sh <pvc-name> <namespace>
```

Checks:
- PVC status and events
- StorageClass configuration
- CSI driver logs (democratic-csi)
- TrueNAS NFS export status
- Storage network connectivity (VLAN 160)

### Pod CrashLoopBackOff

```bash
{baseDir}/scripts/check-pod.sh <pod-name> <namespace>
```

Analyzes:
- Pod events and status
- Container logs (current and previous)
- Resource limits and OOM kills
- Liveness/readiness probe failures
- Image pull issues

### Storage Network Connectivity

```bash
{baseDir}/scripts/check-storage-network.sh
```

Tests:
- VLAN 160 routing from all nodes
- TrueNAS reachability (172.16.160.100)
- Node 4 hybrid NIC configuration
- NFS mount accessibility

### Democratic-CSI Driver

```bash
{baseDir}/scripts/check-democratic-csi.sh
```

Reviews:
- Controller and node driver pod status
- Recent logs from provisioner
- Image tag (must be `next` for TrueNAS 25.10)
- CSI driver registration

## Common Issues & Solutions

### Issue 1: PVC Pending - CSI Driver Can't Reach TrueNAS

**Symptoms:**
- PVC stuck in `Pending` state
- CSI logs show: `connection refused 172.16.160.100`
- No recent provisions succeeding

**Root Cause:**
- VLAN 160 storage network routing issue
- Most common on Node 4 (hybrid 2-port blade)
- Tagged VLAN 160 not configured on eno2

**Diagnosis:**
```bash
./scripts/check-storage-network.sh
```

**Resolution:**
```bash
# From Node 4 (if affected)
oc debug node/<node4-name>
chroot /host

# Check VLAN interface
ip addr show eno2.160

# Expected: 172.16.160.x IP assigned
# If missing: VLAN tag not configured

# Test connectivity
ping -c 3 172.16.160.100
curl -k https://172.16.160.100/api/v2.0/system/info
```

**Fix:**
```bash
# Persistent fix: NetworkManager connection for VLAN
nmcli con add type vlan con-name eno2.160 ifname eno2.160 dev eno2 id 160
nmcli con mod eno2.160 ipv4.addresses 172.16.160.x/24
nmcli con mod eno2.160 ipv4.method manual
nmcli con up eno2.160
```

### Issue 2: Democratic-CSI Image Tag Mismatch

**Symptoms:**
- PVC provisions failing with API errors
- CSI logs show: `unsupported API endpoint` or `404 Not Found`
- TrueNAS version: 25.10 (Fangtooth)

**Root Cause:**
- TrueNAS 25.10 changed API paths
- Democratic-CSI `latest` or versioned tags use old API
- Must use `next` tag for Fangtooth compatibility

**Diagnosis:**
```bash
./scripts/check-democratic-csi.sh
# Look for image tag in output
```

**Resolution:**
```yaml
# Update driver Deployment/DaemonSet
image: docker.io/democraticcsi/democratic-csi:next

# Example patch
oc patch deployment -n democratic-csi democratic-csi-controller \
  --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"democraticcsi/democratic-csi:next"}]'
```

### Issue 3: LVM Operator Deadlock (Stale Thin Pools)

**Symptoms:**
- LVM VolumeGroup stuck in `Pending` state
- LVMS operator logs show thin pool errors
- PVC creation on `lvms-vg1` StorageClass fails

**Root Cause:**
- Stale LVM metadata from previous cluster
- Thin pools not cleaned up properly
- Operator can't initialize new VG

**Diagnosis:**
```bash
# Check VolumeGroup status
oc get lvmvolumegroup -n openshift-storage

# Check operator logs
oc logs -n openshift-storage -l app=lvms-operator --tail=100 | grep -i "thin\|error"

# Node-level check (run on each node)
oc debug node/<node-name>
chroot /host
lvs | grep thin
```

**Resolution:**
```bash
# From each node with stale thin pools
oc debug node/<node-name>
chroot /host

# List thin pools
lvs

# Remove stale thin pools (DESTRUCTIVE - backup first)
lvremove /dev/<vg-name>/<thin-pool-name>

# Restart LVMS operator
oc delete pod -n openshift-storage -l app=lvms-operator
```

**Prevention:**
- Clean LVM metadata before cluster reinstall
- Use hardware `by-path` IDs with `optionalPaths` for blade hot-swap tolerance

### Issue 4: Pod CrashLoop - Missing Mount Propagation

**Symptoms:**
- Media apps (Plex, Jellyfin, *arr stack) crash immediately
- Logs show: `mount point does not exist` or `permission denied`
- Rclone sidecar can't mount FUSE filesystem

**Root Cause:**
- Container runtime doesn't propagate FUSE mounts from sidecar
- Missing `mountPropagation: Bidirectional` on shared volume
- Parent `/mnt/media` directory not created

**Diagnosis:**
```bash
./scripts/check-pod.sh <pod-name> <namespace>
# Look for mount-related errors in logs
```

**Resolution:**
```yaml
# Add to Pod spec
spec:
  containers:
    - name: plex
      volumeMounts:
        - name: media
          mountPath: /mnt/media
          mountPropagation: Bidirectional  # Required for FUSE
    - name: rclone
      volumeMounts:
        - name: media
          mountPath: /mnt/media
          mountPropagation: Bidirectional
      securityContext:
        privileged: true  # FUSE requires CAP_SYS_ADMIN
  volumes:
    - name: media
      emptyDir: {}
```

**Pattern:**
- All media apps with Rclone sidecars need this
- Parent mount must be `emptyDir` with Bidirectional propagation
- Sidecar mounts FUSE inside the shared emptyDir

### Issue 5: Operator Pod Not Running

**Symptoms:**
- Operator-managed resources stuck (e.g., VirtualMachine, TektonPipeline)
- Operator pod in CrashLoop or Pending
- No reconciliation happening

**Diagnosis:**
```bash
# List operators
oc get csv -A

# Check operator pods
oc get pods -n <operator-namespace> -l control-plane=controller-manager

# Get events
oc get events -n <operator-namespace> --sort-by='.lastTimestamp'

# Check logs
oc logs -n <operator-namespace> <operator-pod> --previous
```

**Common Causes:**
1. **Image pull failure**: Check pull secret, rate limits
2. **RBAC issues**: Verify ServiceAccount permissions
3. **API compatibility**: Operator version vs. OpenShift version
4. **Resource limits**: Operator OOMKilled, increase limits

**Resolution:**
```bash
# Restart operator
oc delete pod -n <operator-namespace> -l control-plane=controller-manager

# If persistent, check CRD status
oc get crd | grep <operator-name>

# Validate CRD
oc get crd <crd-name> -o yaml | grep -A 10 status
```

## Troubleshooting Workflows

### Workflow 1: New PVC Won't Provision

**Checklist:**
1. ✅ Verify PVC is in `Pending` state
   ```bash
   oc get pvc -n <namespace>
   ```

2. ✅ Check PVC events
   ```bash
   oc describe pvc <pvc-name> -n <namespace>
   ```
   - Look for: `ProvisioningFailed`, `connection refused`, `timeout`

3. ✅ Validate StorageClass exists
   ```bash
   oc get sc truenas-nfs
   ```

4. ✅ Check CSI driver health
   ```bash
   ./scripts/check-democratic-csi.sh
   ```

5. ✅ Test storage network
   ```bash
   ./scripts/check-storage-network.sh
   ```

6. ✅ Verify TrueNAS status
   ```bash
   curl -k https://172.16.160.100/api/v2.0/system/info
   ```

7. ✅ Review CSI logs for specific error
   ```bash
   oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=50
   ```

### Workflow 2: Pod Crashing on Startup

**Checklist:**
1. ✅ Get pod status
   ```bash
   oc get pod <pod-name> -n <namespace>
   ```

2. ✅ Check pod events
   ```bash
   oc describe pod <pod-name> -n <namespace>
   ```
   - Look for: `OOMKilled`, `ImagePullBackOff`, `CrashLoopBackOff`

3. ✅ View container logs
   ```bash
   oc logs <pod-name> -n <namespace> --previous
   ```

4. ✅ Check resource limits
   ```bash
   oc get pod <pod-name> -n <namespace> -o yaml | grep -A 10 resources
   ```

5. ✅ Verify probes
   ```bash
   oc get pod <pod-name> -n <namespace> -o yaml | grep -A 5 Probe
   ```

6. ✅ Test liveness/readiness endpoints
   ```bash
   oc debug pod/<pod-name> -n <namespace>
   curl localhost:<port><path>
   ```

7. ✅ Check image availability
   ```bash
   oc get pod <pod-name> -n <namespace> -o yaml | grep image:
   podman pull <image>
   ```

### Workflow 3: Storage Network Unreachable

**Checklist:**
1. ✅ Identify affected node
   ```bash
   oc get nodes
   ```

2. ✅ Check node network interfaces
   ```bash
   oc debug node/<node-name>
   chroot /host
   ip addr show | grep -A 2 "eno2\|160"
   ```

3. ✅ Test TrueNAS connectivity
   ```bash
   ping -c 3 172.16.160.100
   curl -k https://172.16.160.100/api/v2.0/system/info
   ```

4. ✅ Verify VLAN configuration
   ```bash
   ip link show eno2.160
   # If missing: VLAN not configured
   ```

5. ✅ Check routing table
   ```bash
   ip route | grep 172.16.160
   ```

6. ✅ Test NFS mount manually
   ```bash
   showmount -e 172.16.160.100
   mount -t nfs 172.16.160.100:/mnt/tank/test /mnt
   ```

7. ✅ Verify firewall rules
   ```bash
   iptables -L -n | grep 172.16.160
   ```

## Node-Specific Debugging

### Node 2 & 3 (4-Port Blades)

**Network Layout:**
- eno1: Machine network (172.16.100.x)
- eno2: Storage network (172.16.160.x) - 10G dedicated
- eno3: Workload network (172.16.130.x) - 10G dedicated

**Common Issues:**
- Rare - clean network separation
- If eno2 down: Check cable, switch port, NIC status

**Debug:**
```bash
oc debug node/<node-2-or-3>
chroot /host

# Check interface status
ip link show eno2
nmcli con show eno2

# Test bandwidth
iperf3 -c 172.16.160.100 -p 5201
```

### Node 4 (2-Port Blade)

**Network Layout:**
- eno1: Machine network (172.16.100.x)
- eno2: **Hybrid** - Native VLAN 130 (Workload), Tagged VLAN 160 (Storage)

**Common Issues:**
- VLAN 160 tag not configured on eno2
- Bandwidth contention (1G shared between workload and storage)
- Switch VLAN trunk not configured

**Debug:**
```bash
oc debug node/<node-4>
chroot /host

# Check VLAN subinterface
ip link show eno2.160

# Expected output:
# eno2.160@eno2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
#     link/ether XX:XX:XX:XX:XX:XX

# If missing, create it:
nmcli con add type vlan con-name eno2.160 ifname eno2.160 dev eno2 id 160
nmcli con mod eno2.160 ipv4.addresses 172.16.160.x/24
nmcli con mod eno2.160 ipv4.method manual
nmcli con up eno2.160

# Test storage access
ping 172.16.160.100
curl -k https://172.16.160.100/api/v2.0/pool
```

**Performance Note:**
- Node 4 is bandwidth-limited (1G)
- Avoid scheduling storage-heavy workloads here
- Use node affinity to prefer Node 2/3 for media apps

## Helper Scripts

All scripts are located in `{baseDir}/scripts/` and include:
- Usage help with `--help` or no args
- Color-coded output (errors, warnings, info, success)
- Exit codes (0 = success, 1 = error)

### check-pvc.sh

Diagnose PVC provisioning issues.

**Usage:**
```bash
./scripts/check-pvc.sh <pvc-name> <namespace>
```

**Checks:**
- PVC status and events
- StorageClass configuration
- CSI driver pod health
- CSI provisioner logs
- Storage network connectivity

### check-pod.sh

Diagnose pod crash and startup issues.

**Usage:**
```bash
./scripts/check-pod.sh <pod-name> <namespace>
```

**Analyzes:**
- Pod status and events
- Current and previous container logs
- Resource limits (CPU/memory)
- Liveness/readiness probe configuration
- Image pull status

### check-storage-network.sh

Test storage network connectivity from all nodes.

**Usage:**
```bash
./scripts/check-storage-network.sh
```

**Tests:**
- Node-to-TrueNAS connectivity (ICMP, HTTPS, NFS)
- VLAN 160 interface configuration
- Node 4 hybrid NIC status
- NFS export availability

### check-democratic-csi.sh

Review democratic-csi driver status and logs.

**Usage:**
```bash
./scripts/check-democratic-csi.sh
```

**Reports:**
- Controller and node driver pod status
- Image tag (warns if not `next` for TrueNAS 25.10)
- Recent provisioner logs
- CSI driver registration
- StorageClass configuration

## Quick Reference

### Key IP Addresses

| Service | IP | VLAN | Notes |
|---------|-----|------|-------|
| TrueNAS | 172.16.160.100 | 160 | Storage backend |
| Node 2 Storage | 172.16.160.2 | 160 | 10G dedicated |
| Node 3 Storage | 172.16.160.3 | 160 | 10G dedicated |
| Node 4 Storage | 172.16.160.4 | 160 | 1G shared (tagged) |

### Key Namespaces

| Namespace | Purpose |
|-----------|---------|
| democratic-csi | NFS CSI driver |
| openshift-storage | LVMS operator |
| openshift-adp | Velero backup |
| openshift-cnv | OpenShift Virtualization |

### Common Log Locations

```bash
# CSI driver
oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=100

# LVMS operator
oc logs -n openshift-storage -l app=lvms-operator --tail=100

# Kubelet (node-level)
oc debug node/<node-name>
chroot /host
journalctl -u kubelet --since "1 hour ago"

# Container runtime
oc debug node/<node-name>
chroot /host
journalctl -u crio --since "1 hour ago"
```

## When to Use This Skill

Load this skill when:
- User mentions "PVC stuck", "pending", "won't provision"
- User reports "CrashLoopBackOff", "pod crashing", "container failing"
- User asks about "storage network", "VLAN 160", "can't reach TrueNAS"
- User mentions "democratic-csi", "CSI driver", "provisioner errors"
- User reports "operator not working", "CRD stuck", "reconciliation failed"
- User needs "debug steps", "troubleshooting", "cluster issues"

## Related Skills

- **sealed-secrets**: For debugging secret-related pod failures
- **gitops**: For ArgoCD sync issues and deployment failures

## Validation

Test the scripts:
```bash
cd /home/sigtom/wow-ocp/.pi/skills/openshift-debug
./scripts/check-democratic-csi.sh
./scripts/check-storage-network.sh
```

Expected: All checks pass or report known issues with remediation steps.
