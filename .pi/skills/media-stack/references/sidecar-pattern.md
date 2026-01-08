# Sidecar Pattern for Media Stack

Comprehensive implementation guide for the rclone sidecar pattern used in the OpenShift Hybrid Media Stack. This document explains WHY sidecars are necessary, HOW to implement them correctly, and WHAT to avoid.

## Table of Contents

1. [Why Sidecars?](#why-sidecars)
2. [Architecture Comparison](#architecture-comparison)
3. [Implementation Components](#implementation-components)
4. [Mount Propagation Deep Dive](#mount-propagation-deep-dive)
5. [Security Context Requirements](#security-context-requirements)
6. [Node Affinity Strategy](#node-affinity-strategy)
7. [Complete Example](#complete-example)
8. [Common Mistakes](#common-mistakes)
9. [Troubleshooting](#troubleshooting)

## Why Sidecars?

### The Problem: Kubernetes Network Namespace Isolation

**Scenario:** You deploy a standalone rclone pod to mount cloud storage (Real-Debrid, TorBox) via FUSE filesystem. You expect other pods (Plex, Sonarr) to access this mount through a shared PVC.

**What Happens:**
```
Node 2:
- rclone-zurg pod
  └── Mounts Real-Debrid at /mnt/media/zurg
  └── FUSE filesystem visible ONLY within this pod's network namespace

Node 3:
- plex pod
  └── Mounts same PVC at /mnt/media
  └── Tries to access /mnt/media/zurg
  └── Result: "Transport endpoint is not connected" ❌
```

**Why It Fails:**
1. **FUSE is network namespace-local**: Kernel mount table is per-namespace, not global
2. **Kubernetes pods are isolated**: Each pod has its own network namespace
3. **NFS/PVC doesn't help**: FUSE mount is in rclone pod's namespace, not visible through NFS
4. **Node boundaries**: Even on same node, pods are isolated (different from Docker)

**Bottom Line:** You cannot share a FUSE mount from one pod to another pod, even with RWX PVC.

### The Solution: Sidecar Containers

**Concept:** Run rclone as a sidecar container INSIDE the same pod as your application.

**What Changes:**
```
Node 3:
- plex pod (single network namespace shared by all containers)
  ├── rclone-zurg container
  │   └── Mounts Real-Debrid at /mnt/media/zurg (FUSE)
  ├── rclone-torbox container
  │   └── Mounts TorBox at /mnt/media/torbox (FUSE)
  └── plex container
      └── Accesses /mnt/media/zurg via mountPropagation ✓
```

**Why It Works:**
1. **Shared network namespace**: All containers in a pod share the same mount table
2. **mountPropagation: Bidirectional**: Sidecar mounts propagate to sibling containers
3. **No node constraints**: Works on ANY node (Node 2, 3, or 4)
4. **Reliable**: No cross-pod/cross-node mount dependencies

### Trade-offs

**Pros:**
- ✅ **Reliability**: Guaranteed mount visibility within pod
- ✅ **Portability**: Pod can be scheduled on any node
- ✅ **No affinity required**: Removes hard node constraints
- ✅ **Isolation**: Each app has independent mount lifecycle
- ✅ **Resilience**: If one app crashes, others unaffected

**Cons:**
- ❌ **Resource overhead**: N rclone processes (1 per app) vs. 1 shared
- ❌ **Complexity**: More containers per pod (3-4 instead of 1)
- ❌ **Redundancy**: Multiple rclone instances mounting same cloud endpoint
- ❌ **Scaling limits**: Can't scale to 100+ apps (CPU/memory cost)

**Decision Matrix:**

| Apps | Standalone | Sidecar | Hybrid |
|------|-----------|---------|--------|
| 1-5 | ❌ Broken | ✅ Best | N/A |
| 5-20 | ❌ Broken | ✅ Good | ⚠️ Consider |
| 20-50 | ❌ Broken | ⚠️ Costly | ✅ Best |
| 50+ | ❌ Broken | ❌ Expensive | ✅ Required |

**Current Media Stack (10 apps):** Sidecar pattern is optimal.

**Future (>50 apps):** Consider hybrid approach (shared rclone on SAME node + hard affinity).

## Architecture Comparison

### Before: Standalone Rclone (Broken)

**Deployment Structure:**
```yaml
# Separate rclone deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rclone-zurg
spec:
  template:
    spec:
      containers:
      - name: rclone
        image: rclone/rclone:latest
        # Mounts /mnt/media/zurg from PVC
```

```yaml
# Plex deployment (separate pod)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plex
spec:
  template:
    spec:
      containers:
      - name: plex
        image: linuxserver/plex:latest
        # Expects to access /mnt/media/zurg
```

**Node Scheduling:**
```
Node 2:              Node 3:
┌─────────────┐      ┌─────────────┐
│ rclone pod  │      │  plex pod   │
│             │      │             │
│ /mnt/media/ │      │ /mnt/media/ │
│ └── zurg/   │      │ └── zurg/   │ <- EMPTY (mount not visible)
│     └── 📁  │      │     └── ❌  │
└─────────────┘      └─────────────┘
      ↑                    ↑
      └────────────────────┘
           Same PVC (doesn't matter)
```

**Problem:** FUSE mount in rclone pod's namespace is not visible in Plex pod's namespace.

### After: Sidecar Pattern (Working)

**Deployment Structure:**
```yaml
# Plex deployment with sidecars
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plex
spec:
  template:
    spec:
      containers:
      # Sidecar 1: rclone-zurg
      - name: rclone-zurg
        image: rclone/rclone:latest
        securityContext:
          privileged: true
        volumeMounts:
        - name: media-storage
          mountPath: /mnt/media
          mountPropagation: Bidirectional
      
      # Sidecar 2: rclone-torbox
      - name: rclone-torbox
        image: rclone/rclone:latest
        securityContext:
          privileged: true
        volumeMounts:
        - name: media-storage
          mountPath: /mnt/media
          mountPropagation: Bidirectional
      
      # Main container
      - name: plex
        image: linuxserver/plex:latest
        volumeMounts:
        - name: media-storage
          mountPath: /mnt/media
          mountPropagation: HostToContainer
```

**Node Scheduling:**
```
Node 3:
┌────────────────────────────────────┐
│         plex pod (1 namespace)     │
│                                    │
│  ┌──────────────┐  ┌────────────┐ │
│  │ rclone-zurg  │  │   plex     │ │
│  │ container    │  │ container  │ │
│  │              │  │            │ │
│  │ Mounts FUSE  │  │ Reads via  │ │
│  │ /mnt/media/  │  │ mount      │ │
│  │ └── zurg/    │  │ propagation│ │
│  │     └── 📁   │  │            │ │
│  └──────────────┘  └────────────┘ │
│         ↓                ↓         │
│    Shared mount table (visible)   │
└────────────────────────────────────┘
```

**Solution:** All containers in pod share network namespace, FUSE mount is visible everywhere.

## Implementation Components

### 1. Init Container (init-dirs)

**Purpose:** Create mount point directories before rclone sidecars start.

**Why Needed:**
- FUSE mount target must exist before `rclone mount` command
- If directory missing, rclone crashes with "directory not found"
- emptyDir volumes start empty (no directories)

**Implementation:**
```yaml
initContainers:
- name: init-dirs
  image: docker.io/alpine:latest
  command:
    - /bin/sh
    - -c
    - |
      mkdir -p /mnt/media/zurg
      mkdir -p /mnt/media/torbox
      echo "Mount points created successfully"
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
```

**Best Practices:**
- ✅ Use lightweight image (alpine, busybox)
- ✅ Create ALL mount points (zurg + torbox)
- ✅ Exit cleanly (no infinite loops)
- ❌ Don't run as daemon (init containers must exit)

### 2. Sidecar: rclone-zurg (Real-Debrid)

**Purpose:** Mount Real-Debrid cached torrents via Zurg WebDAV gateway.

**Implementation:**
```yaml
- name: rclone-zurg
  image: docker.io/rclone/rclone:latest
  securityContext:
    privileged: true  # REQUIRED for /dev/fuse access
  args:
  - "mount"
  - "zurg:"                       # Remote name from rclone.conf
  - "/mnt/media/zurg"             # Mount point (created by init-dirs)
  - "--config=/config/rclone/rclone.conf"
  - "--allow-other"               # Allow other users (plex container)
  - "--vfs-cache-mode=full"       # Cache metadata + data
  - "--poll-interval=10s"         # Check for new files every 10s
  - "--dir-cache-time=10s"        # Cache directory listings for 10s
  - "--attr-timeout=10s"          # Cache file attributes for 10s
  - "--rc"                        # Enable remote control
  - "--rc-no-auth"                # No auth (localhost only)
  - "--rc-addr=:5572"             # RC port (unique per sidecar)
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional  # CRITICAL: Propagate mount to siblings
  - name: rclone-zurg-config
    mountPath: /config/rclone
    readOnly: true
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m       # Prevent runaway CPU
      memory: 1Gi
```

**Key Parameters Explained:**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `--allow-other` | Required | Allow plex container (different UID) to read mount |
| `--vfs-cache-mode=full` | Recommended | Cache metadata to reduce API calls |
| `--poll-interval=10s` | Tunable | How often to check for new files (balance freshness vs. load) |
| `--rc` | Optional | Remote control API for troubleshooting |
| `--rc-addr=:5572` | Unique | Each sidecar needs different port (5572, 5573, etc.) |

**Resource Limits:**
- **CPU**: 500m limit prevents CPU saturation (rclone can be CPU-intensive)
- **Memory**: 1Gi limit for VFS cache (adjust based on library size)

### 3. Sidecar: rclone-torbox (TorBox)

**Purpose:** Mount TorBox active downloads + Usenet cache via native rclone WebDAV.

**Implementation:**
```yaml
- name: rclone-torbox
  image: docker.io/rclone/rclone:latest
  securityContext:
    privileged: true  # REQUIRED for /dev/fuse access
  args:
  - "mount"
  - "torbox:"                     # Remote name from rclone.conf
  - "/mnt/media/torbox"           # Mount point (different from zurg)
  - "--config=/config/rclone/rclone.conf"
  - "--allow-other"
  - "--vfs-cache-mode=full"
  - "--poll-interval=10s"
  - "--dir-cache-time=10s"
  - "--attr-timeout=10s"
  - "--rc"
  - "--rc-no-auth"
  - "--rc-addr=:5573"             # Different port than zurg (5573)
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional  # CRITICAL
  - name: rclone-config
    mountPath: /config/rclone
    readOnly: true
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
```

**Differences from rclone-zurg:**
- Different remote name (`torbox:` vs. `zurg:`)
- Different mount point (`/mnt/media/torbox`)
- Different RC port (`5573` vs. `5572`)
- Different secret (`rclone-config` vs. `rclone-zurg-config`)

**Why Two Separate Sidecars?**
- Different cloud providers (Real-Debrid vs. TorBox)
- Different credentials (separate secrets)
- Different mount paths (avoid conflicts)
- Independent failure domains (if one crashes, other still works)

### 4. Main Container (Application)

**Purpose:** Run the actual application (Plex, Sonarr, etc.) with access to cloud mounts.

**Implementation:**
```yaml
- name: plex
  image: lscr.io/linuxserver/plex:latest
  env:
  - name: PUID
    value: "1000"
  - name: PGID
    value: "1000"
  - name: VERSION
    value: docker
  ports:
  - containerPort: 32400
    name: pms
  volumeMounts:
  # Config directory (app state)
  - name: media-storage
    mountPath: /config
    subPath: config/plex
  # Media directory (cloud mounts + local storage)
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: HostToContainer  # RECEIVE mounts from sidecars
  livenessProbe:
    tcpSocket:
      port: 32400
    initialDelaySeconds: 40
    periodSeconds: 20
  readinessProbe:
    tcpSocket:
      port: 32400
    initialDelaySeconds: 20
    periodSeconds: 10
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: "4"
      memory: 8Gi
```

**Key Points:**
- ✅ **mountPropagation: HostToContainer**: Receives mounts FROM sidecars (one-way)
- ❌ **NOT Bidirectional**: Main container doesn't create mounts, only consumes
- ✅ **subPath for config**: Separate config directory from media directory
- ✅ **Higher resource limits**: Main app typically needs more resources than sidecars

### 5. Volumes

**Purpose:** Provide shared storage and credentials.

**Implementation:**
```yaml
volumes:
# PVC for persistent storage (TrueNAS NFS)
- name: media-storage
  persistentVolumeClaim:
    claimName: media-library-pvc

# Secret for Zurg credentials
- name: rclone-zurg-config
  secret:
    secretName: rclone-zurg-config
    defaultMode: 0400  # Read-only for owner

# Secret for TorBox credentials
- name: rclone-config
  secret:
    secretName: rclone-config
    defaultMode: 0400  # Read-only for owner
```

**Volume Types:**

| Volume | Type | Purpose | Shared |
|--------|------|---------|--------|
| `media-storage` | PVC (NFS) | Persistent storage + mount points | Yes (RWX) |
| `rclone-zurg-config` | Secret | Real-Debrid API credentials | No (read-only) |
| `rclone-config` | Secret | TorBox API credentials | No (read-only) |

**Why NOT emptyDir?**
- FUSE mounts need persistent base directory
- emptyDir is ephemeral (lost on pod restart)
- PVC provides persistence + cross-pod sharing (for config backups)

### 6. Node Affinity (Optional but Recommended)

**Purpose:** Prefer nodes with better networking/CPU without hard constraint.

**Implementation:**
```yaml
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
```

**Why Preferred (Not Required)?**
- ✅ Scheduler tries Node 2/3 first (10G NIC, better CPU)
- ✅ Falls back to Node 4 if Node 2/3 unavailable
- ✅ High availability (pod always scheduled)
- ❌ Required affinity = single point of failure

See [Node Affinity Strategy](#node-affinity-strategy) for details.

## Mount Propagation Deep Dive

### What is mountPropagation?

**Definition:** Controls how mounts created in one container affect other containers in the same pod, and the host.

**Modes:**

| Mode | Mount Flow | Use Case |
|------|------------|----------|
| `None` | Isolated (default) | No mount propagation (safest) |
| `HostToContainer` | Host → Container | Container RECEIVES mounts from host/sidecars |
| `Bidirectional` | Host ↔ Container | Container CREATES + RECEIVES mounts |

**Kubernetes Documentation:**
- HostToContainer: "The container will receive all mounts subsequently created by the host or other containers"
- Bidirectional: "Mounts created by the container will be propagated to the host and all containers"

### Why Bidirectional for Sidecars?

**Scenario:** rclone-zurg sidecar creates FUSE mount at `/mnt/media/zurg`.

**Goal:** Make this mount visible to plex container (sibling in same pod).

**Solution:**
```yaml
# Sidecar (creates mount)
- name: rclone-zurg
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional  # "I create mounts that others can see"
```

**What Happens:**
1. rclone-zurg creates FUSE mount at `/mnt/media/zurg`
2. Kubernetes propagates mount to pod's shared mount namespace
3. Mount becomes visible to ALL containers with `HostToContainer` propagation

**Without Bidirectional:**
```yaml
# Wrong: sidecar with None propagation
- name: rclone-zurg
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: None  # ❌ Mount stays private to this container
```

**Result:** plex container sees `/mnt/media/zurg` as empty directory (mount not propagated).

### Why HostToContainer for Main App?

**Scenario:** plex container needs to READ mounts created by sidecars.

**Goal:** Receive mounts, but don't create new ones (principle of least privilege).

**Solution:**
```yaml
# Main app (receives mounts)
- name: plex
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: HostToContainer  # "I receive mounts from others"
```

**What Happens:**
1. Plex sees `/mnt/media` base directory (from PVC)
2. Plex automatically sees `/mnt/media/zurg` (propagated from rclone-zurg sidecar)
3. Plex automatically sees `/mnt/media/torbox` (propagated from rclone-torbox sidecar)

**Why NOT Bidirectional for Main App?**
- Plex doesn't create mounts (only rclone does)
- HostToContainer is sufficient (one-way receive)
- Bidirectional = unnecessary privilege escalation

### Visual Flow

```
┌────────────────────────────────────────────────┐
│              Pod Network Namespace             │
│                                                │
│  ┌──────────────────────┐                     │
│  │  rclone-zurg         │                     │
│  │  (Bidirectional)     │                     │
│  │                      │                     │
│  │  1. Mount FUSE at    │                     │
│  │     /mnt/media/zurg  │                     │
│  │                      │                     │
│  │  2. Propagate mount  │                     │
│  │     to namespace ────┼────────┐            │
│  └──────────────────────┘        │            │
│                                  ↓            │
│  ┌──────────────────────┐  ┌────────────────┐│
│  │  rclone-torbox       │  │  Pod mount     ││
│  │  (Bidirectional)     │  │  table         ││
│  │                      │  │                ││
│  │  1. Mount FUSE at    │  │ /mnt/media/    ││
│  │     /mnt/media/torbox│  │ ├── zurg/      ││
│  │                      │  │ └── torbox/    ││
│  │  2. Propagate mount ─┼─→│                ││
│  └──────────────────────┘  └────────────────┘│
│                                  ↓            │
│  ┌──────────────────────────────────────────┐│
│  │  plex                                     ││
│  │  (HostToContainer)                        ││
│  │                                           ││
│  │  1. Reads /mnt/media/zurg (visible ✓)    ││
│  │  2. Reads /mnt/media/torbox (visible ✓)  ││
│  │  3. Follows symlinks correctly ✓          ││
│  └──────────────────────────────────────────┘│
└────────────────────────────────────────────────┘
```

### Common mountPropagation Mistakes

#### Mistake 1: All None (No Propagation)

```yaml
# ❌ WRONG
containers:
- name: rclone-zurg
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    # mountPropagation: None (default)

- name: plex
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    # mountPropagation: None (default)
```

**Problem:** Mounts stay isolated to rclone-zurg container. Plex sees empty directory.

#### Mistake 2: Main App Bidirectional

```yaml
# ❌ WRONG
containers:
- name: rclone-zurg
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional  # ✓ Correct

- name: plex
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional  # ❌ Unnecessary privilege
```

**Problem:** Works, but violates principle of least privilege. Plex doesn't need to CREATE mounts.

#### Mistake 3: Sidecar HostToContainer

```yaml
# ❌ WRONG
containers:
- name: rclone-zurg
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: HostToContainer  # ❌ One-way receive only

- name: plex
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: HostToContainer  # ✓ Correct but useless
```

**Problem:** Sidecar can't propagate mounts OUT. Plex receives nothing.

#### Correct Pattern

```yaml
# ✅ CORRECT
containers:
- name: rclone-zurg
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional  # ✓ Create + propagate mounts

- name: plex
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: HostToContainer  # ✓ Receive mounts only
```

## Security Context Requirements

### Why Privileged?

**FUSE Requirement:** FUSE (Filesystem in Userspace) requires access to `/dev/fuse` character device.

**Kubernetes Behavior:**
- Non-privileged containers: `/dev/fuse` not accessible
- Privileged containers: All devices accessible (including `/dev/fuse`)

**Rclone Mount Command:**
```bash
rclone mount torbox: /mnt/media/torbox
```

**Behind the Scenes:**
1. Rclone opens `/dev/fuse`
2. Rclone registers FUSE filesystem with kernel
3. Kernel routes filesystem operations to rclone process
4. Rclone translates to WebDAV API calls

**Without Privileged:**
```
Error: fusermount: failed to open /dev/fuse: Operation not permitted
```

### Minimal Privilege Pattern

**Best Practice:** Only sidecars need privileged, NOT main app.

```yaml
# ✅ CORRECT
containers:
# Sidecars need privileged (create FUSE mounts)
- name: rclone-zurg
  securityContext:
    privileged: true  # ✓ Required for FUSE

- name: rclone-torbox
  securityContext:
    privileged: true  # ✓ Required for FUSE

# Main app doesn't need privileged (only reads mounts)
- name: plex
  securityContext:
    # No privileged needed ✓
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
```

**Why Main App Doesn't Need Privileged:**
- Main app READS from existing FUSE mount (already created by sidecar)
- Main app doesn't CREATE mounts (no `/dev/fuse` access needed)
- Principle of least privilege (minimize attack surface)

### SCC (Security Context Constraints)

**OpenShift Requirement:** ServiceAccount must have `privileged` SCC binding.

```bash
# Grant privileged SCC to service account
oc adm policy add-scc-to-user privileged -z plex -n media-stack
```

**Verification:**
```bash
# Check SCC bindings
oc get scc privileged -o yaml | grep -A 5 users

# Should show:
# users:
# - system:serviceaccount:media-stack:plex
```

**Per-Zone Service Accounts:**
- `plex` (Zone 3 - Player)
- `managers` (Zone 2 - Sonarr, Radarr, Bazarr, SABnzbd)
- `cloud-gateway` (Zone 1 - Zurg, rdt-client, Riven)
- `discovery` (Zone 4 - Overseerr)

Each needs privileged SCC if running rclone sidecars.

### Alternative: unprivileged FUSE (Future)

**Experimental:** Kubernetes 1.30+ supports unprivileged FUSE via `SYS_ADMIN` capability.

```yaml
# Future alternative (not yet stable)
- name: rclone-zurg
  securityContext:
    capabilities:
      add:
      - SYS_ADMIN  # Alternative to privileged
    # privileged: false
```

**Status:** Not yet stable in OpenShift 4.20. Stick with `privileged: true` for now.

## Node Affinity Strategy

### Preferred vs. Required

**Decision Tree:**

```
Do pods need to run on specific node?
│
├─ YES (hardware requirement)
│  └─ Use requiredDuringSchedulingIgnoredDuringExecution
│     └─ Example: GPU workload, specific storage driver
│
└─ NO (just performance preference)
   └─ Use preferredDuringSchedulingIgnoredDuringExecution
      └─ Example: better NIC, faster CPU (media stack)
```

### Preferred Affinity (Recommended)

**Use Case:** Node 2/3 have 10G NICs and better CPUs, but apps CAN run on Node 4 if needed.

**Implementation:**
```yaml
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100  # Higher = stronger preference
            preference:
              matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - wow-ocp-node2
                - wow-ocp-node3
```

**Scheduler Behavior:**
1. **Score nodes**: Node 2/3 get +100 points, Node 4 gets 0
2. **Consider other factors**: Resource availability, pod affinity/anti-affinity
3. **Pick best node**: Usually Node 2/3 (unless overloaded)
4. **Fallback**: Schedules on Node 4 if Node 2/3 full or unavailable

**Benefits:**
- ✅ High availability (always scheduled)
- ✅ Load balancing (distributes across Node 2/3)
- ✅ Maintenance-friendly (drain Node 2, pods move to Node 3)
- ✅ No single point of failure

### Required Affinity (Avoid for Media Stack)

**Use Case:** App MUST run on specific node (hard requirement).

**Implementation:**
```yaml
# ❌ NOT RECOMMENDED for media stack
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - wow-ocp-node2
```

**Scheduler Behavior:**
1. **Check requirement**: Is Node 2 available?
2. **Yes**: Schedule on Node 2
3. **No**: Pod stays Pending forever (no fallback)

**Problems:**
- ❌ Single point of failure (Node 2 down = pod dead)
- ❌ No load balancing (all pods on Node 2)
- ❌ Maintenance nightmare (drain Node 2 = manual intervention)

### nodeSelector (Legacy, Avoid)

**Old Pattern (Pre-sidecar migration):**
```yaml
# ❌ DEPRECATED for media stack
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: wow-ocp-node4
```

**Why Deprecated:**
- Hard constraint (same problems as required affinity)
- Less flexible than affinity API
- No weight/preference system

**Migration Path:**
```yaml
# Old (hard constraint)
nodeSelector:
  kubernetes.io/hostname: wow-ocp-node4

# New (soft preference)
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
```

### Node Characteristics

| Node | NICs | CPU | Storage Network | Media Suitability | Preference Weight |
|------|------|-----|-----------------|-------------------|-------------------|
| Node 2 | 4x1G bond + 10G | Xeon X5650 (12T) | ✓ VLAN 160 stable | **Excellent** | 100 |
| Node 3 | 4x1G bond + 10G | Xeon X5650 (12T) | ✓ VLAN 160 stable | **Excellent** | 100 |
| Node 4 | 2x1G hybrid | Xeon E5440 (4T) | ⚠ VLAN 160 flaky | **Avoid** | 0 |

**Recommendation:** Use preferred affinity for Node 2/3, allow fallback to Node 4.

## Complete Example

### Full Plex Deployment with Sidecars

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plex
  namespace: media-stack
  labels:
    app: plex
    zone: zone3
spec:
  replicas: 1
  selector:
    matchLabels:
      app: plex
  template:
    metadata:
      labels:
        app: plex
        zone: zone3
    spec:
      serviceAccountName: plex
      
      # Prefer Node 2/3 for better networking
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
      
      # Create mount points before sidecars start
      initContainers:
      - name: init-dirs
        image: docker.io/alpine:latest
        command:
          - /bin/sh
          - -c
          - |
            mkdir -p /mnt/media/zurg /mnt/media/torbox
            echo "Mount points created successfully"
        volumeMounts:
        - name: media-storage
          mountPath: /mnt/media
      
      containers:
      # Sidecar 1: Mount Real-Debrid via Zurg
      - name: rclone-zurg
        image: docker.io/rclone/rclone:latest
        securityContext:
          privileged: true  # Required for FUSE
        args:
        - "mount"
        - "zurg:"
        - "/mnt/media/zurg"
        - "--config=/config/rclone/rclone.conf"
        - "--allow-other"
        - "--vfs-cache-mode=full"
        - "--poll-interval=10s"
        - "--dir-cache-time=10s"
        - "--attr-timeout=10s"
        - "--rc"
        - "--rc-no-auth"
        - "--rc-addr=:5572"
        volumeMounts:
        - name: media-storage
          mountPath: /mnt/media
          mountPropagation: Bidirectional  # Propagate mount to siblings
        - name: rclone-zurg-config
          mountPath: /config/rclone
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "test -d /mnt/media/zurg/__all__"
          initialDelaySeconds: 30
          periodSeconds: 30
      
      # Sidecar 2: Mount TorBox
      - name: rclone-torbox
        image: docker.io/rclone/rclone:latest
        securityContext:
          privileged: true  # Required for FUSE
        args:
        - "mount"
        - "torbox:"
        - "/mnt/media/torbox"
        - "--config=/config/rclone/rclone.conf"
        - "--allow-other"
        - "--vfs-cache-mode=full"
        - "--poll-interval=10s"
        - "--dir-cache-time=10s"
        - "--attr-timeout=10s"
        - "--rc"
        - "--rc-no-auth"
        - "--rc-addr=:5573"
        volumeMounts:
        - name: media-storage
          mountPath: /mnt/media
          mountPropagation: Bidirectional  # Propagate mount to siblings
        - name: rclone-config
          mountPath: /config/rclone
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "test -d /mnt/media/torbox/torrents"
          initialDelaySeconds: 30
          periodSeconds: 30
      
      # Main: Plex Media Server
      - name: plex
        image: lscr.io/linuxserver/plex:latest
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: VERSION
          value: docker
        - name: PLEX_CLAIM
          valueFrom:
            secretKeyRef:
              name: plex-claim
              key: claimToken
        ports:
        - containerPort: 32400
          name: pms
        volumeMounts:
        # Config directory (persistent state)
        - name: media-storage
          mountPath: /config
          subPath: config/plex
        # Media directory (cloud mounts + local storage)
        - name: media-storage
          mountPath: /mnt/media
          mountPropagation: HostToContainer  # Receive mounts from sidecars
        livenessProbe:
          tcpSocket:
            port: 32400
          initialDelaySeconds: 40
          periodSeconds: 20
        readinessProbe:
          tcpSocket:
            port: 32400
          initialDelaySeconds: 20
          periodSeconds: 10
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: "4"
            memory: 8Gi
      
      volumes:
      # PVC for TrueNAS storage (RWX)
      - name: media-storage
        persistentVolumeClaim:
          claimName: media-library-pvc
      # Secret for Zurg credentials
      - name: rclone-zurg-config
        secret:
          secretName: rclone-zurg-config
          defaultMode: 0400
      # Secret for TorBox credentials
      - name: rclone-config
        secret:
          secretName: rclone-config
          defaultMode: 0400
---
apiVersion: v1
kind: Service
metadata:
  name: plex
  namespace: media-stack
spec:
  type: LoadBalancer
  selector:
    app: plex
  ports:
  - protocol: TCP
    port: 32400
    targetPort: 32400
    name: pms
```

### Key Highlights

1. **Init Container**: Creates `/mnt/media/zurg` and `/mnt/media/torbox` directories
2. **Sidecars**: Both `rclone-zurg` and `rclone-torbox` with:
   - `privileged: true` (FUSE requirement)
   - `mountPropagation: Bidirectional` (propagate mounts)
   - Different RC ports (5572 vs. 5573)
   - Resource limits (prevent CPU saturation)
3. **Main Container**: Plex with:
   - `mountPropagation: HostToContainer` (receive mounts)
   - NO privileged (principle of least privilege)
   - Higher resource limits (transcoding workload)
4. **Node Affinity**: Preferred (not required) for Node 2/3
5. **Volumes**: PVC + 2 secrets for credentials

## Common Mistakes

### 1. Forgetting init-dirs

**Symptom:**
```
rclone mount failed: directory not found: /mnt/media/zurg
```

**Fix:**
```yaml
initContainers:
- name: init-dirs
  image: alpine:latest
  command: ["/bin/sh", "-c", "mkdir -p /mnt/media/zurg /mnt/media/torbox"]
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
```

### 2. Wrong mountPropagation

**Symptom:**
```bash
# From plex container
ls /mnt/media/zurg/__all__
# Empty (should show thousands of files)
```

**Fix:**
```yaml
# Sidecar
- name: rclone-zurg
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional  # <- Add this

# Main container
- name: plex
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: HostToContainer  # <- Add this
```

### 3. Missing privileged securityContext

**Symptom:**
```
fusermount: failed to open /dev/fuse: Operation not permitted
```

**Fix:**
```yaml
- name: rclone-zurg
  securityContext:
    privileged: true  # <- Add this
```

### 4. Using nodeSelector instead of nodeAffinity

**Symptom:**
- Pod stuck Pending when Node 2/3 unavailable
- All pods on same node (no load balancing)

**Fix:**
```yaml
# Replace this
nodeSelector:
  kubernetes.io/hostname: wow-ocp-node2

# With this
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
```

### 5. Duplicate RC Ports

**Symptom:**
```
rclone: Failed to start remote control: listen tcp :5572: bind: address already in use
```

**Fix:**
```yaml
# Zurg sidecar
- name: rclone-zurg
  args:
  - "--rc-addr=:5572"  # <- Unique port

# TorBox sidecar
- name: rclone-torbox
  args:
  - "--rc-addr=:5573"  # <- Different port
```

### 6. No Resource Limits

**Symptom:**
- Node CPU at 100%
- Rclone consuming 400% CPU
- Other pods starved

**Fix:**
```yaml
- name: rclone-zurg
  resources:
    limits:
      cpu: 500m      # <- Add CPU limit
      memory: 1Gi    # <- Add memory limit
```

## Troubleshooting

### Mount Not Visible

**Diagnosis:**
```bash
# Check from main container
oc exec -n media-stack deployment/plex -- ls -la /mnt/media/zurg/__all__

# If empty or error "Transport endpoint is not connected"
# Check sidecar status
oc get pods -n media-stack -l app=plex
oc logs -n media-stack <pod> -c rclone-zurg
```

**Common Causes:**
1. **mountPropagation missing**: Add `Bidirectional` to sidecars
2. **Sidecar crashed**: Check logs for FUSE mount errors
3. **Privileged not granted**: Add `privileged: true` to sidecar

### Sidecar CrashLoopBackOff

**Diagnosis:**
```bash
oc logs -n media-stack <pod> -c rclone-zurg

# Common errors:
# - "directory not found" -> init-dirs missing
# - "Operation not permitted" -> privileged: true missing
# - "Connection refused" -> Invalid credentials in secret
```

**Fixes:**
- Add init-dirs initContainer
- Add `privileged: true` to sidecar
- Verify secret contains valid `rclone.conf`

### High CPU Usage

**Diagnosis:**
```bash
oc adm top pods -n media-stack --containers | grep rclone

# Shows CPU usage per container
```

**Fixes:**
```yaml
# Reduce cache aggressiveness
args:
- "--vfs-cache-mode=writes"  # Instead of "full"
- "--poll-interval=30s"       # Instead of 10s

# Add resource limits
resources:
  limits:
    cpu: 500m  # Cap CPU
```

### Symlinks Broken

**Diagnosis:**
```bash
# From plex container
oc exec -n media-stack deployment/plex -- \
  ls -la /mnt/media/stream/Shows/MyShow/S01E01.mkv

# Shows symlink target
MyShow.S01E01.mkv -> /mnt/media/torbox/torrents/abc/file.mkv

# Test if target exists
oc exec -n media-stack deployment/plex -- \
  ls -la /mnt/media/torbox/torrents/abc/file.mkv

# If "No such file or directory" -> torbox mount missing
```

**Fix:**
- Ensure both `rclone-zurg` AND `rclone-torbox` sidecars present
- Check rclone-torbox sidecar logs for mount success
- Verify mountPropagation on main container

## Summary

**Sidecar Pattern Requirements:**
1. ✅ init-dirs initContainer (create mount points)
2. ✅ rclone-zurg sidecar with `privileged: true` + `mountPropagation: Bidirectional`
3. ✅ rclone-torbox sidecar with `privileged: true` + `mountPropagation: Bidirectional`
4. ✅ Main container with `mountPropagation: HostToContainer`
5. ✅ ServiceAccount with `privileged` SCC binding
6. ✅ Node affinity: preferred (not required)
7. ✅ Resource limits on sidecars
8. ✅ Unique RC ports per sidecar
9. ✅ Liveness probes on sidecars (optional but recommended)

**Why This Works:**
- Sidecars and main container share same network namespace (pod boundary)
- FUSE mounts created by sidecars propagate to main container
- Works on ANY node (no cross-node mount dependencies)
- High availability (no hard node constraints)

**When to Use:**
- FUSE mounts (rclone, sshfs, s3fs, etc.)
- Multi-node Kubernetes clusters
- Apps requiring cloud storage integration
- Media stacks, ML pipelines, data processing

**When NOT to Use:**
- Single-node clusters (standalone rclone works fine)
- Non-FUSE mounts (NFS, iSCSI don't need sidecars)
- Apps with >50 replicas (resource overhead too high)
