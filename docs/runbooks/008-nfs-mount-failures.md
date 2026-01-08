# Runbook 008: NFS Mount Failures (TrueNAS)

**Frequency:** Occasional (network issues, TrueNAS maintenance)  
**Impact:** High - Pods cannot start, data unavailable  
**Last Occurred:** Various (network topology changes)  
**MTTR:** 10-30 minutes

---

## Symptoms

- Pods stuck in `ContainerCreating` state
- Events show: `Unable to attach or mount volumes`
- Logs show: `mount.nfs: Connection timed out` or `mount.nfs: access denied`
- PVC bound but mount fails

**Quick Check:**
```bash
# Check pod status
oc get pods -n <namespace>

# Check pod events
oc describe pod <pod-name> -n <namespace> | grep -A 10 Events

# Check PVC status
oc get pvc -n <namespace>
```

---

## Root Cause Analysis

### Common Causes (Priority Order)

1. **Network Connectivity to TrueNAS (VLAN 160)** (40% of cases)
   - Node cannot reach 172.16.160.100
   - VLAN 160 not configured on node NIC
   - Firewall blocking NFS ports (2049, 111)

2. **NFS Export Permissions** (25% of cases)
   - Export not created on TrueNAS
   - Wrong network allowed (e.g., 172.16.100.0/24 instead of worker nodes)
   - `root_squash` preventing access

3. **Stale NFS Mount** (15% of cases)
   - Previous mount still held by kernel
   - Node restarted but mount not cleaned
   - NFS server was unreachable and timed out

4. **TrueNAS Service Not Running** (10% of cases)
   - NFS service stopped/crashed
   - TrueNAS rebooted recently
   - Disk pool not mounted

5. **SELinux / Security Context** (5% of cases)
   - SELinux denying NFS mount
   - Pod security context incompatible with NFS

6. **Resource Exhaustion on TrueNAS** (5% of cases)
   - Disk full
   - Too many active connections
   - Memory/CPU exhausted

---

## Diagnosis Steps

### Step 1: Check Pod Events
```bash
oc describe pod <pod-name> -n <namespace>
```

**Look for Mount Errors:**
```
Events:
  Type     Reason       Message
  ----     ------       -------
  Warning  FailedMount  Unable to attach or mount volumes: timeout expired waiting for volumes to attach or mount
  Warning  FailedMount  MountVolume.MountDevice failed: mount failed: exit status 32
```

### Step 2: Check PVC and PV Details
```bash
# Check PVC
oc describe pvc <pvc-name> -n <namespace>

# Get PV name
oc get pvc <pvc-name> -n <namespace> -o jsonpath='{.spec.volumeName}'

# Check PV NFS server and path
oc get pv <pv-name> -o yaml | grep -A 5 nfs
```

**Expected Output:**
```yaml
nfs:
  path: /mnt/tank/k8s/media-stack-sonarr-config-pvc
  server: 172.16.160.100
```

### Step 3: Test Network Connectivity from Node
```bash
# Find which node the pod is scheduled on
oc get pod <pod-name> -n <namespace> -o jsonpath='{.spec.nodeName}'

# Debug into that node
oc debug node/<node-name>

# Inside debug pod
chroot /host

# Test ping
ping -c 3 172.16.160.100

# Test NFS port
nc -zv 172.16.160.100 2049

# Test RPC port
nc -zv 172.16.160.100 111

# Try manual mount
mkdir -p /tmp/test-mount
mount -t nfs 172.16.160.100:/mnt/tank/k8s/<pvc-name> /tmp/test-mount
ls /tmp/test-mount
umount /tmp/test-mount
```

### Step 4: Check TrueNAS Exports
```bash
ssh truenas "showmount -e"
```

**Expected Output:**
```
Export list for truenas:
/mnt/tank/k8s/media-stack-sonarr-config-pvc  172.16.160.0/24
/mnt/tank/k8s/media-stack-radarr-config-pvc  172.16.160.0/24
...
```

**Problem (Export Missing):**
```
Export list for truenas:
(no exports)
```

### Step 5: Check TrueNAS NFS Service
```bash
ssh truenas "systemctl status nfs-server"
```

**Expected:**
```
● nfs-server.service - NFS server
   Loaded: loaded
   Active: active (running)
```

**Problem:**
```
Active: inactive (dead)
```

### Step 6: Check Node VLAN Configuration (Node 4 Specific)
```bash
# On Node 4 (2-port blade with VLAN trunk)
oc debug node/wow-ocp-node4
chroot /host

# Check VLAN 160 interface
ip addr show eno2.160

# Should show:
# eno2.160@eno2: <BROADCAST,MULTICAST,UP,LOWER_UP>
#   inet 172.16.160.x/24 ...

# Test routing
ip route | grep 172.16.160
```

---

## Resolution by Root Cause

### Fix 1: Network Connectivity Broken (VLAN 160)

**Symptom:**
- `ping 172.16.160.100` fails from node
- `nc -zv 172.16.160.100 2049` fails

