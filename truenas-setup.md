OpenShift + TrueNAS Scale NFS Storage Configuration
Date: Dec 2025  
Cluster: Compact 3-Node (FC630 Blades)  
Storage Backend: TrueNAS Scale 25.10 ("Fangtooth")  
Driver: Democratic CSI (NFS)  
This document details the configuration of the truenas-nfs StorageClass, Volume Snapshots, and optimizations for OpenShift Virtualization (CDI) to enable instant cloning.
1. Preparation & Permissions
The CSI driver requires privileged access to mount NFS shares on the host nodes. OpenShift uses Security Context Constraints (SCC) to control this.
Create Namespace
oc create ns democratic-csi
Configure SCC (Privileged Access)
We explicitly granted the privileged SCC to the service accounts that the Helm chart creates. This allows the driver to modify the host's /var/lib/kubelet directory.
# Allow the controller to manage volumes  
oc adm policy add-scc-to-user privileged -z truenas-nfs-democratic-csi-controller -n democratic-csi
# Allow the node driver to mount shares on the host  
oc adm policy add-scc-to-user privileged -z truenas-nfs-democratic-csi-node -n democratic-csi
2. Democratic CSI Installation
We used the democratic-csi Helm chart.
Critical Override: Because TrueNAS Scale 25.10 changed the system info API, standard driver versions fail. We mandated the use of the next image tag for compatibility.
Helm Setup
helm repo add democratic-csi [https://democratic-csi.github.io/charts/](https://democratic-csi.github.io/charts/)  
helm repo update
Configuration (truenas-nfs-values.yaml)
Key settings applied in the values file:
⦁	Driver Name: truenas-nfs (Custom name to distinguish it).
⦁	Image Tags: tag: next set for Controller, Node, and Driver containers.
⦁	Sidecars: Updated to stable versions (Provisioner v5.2.0, Snapshotter v8.2.0, etc.).
⦁	OpenShift Specifics: * rbac.openshift.privileged: true
⦁	kubeletHostPath: /var/lib/kubelet
⦁	ZFS Paths:
⦁	Parent: wow-ts10TB/ocp-nfs-volumes/v
⦁	Snapshots: wow-ts10TB/ocp-nfs-volumes/s
Deployment Command
helm upgrade --install truenas-nfs democratic-csi/democratic-csi \  
--namespace democratic-csi \  
--values truenas-nfs-values.yaml
3. Snapshot Configuration
The Helm chart enables the snapshot software (sidecar), but does not create the Kubernetes VolumeSnapshotClass by default. We created this manually.
The "Identity Crisis" Fix:  
The default driver name is org.democratic-csi.nfs, but our config named it truenas-nfs. The snapshot class must match the driver name reported in the logs, or snapshots will hang forever.
VolumeSnapshotClass YAML (snapshot-setup.yaml)
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
Apply
oc apply -f snapshot-setup.yaml
4. OpenShift Virtualization Optimization (Fast Cloning)
By default, OpenShift's Containerized Data Importer (CDI) creates VMs by copying data over the network (slow). We patched the storage profile to tell CDI that our storage supports CSI-native cloning (ZFS clones).
Result: VM cloning and provisioning from templates happens effectively instantly on the storage array, rather than copying gigabytes over the LAN.
The Patch (storage-profile-patch.yaml)
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
Apply
oc apply -f storage-profile-patch.yaml
5. Verification Commands
Use these commands to verify the health of the storage stack.
Check Pods:
oc get pods -n democratic-csi  
# Expected: All pods 1/1 (or 4/4 sidecars) Running
Verify Snapshot Class:
oc get volumesnapshotclass  
# Expected: Name 'truenas-nfs-snap' with driver 'truenas-nfs'
Verify CDI Optimization:
oc get storageprofile truenas-nfs -o yaml  
# Expected Status:  
# cloneStrategy: csi-clone  
# snapshotClass: truenas-nfs-snap
