---
name: media-stack
description: Deploy and manage hybrid cloud media applications with rclone sidecar pattern. Use for adding media apps (Plex, Sonarr, Radarr, etc.), implementing cloud storage mounts (Zurg/TorBox), troubleshooting FUSE mount propagation, and checking media mount status across pods.
---

# Media Stack Operations

Deployment and troubleshooting toolkit for the OpenShift Hybrid-Converged Media Stack. Implements the sidecar rclone pattern to enable FUSE mount propagation across nodes for cloud storage (Real-Debrid via Zurg, TorBox) combined with local TrueNAS storage.

## Architecture Overview

The media stack is divided into **4 zones**:

- **Zone 1: Cloud Gateway** - Zurg, Rclone, rdt-client, Riven (cloud connectivity)
- **Zone 2: Managers** - Sonarr, Radarr, SABnzbd, Bazarr (library management)
- **Zone 3: Player** - Plex with rclone sidecars (content delivery)
- **Zone 4: Discovery** - Overseerr (user requests and trending)

**Storage Topology:**
- **Local (TrueNAS)**: `/mnt/media/archive` (permanent 4K storage), `/mnt/media/stream` (symlinks)
- **Cloud (Virtual)**: `/mnt/media/zurg/__all__` (Real-Debrid), `/mnt/media/torbox/torrents` (TorBox)

See `{baseDir}/references/architecture.md` for detailed design.

## Prerequisites

- OpenShift 4.20+ cluster with privileged SCC access
- TrueNAS NFS storage (RWX PVC)
- Sealed secrets for rclone configs:
  - `rclone-zurg-config` (Real-Debrid credentials)
  - `rclone-config` (TorBox credentials)
- `oc` CLI with cluster admin access

## Quick Operations

### Deploy New Media App

```bash
{baseDir}/scripts/generate-media-app.sh <app-name> <image> <port>
```

Creates complete deployment with:
- Rclone sidecars (zurg + torbox)
- Proper mount propagation (Bidirectional)
- Node affinity (Node 2/3 preferred)
- Service and route manifests

**Example:**
```bash
./scripts/generate-media-app.sh prowlarr lscr.io/linuxserver/prowlarr:latest 9696
# Creates: apps/prowlarr/base/{deployment.yaml,service.yaml,route.yaml,kustomization.yaml}
```

### Add Sidecars to Existing App

```bash
{baseDir}/scripts/add-sidecars.sh <deployment-name> <namespace>
```

Patches existing deployment to add rclone sidecars without rewriting entire manifest.

**Example:**
```bash
./scripts/add-sidecars.sh bazarr media-stack
# Adds rclone-zurg and rclone-torbox containers to bazarr deployment
```

### Check Media Mount Status

```bash
{baseDir}/scripts/check-media-mounts.sh <namespace>
```

Verifies FUSE mounts across all pods:
- Checks `/mnt/media/zurg/__all__` presence
- Checks `/mnt/media/torbox/torrents` presence
- Tests mount readability
- Reports per-pod status with node location

**Example:**
```bash
./scripts/check-media-mounts.sh media-stack
# Shows mount status for all media-stack pods
```

### Troubleshoot Mount Propagation

```bash
{baseDir}/scripts/troubleshoot-mounts.sh <pod-name> <namespace>
```

Deep dive into mount issues:
- Checks mountPropagation settings
- Verifies privileged securityContext
- Tests FUSE device access
- Shows mount table from pod perspective
- Checks rclone sidecar logs

## Deployment Workflows

### Workflow 1: Deploy New Media App from Scratch

**Scenario:** Add Prowlarr to the media stack

