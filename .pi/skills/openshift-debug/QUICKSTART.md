# OpenShift Debug - Quick Start

## 30-Second Workflow

```bash
# Diagnose a stuck PVC
.pi/skills/openshift-debug/scripts/check-pvc.sh my-pvc my-namespace

# Diagnose a crashing pod
.pi/skills/openshift-debug/scripts/check-pod.sh my-pod my-namespace

# Check storage network
.pi/skills/openshift-debug/scripts/check-storage-network.sh

# Check CSI driver
.pi/skills/openshift-debug/scripts/check-democratic-csi.sh
```

## Common Scenarios

### PVC Won't Provision

```bash
# Quick diagnosis
./scripts/check-pvc.sh plex-config media

# Output tells you:
# ✗ CSI driver can't reach TrueNAS at 172.16.160.100
# ⚠ Storage network (VLAN 160) may be misconfigured

# Fix it
./scripts/check-storage-network.sh
# Follow the output to configure VLAN 160 on Node 4
```

### Pod Crashing

```bash
# Quick diagnosis
./scripts/check-pod.sh plex-deployment-abc123 media

# Output tells you:
# ✗ Container was OOMKilled
# ⚠ Increase memory limits in pod spec

# Or:
# ✗ Liveness probe failing
# → Check application health endpoint
```

### Storage Network Down

```bash
# Quick diagnosis
./scripts/check-storage-network.sh

# Output shows per-node connectivity
# Identifies VLAN 160 issues on Node 4
# Tests TrueNAS reachability
```

### CSI Driver Issues

```bash
# Quick diagnosis
./scripts/check-democratic-csi.sh

# Output tells you:
# ✗ Image tag: latest (should be 'next' for TrueNAS 25.10)
# Provides patch command to fix
```

## Key Commands

### Restart CSI Driver
```bash
oc delete pod -n democratic-csi -l app=democratic-csi-nfs
```

### Fix Node 4 VLAN 160
```bash
oc debug node/worker-2
chroot /host
nmcli con add type vlan con-name eno2.160 ifname eno2.160 dev eno2 id 160
nmcli con mod eno2.160 ipv4.addresses 172.16.160.4/24
nmcli con mod eno2.160 ipv4.method manual
nmcli con up eno2.160
```

### Update CSI to 'next' Tag
```bash
oc patch deployment -n democratic-csi democratic-csi-controller \
  --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"democraticcsi/democratic-csi:next"}]'
```

## Key Infrastructure

| Component | Location | Notes |
|-----------|----------|-------|
| TrueNAS | 172.16.160.100 | Storage backend (VLAN 160) |
| Node 2/3 Storage | 172.16.160.2/3 | 10G dedicated (eno2) |
| Node 4 Storage | 172.16.160.4 | 1G tagged VLAN 160 (eno2.160) |

## Known Issues

1. **TrueNAS 25.10 API**: Requires democratic-csi `next` tag
2. **Node 4 VLAN**: Must manually configure eno2.160 interface
3. **FUSE Mounts**: Need `mountPropagation: Bidirectional`
4. **LVM Thin Pools**: Clean up stale pools before reinstall

## Documentation

- **Full Guide**: [SKILL.md](SKILL.md)
- **Examples**: [examples/example-workflow.md](examples/example-workflow.md)
- **Quick Ref**: [references/quick-reference.md](references/quick-reference.md)

## Validation

```bash
# Test the skill
./test-skill.sh

# Expected: All 10 tests pass ✓
```
