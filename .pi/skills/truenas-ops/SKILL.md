---
name: truenas-ops
description: TrueNAS Scale 25.10 storage operations for OpenShift homelab. Manage Democratic CSI NFS storage, check ZFS capacity, troubleshoot PVC provisioning, verify storage network (VLAN 160), and monitor snapshot classes. Use when debugging storage issues or checking TrueNAS health.
---

# TrueNAS Operations

Management and troubleshooting toolkit for TrueNAS Scale 25.10 ("Fangtooth") NFS storage backend with Democratic CSI driver.

## Prerequisites

- SSH access to TrueNAS (172.16.160.100)
- `oc` CLI with cluster admin access
- Democratic CSI deployed in `democratic-csi` namespace
- Access to storage network (VLAN 160)

## Quick Health Check

```bash
{baseDir}/scripts/check-storage-health.sh
```

Verifies:
- Democratic CSI pods running
- VolumeSnapshotClass configured correctly
- StorageProfile CDI optimization
- CSI driver registration

## Infrastructure Overview

### TrueNAS Backend
- **IP:** 172.16.160.100 (VLAN 160)
- **Version:** TrueNAS Scale 25.10 ("Fangtooth")
- **Pool:** wow-ts10TB
- **Datasets:**
  - `wow-ts10TB/ocp-nfs-volumes/v` - Dynamic volumes
  - `wow-ts10TB/ocp-nfs-volumes/s` - Snapshots
  - `wow-ts10TB/media` - 11TB media library (static PV)

### Storage Network (VLAN 160)
- **Network:** 172.16.160.0/24
- **Node 2/3:** Dedicated 10G NIC (eno2)
- **Node 4:** Hybrid 1G NIC (eno2.160 tagged)
- **Purpose:** Isolated NFS traffic

### Democratic CSI Driver
- **Namespace:** democratic-csi
- **Driver Name:** truenas-nfs (custom)
- **Image Tag:** `next` (required for Fangtooth API)
- **StorageClass:** truenas-nfs
- **Access Mode:** ReadWriteMany (RWX)
- **Snapshots:** Enabled via ZFS

## Common Operations

### Check ZFS Capacity

```bash
{baseDir}/scripts/check-truenas-capacity.sh
```

Shows:
- Pool usage and available space
- Dataset sizes
- Snapshot overhead
- Compression ratios

### Check CSI Logs

```bash
{baseDir}/scripts/check-csi-logs.sh [--controller|--node]
```

Tails logs from:
- Controller pod (provisioner, snapshotter)
- Node pods (mount operations)
- Filters for errors and warnings

### Test Storage Network

```bash
{baseDir}/scripts/test-storage-network.sh
```

Tests:
- VLAN 160 connectivity from all nodes
- TrueNAS API reachability
- NFS showmount access
- Bandwidth (optional)

## Troubleshooting Workflows

### Issue 1: PVC Stuck in Pending

**Symptoms:**
- PVC shows `Pending` for >5 minutes
- No volume provisioned on TrueNAS
- Events show provisioning errors

**Diagnosis:**
```bash
# Check overall health
./scripts/check-storage-health.sh

# Check CSI logs for errors
./scripts/check-csi-logs.sh --controller

# Verify storage network
./scripts/test-storage-network.sh

# Check TrueNAS directly
ssh root@172.16.160.100 "zfs list | grep ocp-nfs"
```

**Common Causes:**

1. **CSI Driver Not Running**
   ```bash
   oc get pods -n democratic-csi
   # If not Running, check logs
   oc describe pod -n democratic-csi -l app=democratic-csi-nfs
   ```

2. **Wrong Image Tag**
   - TrueNAS 25.10 requires `next` tag
   - Check: `oc get deployment -n democratic-csi -o yaml | grep image:`
   - Should show: `democraticcsi/democratic-csi:next`

3. **Storage Network Unreachable**
   - VLAN 160 misconfigured on Node 4
   - See openshift-debug skill: `./check-storage-network.sh`