```bash
# 1. Generate deployment manifests
cd /home/sigtom/wow-ocp
./pi/skills/media-stack/scripts/generate-media-app.sh prowlarr lscr.io/linuxserver/prowlarr:latest 9696

# 2. Review generated files
ls -la apps/prowlarr/base/
# deployment.yaml, service.yaml, route.yaml, kustomization.yaml

# 3. Customize if needed
vim apps/prowlarr/base/deployment.yaml
# Adjust resources, environment variables, etc.

# 4. Commit to Git
git add apps/prowlarr
git commit -m "feat(media): add prowlarr deployment"
git push origin main

# 5. Create ArgoCD application
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prowlarr
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/sigtom/wow-ocp.git
    path: apps/prowlarr/base
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: media-stack
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# 6. Sync via ArgoCD
argocd app sync prowlarr

# 7. Verify mounts
./pi/skills/media-stack/scripts/check-media-mounts.sh media-stack | grep prowlarr
```

### Workflow 2: Add Sidecars to Existing Deployment

**Scenario:** Bazarr was deployed without sidecars, needs cloud access

```bash
# 1. Check current mount status
./pi/skills/media-stack/scripts/check-media-mounts.sh media-stack | grep bazarr
# Shows: Missing /mnt/media/zurg

# 2. Add sidecars (dry-run first)
./pi/skills/media-stack/scripts/add-sidecars.sh bazarr media-stack --dry-run
# Shows patch that would be applied

# 3. Apply patch
./pi/skills/media-stack/scripts/add-sidecars.sh bazarr media-stack

# 4. Wait for rollout
oc rollout status deployment/bazarr -n media-stack

# 5. Verify mounts
./pi/skills/media-stack/scripts/check-media-mounts.sh media-stack | grep bazarr
# Shows: OK - /mnt/media/zurg/__all__ (25000+ files)
```

### Workflow 3: Migrate from Standalone Rclone to Sidecars

**Scenario:** Legacy deployment with standalone rclone pod

**Problem:** Standalone rclone pods don't propagate FUSE mounts to other pods on different nodes.

**Solution:** Migrate to sidecar pattern

```bash
# 1. Check current architecture
oc get pods -n media-stack -o wide
# Shows: rclone-zurg pod on Node 2, sonarr pod on Node 3 (different nodes)

# 2. Verify mount failure
oc exec -n media-stack deployment/sonarr -- ls /mnt/media/zurg/__all__
# Error: Transport endpoint is not connected

# 3. Add sidecars to all affected apps
for app in sonarr radarr bazarr; do
  ./pi/skills/media-stack/scripts/add-sidecars.sh $app media-stack
done

# 4. Delete standalone rclone pod
oc delete deployment/rclone-zurg -n media-stack

# 5. Verify all mounts working
./pi/skills/media-stack/scripts/check-media-mounts.sh media-stack
# All apps show: OK - /mnt/media/zurg/__all__ (25000+ files)
```

### Workflow 4: Troubleshoot Missing Cloud Content

**Scenario:** Sonarr can't see Real-Debrid content

```bash
# 1. Check mount status
./pi/skills/media-stack/scripts/check-media-mounts.sh media-stack | grep sonarr
# Shows: FAIL - /mnt/media/zurg (No such file or directory)

# 2. Deep troubleshooting
./pi/skills/media-stack/scripts/troubleshoot-mounts.sh sonarr-xyz123 media-stack

# Output shows:
# - mountPropagation: None (WRONG - should be Bidirectional)
# - /dev/fuse: missing (WRONG - needs privileged: true)

# 3. Check deployment manifest
oc get deployment/sonarr -n media-stack -o yaml | grep -A 5 mountPropagation
# Missing or set to "None"

# 4. Fix in Git
vim apps/sonarr/base/deployment.yaml
# Add mountPropagation: Bidirectional to main container's volumeMount
# Ensure securityContext: privileged: true on rclone sidecars

git commit -am "fix(sonarr): enable mount propagation for cloud storage"
git push

# 5. Sync via ArgoCD
argocd app sync sonarr

# 6. Verify fix
./pi/skills/media-stack/scripts/check-media-mounts.sh media-stack | grep sonarr
# Shows: OK - /mnt/media/zurg/__all__ (25000+ files)
```

## Common Issues & Troubleshooting

### Issue 1: Mount Not Visible in Main Container

**Symptoms:**
- Rclone sidecar logs show successful mount
- Main container sees empty directory
- `ls /mnt/media/zurg/__all__` returns nothing