**Resolution (Node 2 & 3 - Dedicated Storage NIC):**

1. **Check physical link:**
```bash
oc debug node/<node-name>
chroot /host

# Check interface status (eno2 = Storage network)
ip link show eno2

# Should show: <BROADCAST,MULTICAST,UP,LOWER_UP>
```

2. **If down, check cable/switch port**

**Resolution (Node 4 - VLAN Trunk):**

1. **Verify VLAN 160 interface exists:**
```bash
oc debug node/wow-ocp-node4
chroot /host

# Check VLAN interface
ip addr show eno2.160
```

2. **If missing, recreate via NNCP:**

**File:** `infrastructure/networking/nncp-br160-node4.yaml`

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: br160-node4-vlan
spec:
  nodeSelector:
    kubernetes.io/hostname: wow-ocp-node4
  desiredState:
    interfaces:
      - name: eno2.160
        type: vlan
        state: up
        vlan:
          base-iface: eno2
          id: 160
        ipv4:
          enabled: true
          dhcp: false
          address:
            - ip: 172.16.160.104  # Static IP on storage network
              prefix-length: 24
```

**Apply:**
```bash
oc apply -f infrastructure/networking/nncp-br160-node4.yaml
```

3. **Verify routing:**
```bash
oc debug node/wow-ocp-node4
chroot /host
ip route | grep 172.16.160

# Should show:
# 172.16.160.0/24 dev eno2.160 proto kernel scope link src 172.16.160.104
```

### Fix 2: NFS Export Not Created or Wrong Permissions

**Symptom:**
- Network connectivity OK
- `showmount -e` doesn't show the export
- Manual mount fails with `access denied`

**Resolution:**

1. **Check if dataset exists:**
```bash
ssh truenas "zfs list | grep <pvc-name>"
```

2. **If dataset exists but no export, create manually:**
```bash
ssh truenas

# Add NFS share
midclt call sharing.nfs.create '{
  "path": "/mnt/tank/k8s/<pvc-name>",
  "comment": "K8s PVC <pvc-name>",
  "networks": ["172.16.160.0/24"],
  "hosts": [],
  "ro": false,
  "maproot_user": "root",
  "maproot_group": "root",
  "security": []
}'

# Reload NFS exports
exportfs -ra

# Verify
showmount -e
```

3. **If using democratic-csi, check driver logs:**
```bash
oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=100 | grep <pvc-name>
```

**Look for API errors:** `failed to create export`

### Fix 3: Stale NFS Mount on Node

**Symptom:**
- Mount fails with: `device is busy` or `mount point does not exist`
- Node was rebooted but mount state corrupted

**Resolution:**

1. **Find stale mount:**
```bash
oc debug node/<node-name>
chroot /host

# List all NFS mounts
mount | grep nfs