4. **TrueNAS API Authentication**
   ```bash
   # Get API key from secret
   oc get secret -n democratic-csi truenas-nfs-democratic-csi-driver-config \
     -o jsonpath='{.data.driver-config-file\.yaml}' | base64 -d | grep apiKey
   
   # Test API access
   curl -k -H "Authorization: Bearer <api-key>" \
     https://172.16.160.100/api/v2.0/system/info
   ```

5. **ZFS Pool Full**
   ```bash
   ./scripts/check-truenas-capacity.sh
   # If >80%, clean up or expand pool
   ```

**Resolution:**
```bash
# Restart CSI controller
oc delete pod -n democratic-csi -l app=democratic-csi-nfs

# Force PVC retry
oc delete pvc <name> -n <namespace>
oc apply -f pvc.yaml
```

### Issue 2: Snapshot Class Not Working

**Symptoms:**
- VolumeSnapshot stuck in Pending
- VM cloning fails or is slow
- Snapshot class exists but not used

**Diagnosis:**
```bash
# Check snapshot class
oc get volumesnapshotclass
# Should show: truenas-nfs-snap with driver truenas-nfs

# Check if default
oc get volumesnapshotclass truenas-nfs-snap -o yaml | grep is-default-class

# Check CSI driver name match
oc get csidriver
# Should show: truenas-nfs
```

**Common Causes:**

1. **Driver Name Mismatch ("Identity Crisis")**
   - Snapshot class driver must match `csiDriver.name` from Helm values
   - Default is `org.democratic-csi.nfs` but we use `truenas-nfs`
   
   ```bash
   # Check mismatch
   SNAPSHOT_DRIVER=$(oc get volumesnapshotclass truenas-nfs-snap -o jsonpath='{.driver}')
   CSI_DRIVER=$(oc get csidriver -o name | grep truenas)
   
   echo "Snapshot class driver: ${SNAPSHOT_DRIVER}"
   echo "CSI driver: ${CSI_DRIVER}"
   # Must match!
   ```

2. **Snapshot Class Missing**
   ```bash
   # Create if missing
   cat <<EOF | oc apply -f -
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshotClass
   metadata:
     name: truenas-nfs-snap
     annotations:
       snapshot.storage.kubernetes.io/is-default-class: "true"
   driver: truenas-nfs
   deletionPolicy: Delete
   parameters:
     detachedSnapshots: "false"
   EOF
   ```

**Resolution:**
```bash
# Verify everything after fix
./scripts/check-storage-health.sh

# Test snapshot creation
cat <<EOF | oc apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snap
spec:
  volumeSnapshotClassName: truenas-nfs-snap
  source:
    persistentVolumeClaimName: <existing-pvc>
EOF

# Check status
oc get volumesnapshot test-snap
# Should show: ReadyToUse=true
```

### Issue 3: VM Cloning is Slow

**Symptoms:**
- VM cloning takes 5-15 minutes
- CDI copies data instead of ZFS cloning
- Cloning uses network bandwidth

**Diagnosis:**
```bash
# Check StorageProfile
oc get storageprofile truenas-nfs -o yaml

# Expected:
# status:
#   cloneStrategy: csi-clone
#   snapshotClass: truenas-nfs-snap
```

**Root Cause:**
- CDI not configured for CSI smart cloning
- Falls back to host-assisted cloning (slow)

**Resolution:**
```bash
# Patch StorageProfile
cat <<EOF | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: StorageProfile
metadata:
  name: truenas-nfs
spec:
  claimPropertySets:
  - accessModes:
    - ReadWriteMany
    volumeMode: Filesystem
  cloneStrategy: csi-clone
EOF

# Verify
oc get storageprofile truenas-nfs -o jsonpath='{.spec.cloneStrategy}'
# Should output: csi-clone

# Test: Clone a VM - should be instant (<30s)
```

### Issue 4: Node Can't Mount NFS

**Symptoms:**
- Pod stuck in ContainerCreating
- Events show: `MountVolume.SetUp failed`
- Node logs: `connection refused` or `timeout`

**Diagnosis:**
```bash
# Check storage network
./scripts/test-storage-network.sh

# Check from specific node
oc debug node/<node-name>
chroot /host

# Test NFS mount
showmount -e 172.16.160.100
mount -t nfs 172.16.160.100:/mnt/wow-ts10TB/ocp-nfs-volumes/v/<vol-name> /mnt
```

