# TrueNAS Operations Skill

Management and troubleshooting toolkit for TrueNAS Scale 25.10 ("Fangtooth") NFS storage with Democratic CSI.

## Quick Start

```bash
# Check overall storage health
./scripts/check-storage-health.sh

# Check ZFS capacity
./scripts/check-truenas-capacity.sh

# View CSI logs
./scripts/check-csi-logs.sh --errors-only

# Test storage network
./scripts/test-storage-network.sh
```

## Features

✅ **Comprehensive Health Checks**
- CSI pods (controller + nodes)
- VolumeSnapshotClass configuration
- StorageProfile CDI optimization
- Storage network connectivity

✅ **Capacity Management**
- ZFS pool usage
- Dataset breakdown
- Snapshot overhead
- Compression ratios

✅ **Log Analysis**
- Controller and node driver logs
- Error filtering
- Common issue detection

✅ **Network Testing**
- VLAN 160 connectivity
- Per-node interface validation
- TrueNAS API access
- Optional bandwidth tests

## Infrastructure

- **TrueNAS:** 172.16.160.100 (Scale 25.10 "Fangtooth")
- **Pool:** wow-ts10TB
- **CSI Driver:** Democratic CSI (image tag: `next`)
- **StorageClass:** truenas-nfs (RWX)
- **Network:** VLAN 160 (172.16.160.0/24)

## Known Issues

1. **TrueNAS 25.10 API Changes**
   - MUST use `next` image tag
   - Versioned tags will fail

2. **Snapshot Driver Mismatch**
   - VolumeSnapshotClass driver must be `truenas-nfs`
   - Default `org.democratic-csi.nfs` will cause hangs

3. **Node 4 VLAN Configuration**
   - Requires eno2.160 (tagged)
   - Must be manually configured

4. **CDI Cloning**
   - StorageProfile needs `cloneStrategy: csi-clone`
   - Otherwise VM cloning is slow (network copy)

## Documentation

- **Full Guide**: [SKILL.md](SKILL.md)
- **Setup Reference**: [references/setup-guide.md](references/setup-guide.md)

## Validation

```bash
./scripts/check-storage-health.sh
```

Expected: All checks pass (exit code 0)