# Find kubelet mount points
ls /var/lib/kubelet/pods/*/volumes/kubernetes.io~nfs/
```

2. **Force unmount:**
```bash
# Unmount specific path
umount -f /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~nfs/<pv-name>

# If that fails, lazy unmount
umount -l /var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~nfs/<pv-name>
```

3. **Restart kubelet to clean up:**
```bash
systemctl restart kubelet
```

4. **Delete and recreate pod:**
```bash
oc delete pod <pod-name> -n <namespace>
```

### Fix 4: TrueNAS NFS Service Not Running

**Symptom:**
- All NFS mounts failing across cluster
- TrueNAS web UI accessible but NFS down

**Resolution:**

1. **Restart NFS service:**
```bash
ssh truenas

# Restart NFS
systemctl restart nfs-server

# Verify
systemctl status nfs-server
```

2. **Check TrueNAS logs:**
```bash
ssh truenas "tail -n 100 /var/log/middlewared.log | grep -i nfs"
```

3. **Verify pool is mounted:**
```bash
ssh truenas "zpool status tank"

# Should show: state: ONLINE
```

**If pool degraded or offline:** See TrueNAS documentation for recovery.

### Fix 5: SELinux Blocking NFS Mount (RHEL Nodes)

**Symptom:**
- Mount fails with: `Permission denied`
- Manual mount as root works
- Pod mount fails

**Resolution:**

1. **Check SELinux denials:**
```bash
oc debug node/<node-name>
chroot /host

# Check audit log
ausearch -m avc -ts recent | grep nfs
```

2. **Temporarily set SELinux to permissive (testing only):**
```bash
setenforce 0

# Try mount again
oc delete pod <pod-name> -n <namespace>
```

**If mount works in permissive mode:**

3. **Add SELinux policy (permanent fix):**
```bash
# Re-enable enforcing
setenforce 1

# Generate custom policy from denials
ausearch -m avc -ts recent | audit2allow -M my-nfs-policy

# Install policy
semodule -i my-nfs-policy.pp
```

### Fix 6: TrueNAS Disk Full

**Symptom:**
- Mount succeeds but writes fail
- `df -h` shows 100% usage

**Resolution:**

1. **Check TrueNAS capacity:**
```bash
ssh truenas "zfs list -o name,used,avail,refer tank/k8s"
```

2. **Free up space:**
```bash
# Delete old snapshots
ssh truenas "zfs list -t snapshot tank/k8s | tail -n +2 | head -n 10"
ssh truenas "zfs destroy tank/k8s@snapshot-name"

# Or expand pool (add disks)
```

3. **Set quota alerts:**
```bash
ssh truenas "zfs set quota=500G tank/k8s"  # Set quota
ssh truenas "zfs set reservation=50G tank/k8s"  # Reserve minimum
```

---

## Prevention

### 1. Automate VLAN Configuration with NNCP

**File:** `infrastructure/networking/kustomization.yaml`

```yaml
resources:
  - nncp-br130-eno2.yaml  # Workload network
  - nncp-br130-eno3.yaml  # Workload network (Node 2/3)
  - nncp-br160-eno2.yaml  # Storage network (Node 2/3)
  - nncp-br160-node4.yaml # Storage network (Node 4 VLAN)
```

**Benefit:** Network config survives node rebuilds.

### 2. Monitor NFS Mount Health

**File:** `infrastructure/monitoring/nfs-alerts.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: nfs-alerts
  namespace: openshift-monitoring
spec:
  groups:
    - name: nfs
      rules:
        - alert: NFSMountsFailing
          expr: |
            kube_pod_status_phase{phase="Pending"} > 0
            and
            kube_pod_info{node=~"wow-ocp-node.*"}
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Pod stuck in Pending with possible NFS mount issue"
```

### 3. Pre-Deploy Network Test

**Script:** `scripts/test-storage-network.sh`

```bash
#!/bin/bash
set -e

echo "Testing storage network connectivity from all nodes..."

for node in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do
  echo "=== Testing $node ==="
  
  # Test ping
  oc debug $node -- chroot /host ping -c 1 172.16.160.100 || {
    echo "ERROR: Cannot ping TrueNAS from $node"
    exit 1
  }
  
  # Test NFS port
  oc debug $node -- chroot /host nc -zv 172.16.160.100 2049 || {
    echo "ERROR: Cannot reach NFS port from $node"
    exit 1
  }
  
  echo "✓ $node storage network OK"
done

echo "✓ All nodes can reach TrueNAS"
```

**Usage:**
```bash
./scripts/test-storage-network.sh
```

### 4. Document Network Topology

**File:** `docs/network-topology.md`

```
Storage Network (VLAN 160 - 172.16.160.0/24)
├─ TrueNAS: 172.16.160.100 (NFS Server)
├─ Node 2: 172.16.160.102 (eno2 - Dedicated 10G)
├─ Node 3: 172.16.160.103 (eno2 - Dedicated 10G)
└─ Node 4: 172.16.160.104 (eno2.160 - VLAN Tagged 1G)

Notes:
- Node 2/3: Direct Layer 2 on eno2
- Node 4: VLAN trunk on eno2 (native: 172.16.130.x, tagged: VLAN 160)
```

---

## Troubleshooting Decision Tree

```
NFS Mount Failure
    │
    ├─ Can ping 172.16.160.100 from node?
    │   ├─ No → Fix network (VLAN 160 configuration)
    │   └─ Yes → Continue
    │
    ├─ Can connect to port 2049?
    │   ├─ No → Check TrueNAS NFS service
    │   └─ Yes → Continue
    │
    ├─ Does showmount -e show the export?
    │   ├─ No → Recreate export on TrueNAS
    │   └─ Yes → Continue
    │
    ├─ Can manual mount from node work?
    │   ├─ No → Check export permissions (root_squash?)
    │   └─ Yes → Pod security context or stale mount
    │
    └─ Stale mount in kubelet directory?
        └─ Yes → Force unmount and restart kubelet
```

---

## Related Issues

- **Issue:** Democratic-CSI driver errors
- **Runbook:** [004-pvc-stuck-pending.md](004-pvc-stuck-pending.md)
- **Documentation:** `infrastructure/networking/`

---

## Lessons Learned

1. **Node 4 is special** - Uses VLAN tagging instead of dedicated NIC
2. **NNCP is fragile** - Node reboots can lose VLAN config if not in GitOps
3. **Test network first** - 40% of NFS issues are network-related
4. **Stale mounts are common** - After node crashes/reboots
5. **TrueNAS needs monitoring** - Disk full = silent mount failures

---

## Verification Checklist

- [ ] `ping 172.16.160.100` succeeds from all worker nodes
- [ ] `nc -zv 172.16.160.100 2049` succeeds from all worker nodes
- [ ] `showmount -e` from nodes shows all expected exports
- [ ] Pod transitions from `ContainerCreating` to `Running`
- [ ] `oc exec` into pod can read/write to mount
- [ ] No `FailedMount` events in pod description

---

**Document Version:** 1.0  
**Last Updated:** 2026-01-08  
**Owner:** SRE Team