**Root Cause:**
- Missing `mountPropagation: Bidirectional` on shared volume

**Diagnosis:**
```bash
# Check mount propagation setting
oc get deployment/<app> -n media-stack -o yaml | grep -B 5 -A 2 mountPropagation

# Expected in BOTH sidecar AND main container:
# mountPropagation: Bidirectional
```

**Resolution:**
```bash
# Update deployment manifest in Git
vim apps/<app>/base/deployment.yaml

# Add to volumeMounts section of BOTH rclone sidecars AND main container:
volumeMounts:
- name: media-storage
  mountPath: /mnt/media
  mountPropagation: Bidirectional  # <- Add this line

# Commit and sync
git commit -am "fix: enable bidirectional mount propagation"
git push
argocd app sync <app>
```

**Validation:**
```bash
./scripts/check-media-mounts.sh media-stack | grep <app>
# Should show: OK - /mnt/media/zurg/__all__ (25000+ files)
```

### Issue 2: Rclone Sidecar CrashLoopBackOff

**Symptoms:**
- Rclone container restarts repeatedly
- Logs show: `fusermount: failed to open /dev/fuse: Operation not permitted`
- Mount never succeeds

**Root Cause:**
- Missing `privileged: true` in rclone container securityContext
- Cluster doesn't allow privileged pods (SCC issue)

**Diagnosis:**
```bash
# Check sidecar status
oc get pods -n media-stack -l app=<app>
oc logs <pod> -c rclone-zurg

# Check securityContext
oc get deployment/<app> -n media-stack -o yaml | grep -A 3 "name: rclone-zurg"
# Should show:
# securityContext:
#   privileged: true
```

**Resolution:**
```bash
# 1. Fix securityContext in deployment
vim apps/<app>/base/deployment.yaml

containers:
- name: rclone-zurg
  image: docker.io/rclone/rclone:latest
  securityContext:
    privileged: true  # <- Add this

# 2. Verify SCC allows privileged
oc get scc privileged -o yaml | grep -A 5 users
# Should include: system:serviceaccount:media-stack:<sa-name>

# If missing, add SA to privileged SCC:
oc adm policy add-scc-to-user privileged -z <sa-name> -n media-stack

# 3. Commit and sync
git commit -am "fix: enable privileged for rclone sidecars"
git push
argocd app sync <app>
```

### Issue 3: Mounts Work on Node 2/3 but Not Node 4

**Symptoms:**
- Pods scheduled on Node 2/3 see cloud mounts
- Pods scheduled on Node 4 see empty directories
- Intermittent failures

**Root Cause:**
- Node 4 is hybrid 2-port blade with limited networking
- VLAN 160 storage network issues
- Node affinity missing from deployment

**Diagnosis:**
```bash
# Check pod node placement
oc get pods -n media-stack -o wide
# Compare working vs. non-working pods

# Check node affinity
oc get deployment/<app> -n media-stack -o yaml | grep -A 10 nodeAffinity
```

**Resolution:**
```bash
# Add preferred node affinity in deployment
vim apps/<app>/base/deployment.yaml

spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - wow-ocp-node2
                - wow-ocp-node3

# NOTE: Use preferred, NOT required (hard nodeSelector)
# This allows scheduling flexibility during node maintenance

git commit -am "fix: prefer node 2/3 for better networking"
git push
argocd app sync <app>

# Force reschedule if currently on Node 4
oc delete pod -n media-stack -l app=<app>
```

### Issue 4: Symlinks Broken in Plex

**Symptoms:**
- Plex library shows missing episodes/movies
- Sonarr/Radarr show successful imports
- Symlinks exist in `/mnt/media/stream` but broken

**Root Cause:**
- Symlink points to cloud path that isn't mounted
- rdt-client and Plex on different nodes (legacy issue)
- Mount paths don't match across pods