**Common Causes:**

1. **VLAN 160 Not Configured (Node 4)**
   ```bash
   oc debug node/<node4>
   chroot /host
   
   # Check VLAN interface
   ip link show eno2.160
   # If missing, configure it
   nmcli con add type vlan con-name eno2.160 ifname eno2.160 dev eno2 id 160
   nmcli con mod eno2.160 ipv4.addresses 172.16.160.4/24
   nmcli con mod eno2.160 ipv4.method manual
   nmcli con up eno2.160
   ```

2. **NFS Service Down on TrueNAS**
   ```bash
   ssh root@172.16.160.100 "systemctl status nfs-server"
   # If not running
   ssh root@172.16.160.100 "systemctl start nfs-server"
   ```

3. **Export Not Created**
   ```bash
   # Check TrueNAS exports
   ssh root@172.16.160.100 "exportfs -v"
   
   # Should show /mnt/wow-ts10TB/ocp-nfs-volumes/v
   ```

**Resolution:**
```bash
# Restart node driver pod on affected node
NODE_POD=$(oc get pods -n democratic-csi -o wide | grep <node-name> | awk '{print $1}')
oc delete pod -n democratic-csi ${NODE_POD}
```

### Issue 5: Out of Space

**Symptoms:**
- PVC creation fails with quota errors
- TrueNAS dashboard shows pool full
- ZFS reports ENOSPC

**Diagnosis:**
```bash
./scripts/check-truenas-capacity.sh

# Or directly on TrueNAS
ssh root@172.16.160.100 "zfs list -o space"
```

**Common Causes:**

1. **Snapshots Consuming Space**
   ```bash
   # Check snapshot usage
   ssh root@172.16.160.100 "zfs list -t snapshot -o name,used,refer"
   
   # Delete old snapshots
   ssh root@172.16.160.100 "zfs list -t snapshot | grep old | awk '{print \$1}' | xargs -n1 zfs destroy"
   ```

2. **Unused PVCs**
   ```bash
   # Find PVCs not bound to pods
   oc get pvc -A --no-headers | while read ns name status vol rest; do
     if [[ "$status" == "Bound" ]]; then
       PODS=$(oc get pods -n $ns -o json | jq -r ".items[].spec.volumes[]?.persistentVolumeClaim.claimName" 2>/dev/null | grep "^${name}$")
       if [[ -z "$PODS" ]]; then
         echo "Unused: $ns/$name"
       fi
     fi
   done
   ```

3. **Large Datasets**
   ```bash
   # Find biggest consumers
   ssh root@172.16.160.100 "zfs list -o name,used -s used | head -20"
   ```

**Resolution:**
```bash
# Option 1: Clean up
# Delete unused PVCs
oc delete pvc <name> -n <namespace>

# Option 2: Expand pool (if hardware available)
# Add vdevs or expand existing vdevs in TrueNAS UI

# Option 3: Adjust quotas
# Reduce PVC sizes in manifests
# Set quotas on ZFS datasets
```

## Configuration Reference

### Critical Settings

**Image Tag (MUST be `next` for TrueNAS 25.10):**
```yaml
# In democratic-csi Helm values
csiDriver:
  name: truenas-nfs
controller:
  driver:
    image: democraticcsi/democratic-csi:next
node:
  driver:
    image: democraticcsi/democratic-csi:next
```

**SCC Permissions:**
```bash
oc adm policy add-scc-to-user privileged \
  -z truenas-nfs-democratic-csi-controller -n democratic-csi
oc adm policy add-scc-to-user privileged \
  -z truenas-nfs-democratic-csi-node -n democratic-csi
```

**Snapshot Class:**
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: truenas-nfs-snap
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: truenas-nfs  # MUST match csiDriver.name
deletionPolicy: Delete
parameters:
  detachedSnapshots: "false"
```

**CDI Optimization:**
```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: StorageProfile
metadata:
  name: truenas-nfs
spec:
  claimPropertySets:
  - accessModes:
    - ReadWriteMany
    volumeMode: Filesystem
  cloneStrategy: csi-clone  # Enables instant VM cloning
