# OpenShift Debug Quick Reference

Fast lookup guide for common commands and fixes.

## Emergency Commands

### Restart CSI Driver
```bash
oc delete pod -n democratic-csi -l app=democratic-csi-nfs
```

### Restart LVMS Operator
```bash
oc delete pod -n openshift-storage -l app=lvms-operator
```

### Force PVC Re-provision
```bash
oc delete pvc <name> -n <namespace>
oc apply -f pvc.yaml
```

### Debug Node Network
```bash
oc debug node/<node-name>
chroot /host
ip addr show
ping 172.16.160.100
```

## Quick Diagnostics

### PVC Stuck
```bash
oc describe pvc <name> -n <namespace> | grep -A 10 Events
oc get events -n <namespace> --field-selector involvedObject.name=<pvc-name>
```

### Pod Crashing
```bash
oc logs <pod> -n <namespace> --previous
oc describe pod <pod> -n <namespace> | grep -A 5 Events
```

### CSI Logs
```bash
oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=50
```

### Storage Network Test
```bash
oc debug node/<node> -- chroot /host ping -c 3 172.16.160.100
```

## Fix Patterns

### Node 4 VLAN 160 Configuration
```bash
oc debug node/worker-2
chroot /host
nmcli con add type vlan con-name eno2.160 ifname eno2.160 dev eno2 id 160
nmcli con mod eno2.160 ipv4.addresses 172.16.160.4/24
nmcli con mod eno2.160 ipv4.method manual
nmcli con up eno2.160
exit
exit
```

### Update Democratic-CSI to 'next' Tag
```bash
oc patch deployment -n democratic-csi democratic-csi-controller \
  --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"democraticcsi/democratic-csi:next"}]'
oc delete pod -n democratic-csi -l app=democratic-csi-nfs
```

### Add Bidirectional Mount Propagation (FUSE)
```yaml
volumeMounts:
  - name: media
    mountPath: /mnt/media
    mountPropagation: Bidirectional
```

### Remove Stale LVM Thin Pool
```bash
oc debug node/<node>
chroot /host
lvremove /dev/<vg>/<thin-pool> -y
exit
exit
oc delete pod -n openshift-storage -l app=lvms-operator
```

## Key IP Addresses

| Resource | IP | VLAN | Notes |
|----------|-----|------|-------|
| TrueNAS | 172.16.160.100 | 160 | Storage backend |
| Node 2 Storage | 172.16.160.2 | 160 | 10G dedicated |
| Node 3 Storage | 172.16.160.3 | 160 | 10G dedicated |
| Node 4 Storage | 172.16.160.4 | 160 | 1G tagged |

## Key Namespaces

| Namespace | Purpose | Critical Pods |
|-----------|---------|---------------|
| democratic-csi | NFS CSI driver | controller, node-* |
| openshift-storage | LVMS operator | lvms-operator |
| openshift-adp | Velero backup | velero |
| openshift-cnv | Virtualization | virt-operator |

## Common Log Locations

```bash
# CSI driver
oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=100

# LVMS operator
oc logs -n openshift-storage -l app=lvms-operator --tail=100

# Kubelet (node-level)
oc debug node/<node> -- chroot /host journalctl -u kubelet --since "1 hour ago"

# CRI-O runtime
oc debug node/<node> -- chroot /host journalctl -u crio --since "1 hour ago"
```

## Error Pattern Matching

| Error Message | Likely Cause | Fix Script |
|---------------|--------------|------------|
| connection refused 172.16.160.100 | Storage network down | check-storage-network.sh |
| unsupported API endpoint | CSI tag mismatch | check-democratic-csi.sh |
| OOMKilled | Memory limit too low | check-pod.sh |
| MountVolume.SetUp failed | PVC not bound | check-pvc.sh |
| ImagePullBackOff | Image not found | check-pod.sh |
| thin pool already exists | Stale LVM metadata | Manual cleanup |

## Resource Limits Guide

| Workload Type | Requests | Limits |
|---------------|----------|--------|
| Small (sidecar) | 100m CPU, 128Mi RAM | 500m CPU, 512Mi RAM |
| Medium (API) | 500m CPU, 512Mi RAM | 2 CPU, 2Gi RAM |
| Large (database) | 2 CPU, 2Gi RAM | 4 CPU, 8Gi RAM |
| Media (Plex) | 2 CPU, 4Gi RAM | 8 CPU, 16Gi RAM |

## Probe Configuration Examples

### HTTP Health Check
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

### TCP Socket Check
```yaml
livenessProbe:
  tcpSocket:
    port: 5432
  initialDelaySeconds: 30
  periodSeconds: 10
```

### Exec Command
```yaml
livenessProbe:
  exec:
    command:
      - /bin/sh
      - -c
      - pgrep -f myapp
  initialDelaySeconds: 10
  periodSeconds: 5
```

## TrueNAS API Quick Checks

```bash
# System info
curl -k https://172.16.160.100/api/v2.0/system/info

# NFS service status
curl -k https://172.16.160.100/api/v2.0/service/nfs

# Pool status
curl -k https://172.16.160.100/api/v2.0/pool

# NFS exports
showmount -e 172.16.160.100
```

## Node-Specific Commands

### Check Interface Status
```bash
oc debug node/<node>
chroot /host
ip addr show eno2
ip addr show eno2.160  # Node 4 only
nmcli con show
```

### Test Storage Bandwidth
```bash
oc debug node/<node>
chroot /host
# Install if needed: yum install iperf3
iperf3 -c 172.16.160.100 -p 5201 -t 10
```

### Check Routing
```bash
oc debug node/<node>
chroot /host
ip route show
ip route get 172.16.160.100
```

## Verification Checklist

After fixing issues, verify:

- [ ] PVCs in `Bound` state: `oc get pvc -A | grep -v Bound`
- [ ] Pods in `Running` state: `oc get pods -A | grep -v Running`
- [ ] No recent errors in CSI logs: `oc logs -n democratic-csi -l app=democratic-csi-nfs --tail=50`
- [ ] Storage network reachable: `curl -k https://172.16.160.100/api/v2.0/system/info`
- [ ] No node pressure: `oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.conditions[?(@.status=="True")].type}{"\n"}{end}'`

## When to Escalate

1. **TrueNAS hardware failure** → Check TrueNAS console, disk health
2. **Switch port down** → Check switch logs, physical cables
3. **Node hardware failure** → Check IPMI logs, chassis health
4. **Persistent API errors** → Check TrueNAS system logs, database integrity
5. **Cluster-wide issues** → Check control plane logs, etcd health

## Support Contacts

- TrueNAS Documentation: https://www.truenas.com/docs/
- Democratic-CSI: https://github.com/democratic-csi/democratic-csi
- OpenShift: https://docs.openshift.com/
- LVMS: https://docs.openshift.com/container-platform/4.20/storage/persistent_storage/persistent-storage-lvms.html
