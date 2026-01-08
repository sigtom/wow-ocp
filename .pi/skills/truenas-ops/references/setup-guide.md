# TrueNAS Scale + OpenShift Storage Setup Guide

Complete configuration reference for Democratic CSI NFS storage with TrueNAS Scale 25.10.

## Environment

- **Cluster:** OpenShift 4.20 Compact 3-Node (Dell FC630 Blades)
- **Storage Backend:** TrueNAS Scale 25.10 ("Fangtooth")
- **Driver:** Democratic CSI (NFS)
- **Date:** December 2025

## Table of Contents

1. [Preparation & Permissions](#1-preparation--permissions)
2. [Democratic CSI Installation](#2-democratic-csi-installation)
3. [Snapshot Configuration](#3-snapshot-configuration)
4. [OpenShift Virtualization Optimization](#4-openshift-virtualization-optimization)
5. [Verification Commands](#5-verification-commands)
6. [Troubleshooting](#6-troubleshooting)

---

## 1. Preparation & Permissions

The CSI driver requires privileged access to mount NFS shares on the host nodes. OpenShift uses Security Context Constraints (SCC) to control this.

### Create Namespace

```bash
oc create ns democratic-csi
```

### Configure SCC (Privileged Access)

We explicitly granted the `privileged` SCC to the service accounts that the Helm chart creates. This allows the driver to modify the host's `/var/lib/kubelet` directory.

```bash
# Allow the controller to manage volumes
oc adm policy add-scc-to-user privileged \
  -z truenas-nfs-democratic-csi-controller \
  -n democratic-csi

# Allow the node driver to mount shares on the host
oc adm policy add-scc-to-user privileged \
  -z truenas-nfs-democratic-csi-node \
  -n democratic-csi
```

**Why Privileged?**
- The CSI node driver must mount NFS shares directly on the host
- It modifies `/var/lib/kubelet/pods/<pod-uid>/volumes`
- This requires `hostPath` and `privileged` container capabilities

---

## 2. Democratic CSI Installation

We used the democratic-csi Helm chart.

**Critical Override:** Because TrueNAS Scale 25.10 changed the system info API, standard driver versions fail. We mandated the use of the `next` image tag for compatibility.

### Helm Setup

```bash
helm repo add democratic-csi https://democratic-csi.github.io/charts/
helm repo update
```

### Configuration (truenas-nfs-values.yaml)

Key settings applied in the values file:

#### Driver Identification
```yaml
csiDriver:
  name: truenas-nfs  # Custom name to distinguish it
```

#### Image Tags (CRITICAL for TrueNAS 25.10)
```yaml
controller:
  driver:
    image: democraticcsi/democratic-csi:next  # NOT latest or versioned
node:
  driver:
    image: democraticcsi/democratic-csi:next  # NOT latest or versioned
```

#### Sidecar Versions
Updated to stable versions:
```yaml
csiProxy:
  image: democraticcsi/csi-grpc-proxy:v0.5.6

controller:
  externalProvisioner:
    image: registry.k8s.io/sig-storage/csi-provisioner:v5.2.0
  externalSnapshotter:
    image: registry.k8s.io/sig-storage/csi-snapshotter:v8.2.0
  externalResizer:
    image: registry.k8s.io/sig-storage/csi-resizer:v1.12.0

node:
  driverRegistrar:
    image: registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.12.0
```

#### OpenShift Specifics
```yaml
node:
  rbac:
    openshift:
      privileged: true  # Enable OpenShift SCC
  kubeletHostPath: /var/lib/kubelet  # OpenShift kubelet location
```

#### ZFS Configuration
```yaml
driver:
  config:
    driver: freenas-nfs
    instance_id: truenas-nfs
    httpConnection:
      protocol: https
      host: 172.16.160.100
      port: 443
      allowInsecure: true
      apiKey: <your-api-key>
    
    zfs:
      datasetParentName: wow-ts10TB/ocp-nfs-volumes/v
      detachedSnapshotsDatasetParentName: wow-ts10TB/ocp-nfs-volumes/s
      datasetEnableQuotas: true
      datasetEnableReservation: false
      datasetPermissionsMode: "0777"
      datasetPermissionsUser: root
      datasetPermissionsGroup: root
    
    nfs:
      shareHost: 172.16.160.100
      shareAlldirs: false
      shareAllowedHosts: []
      shareAllowedNetworks:
        - 172.16.160.0/24  # Storage network
      shareMaprootUser: root
      shareMaprootGroup: root
```

### Deployment Command

```bash
helm upgrade --install truenas-nfs democratic-csi/democratic-csi \
  --namespace democratic-csi \
  --values truenas-nfs-values.yaml
```

### Verify Installation

```bash
# Check pods
oc get pods -n democratic-csi
# Expected: 1 controller (4/4) + 3 node pods (4/4) - all Running

# Check CSI driver registration
oc get csidriver truenas-nfs

# Check storage class
oc get sc truenas-nfs
```

---

## 3. Snapshot Configuration

The Helm chart enables the snapshot software (sidecar), but does not create the Kubernetes `VolumeSnapshotClass` by default. We created this manually.

### The "Identity Crisis" Fix

**Problem:** The default driver name is `org.democratic-csi.nfs`, but our config named it `truenas-nfs`. The snapshot class must match the driver name reported in the logs, or snapshots will hang forever.

**Solution:** Explicitly set the driver name in the VolumeSnapshotClass to match our `csiDriver.name` setting.

### VolumeSnapshotClass YAML (snapshot-setup.yaml)

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: truenas-nfs-snap
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: truenas-nfs  # CRITICAL: Must match 'csiDriver.name' from values.yaml
deletionPolicy: Delete
parameters:
  detachedSnapshots: "false"
```

### Apply

```bash
oc apply -f snapshot-setup.yaml
```

### Verify

```bash
# Check snapshot class exists
oc get volumesnapshotclass
# Expected: truenas-nfs-snap with driver truenas-nfs

# Check if it's the default
oc get volumesnapshotclass truenas-nfs-snap -o yaml | grep is-default-class
# Expected: "true"

# Verify driver name matches
oc get csidriver
# Should show: truenas-nfs
```

### Test Snapshot Creation

```bash
# Create a test PVC first
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: truenas-nfs
EOF

# Wait for PVC to bind
oc get pvc test-pvc
# Status should be: Bound

# Create a snapshot
cat <<EOF | oc apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
spec:
  volumeSnapshotClassName: truenas-nfs-snap
  source:
    persistentVolumeClaimName: test-pvc
EOF

# Check snapshot status
oc get volumesnapshot test-snapshot
# ReadyToUse should be: true (within 30 seconds)

# Verify on TrueNAS
ssh root@172.16.160.100 "zfs list -t snapshot | grep ocp-nfs"
# Should show ZFS snapshot

# Clean up
oc delete volumesnapshot test-snapshot
oc delete pvc test-pvc
```

---

## 4. OpenShift Virtualization Optimization (Fast Cloning)

By default, OpenShift's Containerized Data Importer (CDI) creates VMs by copying data over the network (slow). We patched the storage profile to tell CDI that our storage supports CSI-native cloning (ZFS clones).

**Result:** VM cloning and provisioning from templates happens effectively instantly on the storage array, rather than copying gigabytes over the LAN.

### The Patch (storage-profile-patch.yaml)

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
  # Forces CDI to offload cloning to TrueNAS (ZFS Clone)
  cloneStrategy: csi-clone
```

### Apply

```bash
oc apply -f storage-profile-patch.yaml
```

### Verify

```bash
# Check storage profile
oc get storageprofile truenas-nfs -o yaml

# Expected Status:
# status:
#   claimPropertySets:
#   - accessModes:
#     - ReadWriteMany
#   cloneStrategy: csi-clone
#   provisioner: truenas-nfs
#   snapshotClass: truenas-nfs-snap
#   storageClass: truenas-nfs
```

### Test VM Cloning

```bash
# Clone a VM (should be instant)
virtctl clone vm source-vm --target-name cloned-vm

# Watch progress
oc get dv -w
# Should complete in <30 seconds for instant ZFS clone
```

**Before patch:** 5-15 minutes (network copy)  
**After patch:** 10-30 seconds (ZFS instant clone)

---

## 5. Verification Commands

Use these commands to verify the health of the storage stack.

### Check Pods

```bash
oc get pods -n democratic-csi
# Expected: All pods 1/1 (or 4/4 sidecars) Running
#
# Example output:
# NAME                                                     READY   STATUS
# truenas-nfs-democratic-csi-controller-6d4b8f9c8c-abcd   4/4     Running
# truenas-nfs-democratic-csi-node-abc123                  4/4     Running
# truenas-nfs-democratic-csi-node-def456                  4/4     Running
# truenas-nfs-democratic-csi-node-ghi789                  4/4     Running
```

### Verify Snapshot Class

```bash
oc get volumesnapshotclass
# Expected: Name 'truenas-nfs-snap' with driver 'truenas-nfs'

oc get volumesnapshotclass truenas-nfs-snap -o yaml
# Verify:
# - driver: truenas-nfs
# - deletionPolicy: Delete
# - annotation: is-default-class: "true"
```

### Verify CDI Optimization

```bash
oc get storageprofile truenas-nfs -o yaml
# Expected Status:
# cloneStrategy: csi-clone
# snapshotClass: truenas-nfs-snap
```

### Check CSI Driver Registration

```bash
oc get csidriver
# Should show: truenas-nfs

oc describe csidriver truenas-nfs
# Verify:
# - attachRequired: false
# - podInfoOnMount: true
# - volumeLifecycleModes: Persistent
```

### Check Storage Class

```bash
oc get sc truenas-nfs
# Should show provisioner: truenas-nfs

oc describe sc truenas-nfs
# Verify:
# - ReclaimPolicy: Delete
# - VolumeBindingMode: Immediate
# - AllowVolumeExpansion: true
```

### Test PVC Creation

```bash
# Create test PVC
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: health-check-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Mi
  storageClassName: truenas-nfs
EOF

# Wait for binding
oc get pvc health-check-pvc -w
# Should show: Bound within 10-30 seconds

# Verify on TrueNAS
ssh root@172.16.160.100 "zfs list | grep health-check"

# Clean up
oc delete pvc health-check-pvc
```

---

## 6. Troubleshooting

### Common Issues and Solutions

#### Issue: Pods Not Running

**Symptom:** CSI pods stuck in `CrashLoopBackOff` or `Error`

**Diagnosis:**
```bash
oc get pods -n democratic-csi
oc describe pod -n democratic-csi <pod-name>
oc logs -n democratic-csi <pod-name> -c democratic-csi-driver
```

**Common Causes:**
1. SCC not granted
2. Wrong image tag (not `next`)
3. TrueNAS unreachable (VLAN 160 issue)
4. Invalid API key

**Solution:**
```bash
# Re-apply SCC
oc adm policy add-scc-to-user privileged -z truenas-nf-democratic-csi-controller -n democratic-csi
oc adm policy add-scc-to-user privileged -z truenas-nfs-democratic-csi-node -n democratic-csi

# Check image tag
oc get deployment -n democratic-csi -o yaml | grep image:
# Should show: democraticcsi/democratic-csi:next

# Test TrueNAS connectivity
oc debug node/<node-name>
chroot /host
ping 172.16.160.100
curl -k https://172.16.160.100/api/v2.0/system/info
```

#### Issue: API Version Mismatch

**Symptom:** Logs show "unsupported API endpoint" or "404 Not Found"

**Cause:** Using `latest` or versioned tag instead of `next` for TrueNAS 25.10

**Solution:**
```bash
# Update Helm values to use next tag
helm upgrade truenas-nfs democratic-csi/democratic-csi \
  --namespace democratic-csi \
  --values truenas-nfs-values.yaml \
  --set controller.driver.image=democraticcsi/democratic-csi:next \
  --set node.driver.image=democraticcsi/democratic-csi:next
```

#### Issue: Snapshot Hangs

**Symptom:** VolumeSnapshot stuck in Pending, never becomes ReadyToUse

**Cause:** Driver name mismatch between VolumeSnapshotClass and CSI driver

**Solution:**
```bash
# Check mismatch
oc get volumesnapshotclass truenas-nf-snap -o jsonpath='{.driver}'
oc get csidriver -o name | grep truenas

# They must match! If not, recreate snapshot class
oc delete volumesnapshotclass truenas-nfs-snap
oc apply -f snapshot-setup.yaml  # With correct driver name
```

#### Issue: VM Cloning is Slow

**Symptom:** VM cloning takes 5-15 minutes

**Cause:** StorageProfile not configured for CSI cloning

**Solution:**
```bash
# Apply CDI optimization
oc apply -f storage-profile-patch.yaml

# Verify
oc get storageprofile truenas-nfs -o jsonpath='{.spec.cloneStrategy}'
# Should output: csi-clone
```

---

## Additional Resources

### TrueNAS ZFS Commands

```bash
# SSH to TrueNAS
ssh root@172.16.160.100

# List all volumes
zfs list | grep ocp-nfs-volumes/v

# List snapshots
zfs list -t snapshot | grep ocp-nfs-volumes/s

# Check pool capacity
zfs list -o space wow-ts10TB

# Check compression ratios
zfs get compressratio wow-ts10TB/ocp-nfs-volumes

# Snapshot usage
zfs list -t snapshot -o name,used,refer
```

### Helm Values Reference

For complete Helm values reference, see the democratic-csi chart documentation:
https://github.com/democratic-csi/charts/tree/master/stable/democratic-csi

### Related Documentation

- Democratic CSI: https://github.com/democratic-csi/democratic-csi
- TrueNAS Scale API: https://www.truenas.com/docs/scale/api/
- OpenShift Virtualization CDI: https://docs.openshift.com/container-platform/4.20/virt/storage/virt-cloning-vms.html

---

**Last Updated:** December 2025  
**Cluster:** wow-ocp (3-node compact)  
**Storage:** TrueNAS Scale 25.10 "Fangtooth"
