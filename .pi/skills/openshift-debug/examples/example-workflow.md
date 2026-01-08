# Example Troubleshooting Workflows

Real-world scenarios and step-by-step debugging procedures.

## Scenario 1: New PVC Won't Provision

**Situation:** You create a PVC for a new Plex deployment, but it stays in `Pending` state.

**Steps:**

```bash
# 1. Check PVC status
oc get pvc plex-config -n media
# Output: NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
#         plex-config   Pending                                      truenas-nfs    5m

# 2. Run comprehensive PVC check
cd /home/sigtom/wow-ocp/.pi/skills/openshift-debug
./scripts/check-pvc.sh plex-config media

# Output will show:
# - PVC events (ProvisioningFailed)
# - StorageClass validation (truenas-nfs exists)
# - CSI driver logs showing: "connection refused 172.16.160.100"
```

**Root Cause Found:** CSI driver can't reach TrueNAS on storage network.

```bash
# 3. Check storage network
./scripts/check-storage-network.sh

# Output shows Node 4 missing VLAN 160 interface
```

**Fix:**

```bash
# 4. Configure VLAN 160 on Node 4
oc debug node/worker-2  # Node 4
chroot /host

nmcli con add type vlan con-name eno2.160 ifname eno2.160 dev eno2 id 160
nmcli con mod eno2.160 ipv4.addresses 172.16.160.4/24
nmcli con mod eno2.160 ipv4.method manual
nmcli con up eno2.160

# Verify
ping 172.16.160.100
# SUCCESS: TrueNAS reachable

exit
exit

# 5. Restart CSI controller to retry
oc delete pod -n democratic-csi -l app=democratic-csi-nfs
```

**Result:** PVC provisions successfully within 30 seconds.

---

## Scenario 2: Plex Pod in CrashLoopBackOff

**Situation:** Plex pod with Rclone sidecar crashes immediately after starting.

**Steps:**

```bash
# 1. Check pod status
oc get pod plex-7d4b8f9c-xk2l9 -n media
# Output: NAME                   READY   STATUS             RESTARTS   AGE
#         plex-7d4b8f9c-xk2l9   0/2     CrashLoopBackOff   5          3m

# 2. Run pod diagnostic
cd /home/sigtom/wow-ocp/.pi/skills/openshift-debug
./scripts/check-pod.sh plex-7d4b8f9c-xk2l9 media

# Output shows:
# - Container 'plex' logs: "mount: /mnt/media: permission denied"
# - No Bidirectional mount propagation found
```

**Root Cause Found:** Missing `mountPropagation: Bidirectional` for FUSE mounts.

**Fix:**

Update Deployment manifest:

```yaml
spec:
  containers:
    - name: plex
      volumeMounts:
        - name: media
          mountPath: /mnt/media
          mountPropagation: Bidirectional  # Add this
    - name: rclone
      volumeMounts:
        - name: media
          mountPath: /mnt/media
          mountPropagation: Bidirectional  # Add this
      securityContext:
        privileged: true  # Required for FUSE
  volumes:
    - name: media
      emptyDir: {}  # Shared mount point
```

**Result:** Pod starts successfully, Rclone mounts FUSE filesystem, Plex accesses media.

---

## Scenario 3: Democratic-CSI API Errors After TrueNAS Upgrade

**Situation:** After upgrading TrueNAS to 25.10 (Fangtooth), all new PVCs fail to provision.

**Steps:**

```bash
# 1. Check CSI driver
cd /home/sigtom/wow-ocp/.pi/skills/openshift-debug
./scripts/check-democratic-csi.sh

# Output shows:
# - Image: democraticcsi/democratic-csi:latest
# - Logs: "unsupported API endpoint" and "404 Not Found"
# - WARNING: TrueNAS 25.10 requires 'next' tag
```

**Root Cause Found:** TrueNAS 25.10 changed API paths, `latest` tag uses old API.

**Fix:**

```bash
# 2. Update image tag to 'next'
oc patch deployment -n democratic-csi democratic-csi-controller \
  --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"democraticcsi/democratic-csi:next"}]'

# 3. Restart controller
oc delete pod -n democratic-csi -l app=democratic-csi-nfs

# 4. Verify
./scripts/check-democratic-csi.sh
# Output: Image: democraticcsi/democratic-csi:next
#         Logs: No errors, provisioning successful
```

**Result:** New PVCs provision successfully with updated driver.

---

## Scenario 4: LVMS VolumeGroup Stuck in Pending

**Situation:** LVM storage not available, VolumeGroup stuck after cluster reinstall.

**Steps:**

