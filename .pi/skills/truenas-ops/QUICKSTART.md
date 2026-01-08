# TrueNAS Operations - Quick Start

## 30-Second Health Check

```bash
cd /home/sigtom/wow-ocp
.pi/skills/truenas-ops/scripts/check-storage-health.sh
```

Expected: All checks pass (or minor warnings only)

## Common Tasks

### Check Capacity

```bash
./scripts/check-truenas-capacity.sh
```

Shows pool usage, datasets, and snapshots.

### View CSI Logs

```bash
# Show errors from all CSI pods
./scripts/check-csi-logs.sh --errors-only

# Controller only
./scripts/check-csi-logs.sh --controller --tail 100
```

### Test Storage Network

```bash
./scripts/test-storage-network.sh
```

Tests VLAN 160 connectivity from all nodes.

## Quick Fixes

### PVC Stuck Pending

```bash
# Check health
./scripts/check-storage-health.sh

# Check logs
./scripts/check-csi-logs.sh --controller --errors-only

# Restart CSI
oc delete pod -n democratic-csi -l app.kubernetes.io/name=democratic-csi
```

### Snapshot Not Working

```bash
# Check configuration
oc get volumesnapshotclass truenas-nfs-snap -o yaml

# Verify driver name matches
oc get csidriver
# Should show: truenas-nfs (must match snapshot class driver)
```

### VM Cloning Slow

```bash
# Check CDI optimization
oc get storageprofile truenas-nfs -o jsonpath='{.spec.cloneStrategy}'
# Should output: csi-clone

# If not, patch it
oc patch storageprofile truenas-nfs --type=merge -p '{"spec":{"cloneStrategy":"csi-clone"}}'
```

## Key Facts

- **TrueNAS IP:** 172.16.160.100 (VLAN 160)
- **Image Tag:** MUST be `next` for TrueNAS 25.10
- **Driver Name:** truenas-nfs (custom, not default)
- **Snapshot Class:** truenas-nfs-snap (driver must match)
- **Node 4:** Requires VLAN 160 tagged (eno2.160)

## Documentation

- **Full Guide**: [SKILL.md](SKILL.md)
- **Setup Reference**: [references/setup-guide.md](references/setup-guide.md)
