# Media Stack Skill

Operational toolkit for deploying and managing the OpenShift Hybrid-Converged Media Stack with rclone sidecar pattern.

## Overview

This skill provides workflows and automation for:
- Deploying new media applications with cloud storage integration
- Adding rclone sidecars to existing deployments
- Troubleshooting FUSE mount propagation issues
- Verifying media mount status across pods

## Structure

```
media-stack/
├── SKILL.md                    # Main skill documentation (load this in agent)
├── README.md                   # This file
├── references/
│   ├── architecture.md         # Hybrid media stack design reference
│   └── sidecar-pattern.md      # Sidecar implementation guide
├── templates/
│   └── media-deployment.yaml   # Complete deployment template
└── scripts/
    ├── generate-media-app.sh   # Generate new app deployment
    ├── check-media-mounts.sh   # Verify mount status
    ├── add-sidecars.sh         # Add sidecars to existing app
    └── troubleshoot-mounts.sh  # Deep diagnostic tool
```

## Quick Start

### Load Skill in Agent

When user mentions media stack, plex, sonarr, radarr, or mount issues:

```
Load skill: media-stack
```

### Generate New App

```bash
cd /home/sigtom/wow-ocp
./.pi/skills/media-stack/scripts/generate-media-app.sh prowlarr lscr.io/linuxserver/prowlarr:latest 9696
```

### Check Mount Status

```bash
./.pi/skills/media-stack/scripts/check-media-mounts.sh media-stack
```

### Add Sidecars to Existing App

```bash
./.pi/skills/media-stack/scripts/add-sidecars.sh bazarr media-stack
```

### Troubleshoot Mount Issues

```bash
./.pi/skills/media-stack/scripts/troubleshoot-mounts.sh plex-abc123 media-stack
```

## Key Concepts

### Sidecar Pattern

**Problem:** Standalone rclone pods don't propagate FUSE mounts across Kubernetes nodes due to network namespace isolation.

**Solution:** Run rclone as sidecar containers in same pod as application. All containers share network namespace, enabling mount propagation.

**Required Components:**
1. `init-dirs` initContainer (create mount points)
2. `rclone-zurg` sidecar (Real-Debrid)
3. `rclone-torbox` sidecar (TorBox)
4. Main app container with `mountPropagation: HostToContainer`

See `references/sidecar-pattern.md` for detailed explanation.

### Mount Structure

```
/mnt/media/                    # PVC (TrueNAS NFS)
├── zurg/                      # FUSE mount (rclone-zurg sidecar)
│   └── __all__/               # Real-Debrid cached torrents (25k+ files)
├── torbox/                    # FUSE mount (rclone-torbox sidecar)
│   └── torrents/              # TorBox active downloads
├── archive/                   # TrueNAS local storage (permanent)
├── stream/                    # TrueNAS symlink farm
└── config/                    # App persistent data
```

### Node Affinity Strategy

**Preferred (Recommended):**
```yaml
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
```

**Why:** Prefers Node 2/3 (10G NIC, better CPU) but allows fallback to Node 4 if needed. High availability.

**Never Use:** Hard `nodeSelector` (creates single point of failure).

## Common Issues

### Issue 1: Mount Not Visible

**Symptom:** Main container sees empty `/mnt/media/zurg/__all__` directory.

**Fix:**
- Add `mountPropagation: Bidirectional` to sidecar volumeMounts
- Add `mountPropagation: HostToContainer` to main container volumeMounts

### Issue 2: Rclone Sidecar CrashLoopBackOff

**Symptom:** `fusermount: failed to open /dev/fuse: Operation not permitted`

**Fix:**
- Add `privileged: true` to sidecar securityContext
- Grant privileged SCC: `oc adm policy add-scc-to-user privileged -z <sa> -n media-stack`

### Issue 3: Symlinks Broken

**Symptom:** Plex shows missing content, symlinks point to non-existent paths.

**Fix:**
- Ensure both `rclone-zurg` AND `rclone-torbox` sidecars present
- Verify sidecars successfully mounted (check logs)
- Confirm main container has `mountPropagation: HostToContainer`

## Validation

Test skill functionality:

```bash
# Check mount status (should show all pods with OK status)
./.pi/skills/media-stack/scripts/check-media-mounts.sh media-stack

# Expected output:
# POD                            NODE                 ZURG MOUNT                     TORBOX MOUNT
# plex-abc123                    wow-ocp-node2        OK (25000+ files)              OK (50+ files)
# sonarr-xyz789                  wow-ocp-node3        OK (25000+ files)              OK (50+ files)
```

## Documentation

- **SKILL.md**: Complete operational guide (load in agent)
- **references/architecture.md**: Hybrid media stack design, 4 zones, data flow
- **references/sidecar-pattern.md**: Why sidecars, implementation, troubleshooting
- **templates/media-deployment.yaml**: Production-ready template with annotations

## Related Skills

- **argocd-ops**: GitOps deployment workflows
- **openshift-debug**: General pod/PVC troubleshooting
- **truenas-ops**: TrueNAS storage backend issues
- **sealed-secrets**: Managing rclone config secrets

## Lessons Learned

From December 2025 sidecar migration (PROGRESS.md):

> **ARCHITECTURAL UPGRADE**: Migrated entire media stack to Sidecar Pattern.
> - **Result**: Resolved FUSE/NFS mount propagation issues. Apps no longer need to be pinned to a single node.
> - **Outcome**: Verified cross-pod mount consistency and successful deployment to Node 3 via ArgoCD.

**Key Takeaway:** Standalone rclone pods don't work in Kubernetes. Sidecar pattern is mandatory for FUSE mounts in multi-node clusters.

## Author

Created: 2026-01-08
Based on: Project Design - HybridMedia Stack.md + PROGRESS.md lessons learned

## License

Internal use only - Part of wow-ocp homelab GitOps repository