**Diagnosis:**
```bash
# Check symlink targets
oc exec -n media-stack deployment/plex -- \
  ls -la /mnt/media/stream/Shows/Peacemaker/

# Shows: Peacemaker.S02E05.mkv -> /mnt/media/zurg/__all__/xyz/file.mkv

# Verify target exists in Plex pod
oc exec -n media-stack deployment/plex -- \
  ls -la /mnt/media/zurg/__all__/xyz/file.mkv

# If "No such file or directory" = mount missing
```

**Resolution:**
```bash
# Ensure Plex has rclone sidecars
./scripts/check-media-mounts.sh media-stack | grep plex

# If missing:
./scripts/add-sidecars.sh plex media-stack

# Verify all mount paths consistent
./scripts/check-media-mounts.sh media-stack
# All pods should show same mount structure:
# /mnt/media/zurg/__all__
# /mnt/media/torbox/torrents
```

### Issue 5: High CPU Usage from Rclone Sidecars

**Symptoms:**
- Node CPU saturated
- Rclone containers using 200-400% CPU each
- Media playback stuttering

**Root Cause:**
- VFS cache mode set to `full` causes excessive I/O
- Too aggressive polling intervals
- Multiple apps running redundant mounts

**Diagnosis:**
```bash
# Check rclone resource usage
oc adm top pods -n media-stack
# Shows rclone-zurg/torbox containers high CPU

# Check rclone args
oc get deployment/<app> -n media-stack -o yaml | grep -A 15 "name: rclone-zurg"
```

**Resolution:**
```bash
# Option 1: Reduce cache aggressiveness
vim apps/<app>/base/deployment.yaml

args:
- "mount"
- "zurg:"
- "/mnt/media/zurg"
- "--config=/config/rclone/rclone.conf"
- "--allow-other"
- "--vfs-cache-mode=writes"     # <- Changed from "full"
- "--poll-interval=30s"          # <- Increased from 10s
- "--dir-cache-time=60s"         # <- Increased from 10s
- "--attr-timeout=60s"           # <- Increased from 10s

# Option 2: Add resource limits
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m      # <- Cap CPU usage
    memory: 1Gi

git commit -am "fix: reduce rclone resource usage"
git push
argocd app sync <app>
```

## Sidecar Pattern Reference

### Why Sidecars vs. Standalone?

**Problem with Standalone:**
- FUSE mounts don't propagate across Kubernetes nodes
- App on Node 3 can't see mount from rclone pod on Node 2
- Result: "Transport endpoint is not connected" errors

**Solution with Sidecars:**
- Each pod runs its own rclone containers
- FUSE mount is local to pod's network namespace
- Mount propagates to all containers in same pod via `Bidirectional`
- Works regardless of node scheduling

**Trade-offs:**
- **Pro:** Reliable cross-node functionality
- **Pro:** No node affinity required (scheduling flexibility)
- **Con:** More resource usage (1 rclone per app vs. 1 shared)
- **Con:** Slightly more complex deployment manifests

See `{baseDir}/references/sidecar-pattern.md` for implementation details.

### Required Components Checklist

For any media app deployment:

- ✅ **initContainer**: `init-dirs` to create mount points
- ✅ **Sidecar 1**: `rclone-zurg` for Real-Debrid
  - `privileged: true`
  - `mountPropagation: Bidirectional`
  - Volume: `rclone-zurg-config` secret
- ✅ **Sidecar 2**: `rclone-torbox` for TorBox
  - `privileged: true`
  - `mountPropagation: Bidirectional`
  - Volume: `rclone-config` secret
- ✅ **Main Container**: App with media access
  - `mountPropagation: HostToContainer` (NOT Bidirectional)
  - Volume: `/mnt/media` from PVC
- ✅ **Node Affinity**: Prefer Node 2/3 (NOT hard requirement)
- ✅ **Volumes**:
  - PVC: `media-library-pvc` (TrueNAS NFS)
  - Secrets: `rclone-zurg-config`, `rclone-config`

### Mount Structure