```bash
# 1. Check VolumeGroup status
oc get lvmvolumegroup -n openshift-storage
# Output: NAME          STATUS
#         lvms-vg1      Pending

# 2. Check operator logs
oc logs -n openshift-storage -l app=lvms-operator --tail=50
# Output shows: "thin pool already exists" error

# 3. Check node-level LVM
oc debug node/worker-0
chroot /host

lvs | grep thin
# Output: lvms-thin-pool  vg1  twi-a-t---  100.00g (stale)
```

**Root Cause Found:** Stale thin pools from previous cluster installation.

**Fix:**

```bash
# 4. Remove stale thin pools (on each node)
oc debug node/worker-0
chroot /host

# BACKUP FIRST - THIS IS DESTRUCTIVE
lvremove /dev/vg1/lvms-thin-pool -y

# Verify
lvs
# Output: No thin pools

exit
exit

# Repeat for worker-1 and worker-2

# 5. Restart LVMS operator
oc delete pod -n openshift-storage -l app=lvms-operator

# 6. Wait for reconciliation
oc get lvmvolumegroup -n openshift-storage --watch
# Output: lvms-vg1  Ready
```

**Result:** LVM storage available, PVCs can be provisioned on `lvms-vg1` StorageClass.

---

## Scenario 5: All Nodes Can't Reach TrueNAS

**Situation:** Entire storage network down, all PVC provisions failing.

**Steps:**

```bash
# 1. Check storage network
cd /home/sigtom/wow-ocp/.pi/skills/openshift-debug
./scripts/check-storage-network.sh

# Output shows:
# - All nodes: "Cannot ping TrueNAS at 172.16.160.100"
# - VLAN 160 interfaces configured correctly
```

**Root Cause Found:** TrueNAS service down or network infrastructure issue.

**Diagnosis:**

```bash
# 2. Check TrueNAS directly
# Login to TrueNAS: https://172.16.160.100
# Dashboard shows: NFS service STOPPED

# Or from switch (if accessible):
# show vlan 160
# Output: VLAN 160 not configured on uplink trunk
```

**Fix Option A (TrueNAS service):**

```bash
# Via TrueNAS WebUI:
# Services → NFS → Start
# Services → NFS → Start Automatically (enable)

# Verify
curl -k https://172.16.160.100/api/v2.0/service/nfs
# Output: {"state": "RUNNING"}
```

**Fix Option B (Switch VLAN):**

```bash
# Via switch CLI (example for Cisco):
interface GigabitEthernet1/0/1
 switchport trunk allowed vlan add 160
 switchport mode trunk
```

**Result:** Storage network restored, PVCs provision successfully.

---

## Quick Reference: Decision Tree

```
PVC Won't Provision
├─ Is StorageClass valid?
│  ├─ No → Create/fix StorageClass
│  └─ Yes → Continue
├─ Are CSI pods running?
│  ├─ No → Check CSI deployment, restart pods
│  └─ Yes → Continue
├─ Can nodes reach TrueNAS (172.16.160.100)?
│  ├─ No → Check VLAN 160, Node 4 config, switch trunk
│  └─ Yes → Continue
├─ Is TrueNAS NFS service running?
│  ├─ No → Start NFS service on TrueNAS
│  └─ Yes → Continue
└─ Check CSI logs for specific error

Pod CrashLoopBackOff
├─ Check previous logs (--previous)
├─ Is it OOMKilled?
│  ├─ Yes → Increase memory limits
│  └─ No → Continue
├─ Are probes failing?
│  ├─ Yes → Fix probe config or app issue
│  └─ No → Continue
├─ Volume mount issues?
│  ├─ Yes → Check PVC, add mountPropagation if FUSE
│  └─ No → Continue
└─ Check application-specific logs

Storage Network Down
├─ Test from each node: ping 172.16.160.100
├─ Check VLAN 160 interface on each node
├─ Verify TrueNAS service running
├─ Check switch VLAN trunk configuration
└─ Review firewall rules (iptables)
```

---

## Pro Tips

1. **Always start with the script diagnostics** - they check 80% of common issues automatically.

2. **Check recent events** - most issues show up in events before logs:
   ```bash
   oc get events -n <namespace> --sort-by='.lastTimestamp' | tail -20
   ```

3. **Node 4 is special** - always verify VLAN 160 tagged interface after any network changes.

4. **CSI driver restarts quickly** - don't hesitate to restart pods if config changed:
   ```bash
   oc delete pod -n democratic-csi -l app=democratic-csi-nfs
   ```

5. **TrueNAS version matters** - 25.10 needs `next` tag, older versions use `latest`.

6. **Save debug outputs** - redirect script output to files for later analysis:
   ```bash
   ./scripts/check-pvc.sh my-pvc media > /tmp/pvc-debug.txt 2>&1
   ```