```

## Helper Scripts

### check-storage-health.sh

Comprehensive health check for the entire storage stack.

**Usage:**
```bash
./scripts/check-storage-health.sh
```

**Checks:**
- Democratic CSI pods (controller + nodes)
- VolumeSnapshotClass configuration
- StorageProfile CDI settings
- CSI driver registration
- Storage network connectivity

**Exit Codes:**
- 0: All healthy
- 1: Critical issues found
- 2: Warnings but operational

### check-truenas-capacity.sh

Check ZFS pool and dataset capacity.

**Usage:**
```bash
./scripts/check-truenas-capacity.sh [--detailed]
```

**Shows:**
- Pool usage percentage
- Available space
- Dataset sizes
- Snapshot overhead
- Compression ratios

**Options:**
- `--detailed`: Include per-dataset breakdown

### check-csi-logs.sh

Tail CSI driver logs with error filtering.

**Usage:**
```bash
./scripts/check-csi-logs.sh [--controller|--node] [--errors-only]
```

**Options:**
- `--controller`: Only show controller logs
- `--node`: Only show node driver logs
- `--errors-only`: Filter for error/warning messages

### test-storage-network.sh

Test VLAN 160 connectivity from all cluster nodes.

**Usage:**
```bash
./scripts/test-storage-network.sh [--bandwidth]
```

**Tests:**
- ICMP ping to TrueNAS
- NFS showmount availability
- API connectivity
- Per-node interface configuration

**Options:**
- `--bandwidth`: Run iperf3 test (requires iperf3 on TrueNAS)

## Best Practices

### Do's ✅

1. **Always use `next` image tag for TrueNAS 25.10**
2. **Monitor pool capacity** - alert at 80%
3. **Regular snapshot cleanup** - automate with cron
4. **Test storage network** after node changes
5. **Use CSI cloning** for VM templates (instant)
6. **Static PV for media library** - don't dynamically provision 11TB

### Don'ts ❌

1. **Don't use `latest` tag** - API incompatible with Fangtooth
2. **Don't fill pool >90%** - ZFS performance degrades
3. **Don't skip SCC permissions** - driver won't work
4. **Don't mismatch driver names** - snapshots will hang
5. **Don't provision media library dynamically** - use existing dataset

## Verification Commands

```bash
# Quick health check
./scripts/check-storage-health.sh

# Pod status
oc get pods -n democratic-csi

# Snapshot class
oc get volumesnapshotclass truenas-nfs-snap

# Storage profile
oc get storageprofile truenas-nfs -o yaml

# CSI driver
oc get csidriver truenas-nfs

# Storage class
oc get sc truenas-nfs

# Recent PVCs
oc get pvc -A --sort-by=.metadata.creationTimestamp | tail -10

# Capacity
./scripts/check-truenas-capacity.sh

# Network
./scripts/test-storage-network.sh
```

## When to Use This Skill

Load this skill when:
- User mentions "TrueNAS", "NFS storage", "democratic-csi"
- User reports "PVC pending", "provisioning failed"
- User asks about "storage capacity", "ZFS"
- User mentions "snapshot not working", "VM cloning slow"
- User needs to "check storage network", "VLAN 160"
- User asks about "storage health", "CSI logs"

## Related Skills

- **openshift-debug**: For broader PVC/pod debugging
- **argocd-ops**: For deploying storage-related manifests via GitOps

## Quick Troubleshooting Guide

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| PVC Pending | CSI driver down | `oc delete pod -n democratic-csi -l app=democratic-csi-nfs` |
| "Connection refused" | VLAN 160 down | `./scripts/test-storage-network.sh` |
| Snapshot hangs | Driver name mismatch | Check VolumeSnapshotClass driver matches CSI driver |
| VM clone slow | CDI not using CSI | Patch StorageProfile with `cloneStrategy: csi-clone` |
| Out of space | Pool full | `./scripts/check-truenas-capacity.sh` |
| API errors | Wrong image tag | Update to `next` tag and restart pods |

## Documentation

See [references/setup-guide.md](references/setup-guide.md) for complete setup documentation including:
- Initial Helm deployment
- All configuration YAMLs
- SCC setup details
- Troubleshooting history