```
/mnt/media/                    <- Shared emptyDir volume
├── zurg/                      <- Mounted by rclone-zurg sidecar
│   └── __all__/               <- Real-Debrid cached torrents
│       ├── Movies/
│       └── Shows/
├── torbox/                    <- Mounted by rclone-torbox sidecar
│   └── torrents/              <- TorBox active downloads
├── archive/                   <- TrueNAS NFS (permanent storage)
│   ├── Movies/
│   └── Shows/
├── stream/                    <- TrueNAS NFS (symlinks only)
│   ├── Movies/
│   └── Shows/
└── config/                    <- TrueNAS NFS (app configs)
    ├── plex/
    ├── sonarr/
    └── radarr/
```

## GitOps Integration

### Standard Deployment Flow

1. **Generate manifests** with helper script
2. **Review and customize** deployment YAML
3. **Commit to Git** repository
4. **Create ArgoCD Application** pointing to Git path
5. **Sync via ArgoCD** (automated or manual)
6. **Verify mounts** with check script

### Never Use `oc apply` Directly

**Wrong:**
```bash
# Manual deployment (breaks GitOps)
oc apply -f apps/myapp/deployment.yaml
```

**Right:**
```bash
# GitOps deployment
git add apps/myapp/
git commit -m "feat: add myapp"
git push
argocd app sync myapp
```

See `argocd-ops` skill for complete GitOps workflows.

## Best Practices

### Do's ✅

1. **Always use sidecar pattern** for new media apps
   ```bash
   # Generate with sidecars included
   ./scripts/generate-media-app.sh myapp image:tag port
   ```

2. **Test mounts after deployment**
   ```bash
   ./scripts/check-media-mounts.sh media-stack | grep myapp
   ```

3. **Use preferred node affinity** (not hard nodeSelector)
   ```yaml
   nodeAffinity:
     preferredDuringSchedulingIgnoredDuringExecution: [...]
   ```

4. **Set resource limits** on rclone sidecars
   ```yaml
   resources:
     limits:
       cpu: 500m
       memory: 1Gi
   ```

5. **Monitor mount health** periodically
   ```bash
   # Add to cron or monitoring
   ./scripts/check-media-mounts.sh media-stack
   ```

### Don'ts ❌

1. **Never use standalone rclone pods**
   - FUSE mounts won't propagate across nodes
   - Use sidecars instead

2. **Never omit mountPropagation**
   ```yaml
   # Wrong
   volumeMounts:
   - name: media-storage
     mountPath: /mnt/media
   
   # Right
   volumeMounts:
   - name: media-storage
     mountPath: /mnt/media
     mountPropagation: Bidirectional  # <- Essential
   ```

3. **Never use hard nodeSelector**
   ```yaml
   # Wrong - locks app to specific node
   nodeSelector:
     kubernetes.io/hostname: wow-ocp-node2
   
   # Right - prefers but allows flexibility
   affinity:
     nodeAffinity:
       preferredDuringSchedulingIgnoredDuringExecution: [...]
   ```

4. **Never skip privileged securityContext**
   ```yaml
   # Wrong - FUSE mount will fail
   containers:
   - name: rclone-zurg
     image: rclone/rclone:latest
   
   # Right
   containers:
   - name: rclone-zurg
     securityContext:
       privileged: true  # <- Required for FUSE
   ```

5. **Never forget init-dirs**
   ```yaml
   # Required to create mount points before sidecars start
   initContainers:
   - name: init-dirs
     image: alpine:latest
     command: ["/bin/sh", "-c", "mkdir -p /mnt/media/zurg /mnt/media/torbox"]
   ```

## Helper Scripts Reference

### generate-media-app.sh

**Purpose:** Create complete deployment structure for new media app

**Usage:**
```bash
./scripts/generate-media-app.sh <app-name> <image> <port> [--zone <zone>]
```

**Options:**
- `--zone`: Set zone label (zone1-4, default: zone2)
- `--no-sidecars`: Generate without rclone sidecars (not recommended)
- `--dry-run`: Show what would be created without writing files

**Output:**
- `apps/<app-name>/base/deployment.yaml`
- `apps/<app-name>/base/service.yaml`
- `apps/<app-name>/base/route.yaml`
- `apps/<app-name>/base/kustomization.yaml`

### add-sidecars.sh

**Purpose:** Patch existing deployment to add rclone sidecars

