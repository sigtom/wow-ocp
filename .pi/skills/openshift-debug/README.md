# OpenShift Debug Skill

Production-ready troubleshooting toolkit for OpenShift 4.20 homelab operations.

## Quick Start

```bash
# Diagnose PVC issues
./scripts/check-pvc.sh <pvc-name> <namespace>

# Diagnose pod crashes
./scripts/check-pod.sh <pod-name> <namespace>

# Check storage network (VLAN 160)
./scripts/check-storage-network.sh

# Check CSI driver status
./scripts/check-democratic-csi.sh
```

## Features

✅ **PVC Diagnostics**
- Status and events analysis
- StorageClass validation
- CSI driver log review
- Storage network connectivity test

✅ **Pod Crash Analysis**
- Current and previous logs
- Resource limits check
- Probe configuration review
- Image pull status
- Volume mount validation

✅ **Storage Network Testing**
- VLAN 160 connectivity per node
- TrueNAS reachability (172.16.160.100)
- Node 4 hybrid NIC configuration
- NFS export availability

✅ **CSI Driver Health**
- Controller and node pod status
- Image tag validation (must be `next` for TrueNAS 25.10)
- Recent provisioner logs
- Driver registration status

## Common Issues Covered

1. **PVC Stuck in Pending**
   - CSI driver can't reach TrueNAS (VLAN 160 routing)
   - Image tag mismatch (TrueNAS 25.10 requires `next`)
   - NFS export not configured

2. **Pod CrashLoopBackOff**
   - OOMKilled (resource limits)
   - Missing mount propagation (FUSE/Rclone)
   - Image pull failures
   - Liveness probe failures

3. **Storage Network Issues**
   - VLAN 160 not tagged on Node 4 eno2
   - TrueNAS service down
   - Switch trunk not configured

4. **LVM Operator Deadlock**
   - Stale thin pools from previous cluster
   - VolumeGroup stuck in Pending

## Infrastructure Context

### Network Layout

| Node | Type | Storage Interface | Storage IP |
|------|------|-------------------|------------|
| Node 2 | 4-port | eno2 (10G dedicated) | 172.16.160.2 |
| Node 3 | 4-port | eno2 (10G dedicated) | 172.16.160.3 |
| Node 4 | 2-port | eno2.160 (1G tagged) | 172.16.160.4 |

**TrueNAS:** 172.16.160.100 (VLAN 160)

### Known Issues

1. **TrueNAS 25.10 API Changes**
   - Democratic-csi must use `next` image tag
   - Versioned tags not compatible with Fangtooth API

2. **Node 4 Hybrid NIC**
   - VLAN 160 must be manually tagged on eno2
   - 1G bandwidth bottleneck (avoid heavy workloads)

3. **FUSE Mount Propagation**
   - Media apps with Rclone sidecars need `Bidirectional` propagation
   - Parent `/mnt/media` must be `emptyDir`

## Documentation

- **Full Guide:** [SKILL.md](SKILL.md)
- **Examples:** [examples/](examples/)
- **References:** [references/](references/)

## Validation

Test the scripts:
```bash
./scripts/check-democratic-csi.sh
./scripts/check-storage-network.sh
```

Expected: All checks pass or report known issues with remediation steps.