**Usage:**
```bash
./scripts/add-sidecars.sh <deployment-name> <namespace> [--dry-run]
```

**Options:**
- `--dry-run`: Show patch without applying
- `--force`: Skip confirmation prompt

**Effects:**
- Adds `rclone-zurg` and `rclone-torbox` containers
- Adds `init-dirs` initContainer
- Updates volumeMounts with proper mountPropagation
- Adds secret volumes if missing

### check-media-mounts.sh

**Purpose:** Verify mount status across all pods in namespace

**Usage:**
```bash
./scripts/check-media-mounts.sh <namespace>
```

**Options:**
- `--verbose`: Show detailed mount information
- `--json`: Output in JSON format for automation

**Checks:**
- `/mnt/media/zurg/__all__` presence and readability
- `/mnt/media/torbox/torrents` presence and readability
- File count in each mount (should be >1000)
- Node placement for debugging

### troubleshoot-mounts.sh

**Purpose:** Deep diagnostic for mount propagation issues

**Usage:**
```bash
./scripts/troubleshoot-mounts.sh <pod-name> <namespace>
```

**Checks:**
- mountPropagation settings on all containers
- securityContext privileged flag
- /dev/fuse device accessibility
- Mount table from pod perspective
- Rclone sidecar logs and status
- Volume and secret configurations

## Quick Reference Commands

```bash
# Check all media apps status
./scripts/check-media-mounts.sh media-stack

# Generate new app deployment
./scripts/generate-media-app.sh jellyfin jellyfin/jellyfin:latest 8096

# Add sidecars to existing app
./scripts/add-sidecars.sh bazarr media-stack

# Troubleshoot specific pod
./scripts/troubleshoot-mounts.sh plex-abc123 media-stack

# Verify rclone sidecars running
oc get pods -n media-stack -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}' | grep rclone

# Check mount from inside pod
oc exec -n media-stack deployment/plex -- ls -la /mnt/media/zurg/__all__ | head

# Force pod reschedule (trigger mount recreation)
oc delete pod -n media-stack -l app=sonarr

# View rclone sidecar logs
oc logs -n media-stack <pod-name> -c rclone-zurg

# Check resource usage of sidecars
oc adm top pods -n media-stack --containers | grep rclone
```

## When to Use This Skill

Load this skill when:
- User mentions "media stack", "plex", "sonarr", "radarr", etc.
- User wants to "deploy media app", "add cloud storage"
- User reports "mount not working", "empty directory", "symlinks broken"
- User asks about "rclone", "zurg", "torbox", "real-debrid"
- User mentions "FUSE mount", "mount propagation"
- User needs to "troubleshoot media access"
- User asks about "sidecar pattern" or "hybrid storage"

## Related Skills

- **argocd-ops**: GitOps deployment workflows
- **openshift-debug**: General pod/PVC troubleshooting
- **truenas-ops**: TrueNAS storage backend issues
- **sealed-secrets**: Managing rclone config secrets

## Lessons Learned

From PROGRESS.md (2025-12-23):

> **ARCHITECTURAL UPGRADE**: Migrated entire media stack to Sidecar Pattern.
> - **Change**: Added `rclone-zurg` and `rclone-torbox` containers to every deployment
> - **Result**: Resolved FUSE/NFS mount propagation issues. Apps no longer need to be pinned to a single node.
> - **Optimization**: Replaced hard `nodeSelector` with `nodeAffinity` (preferred) for Node 2 and 3
> - **Outcome**: Verified cross-pod mount consistency and successful deployment to Node 3 via ArgoCD.

**Key Takeaway:** Standalone rclone pods don't work in Kubernetes due to FUSE mount namespace isolation. The sidecar pattern is the correct architecture for cloud storage in containerized media apps.

## Validation

Test the skill:
```bash
cd /home/sigtom/wow-ocp/.pi/skills/media-stack

# Run mount check
./scripts/check-media-mounts.sh media-stack

# Expected output: Table showing all media pods with mount status
# All should show: OK - /mnt/media/zurg/__all__ (25000+ files)
```
