# Hybrid Media Stack Architecture

Comprehensive architecture reference for the OpenShift Hybrid-Converged Media Stack. Extracted from "Project Design - HybridMedia Stack.md" (v1.0).

## Executive Summary

**Purpose:** High-availability media streaming and archival solution combining cloud storage (infinite capacity) with local TrueNAS storage (permanent library).

**Key Capabilities:**
- **Infinite Streaming**: Real-Debrid and TorBox for on-demand content without local storage
- **Dual-Pipeline Storage**: Automated routing between cloud (streaming) and local (archival)
- **Unified Namespace**: Single Plex library view combining cloud and local sources
- **Advanced Discovery**: Netflix-style request system via Overseerr with Trakt/Mdblist automation

## Infrastructure Topology

### Compute Layer (OpenShift)

**Platform:** Red Hat OpenShift 4.20 (Kubernetes 1.28)

**Node Architecture:**
- **Node 2**: HP ProLiant BL460c G7 (4-port 1G bonded + 10G NIC)
- **Node 3**: HP ProLiant BL460c G7 (4-port 1G bonded + 10G NIC)
- **Node 4**: HP ProLiant BL460c G1 (2-port 1G hybrid - limited networking)

**Scheduling Strategy:**
- **Preferred**: Node 2/3 for superior networking (10G) and CPU
- **Avoided**: Node 4 due to 2-port limitation and VLAN 160 issues
- **Method**: `nodeAffinity` with `preferredDuringSchedulingIgnoredDuringExecution` (NOT hard nodeSelector)

**Security Context:**
- **SCC Required**: `privileged` (for FUSE filesystem mounting)
- **Justification**: Rclone mounts WebDAV as FUSE filesystem requiring `/dev/fuse` access
- **Applied To**: Rclone sidecar containers only (not main app containers)

### Storage Layer (Hybrid)

#### Physical Storage (TrueNAS Scale 25.10)

**Protocol:** NFS v4.1
**Access Mode:** RWX (ReadWriteMany)
**Network:** VLAN 160 (172.16.160.0/24)
**Address:** 172.16.160.100
**CSI Driver:** Democratic-CSI (image: `next` tag required for TrueNAS 25.10)

**Dataset Structure:**
```
/mnt/tank/media/
├── archive/          # High-capacity permanent storage (4K Remuxes, Usenet downloads)
│   ├── Movies/       # 60GB+ per file, HEVC/HDR, DTS-HD MA audio
│   └── Shows/        # Complete seasons, highest quality available
├── stream/           # Low-capacity symlink farm (metadata only)
│   ├── Movies/       # Symlinks → /mnt/media/zurg/__all__ or /mnt/media/torbox/torrents
│   └── Shows/        # Symlinks created by rdt-client for cloud content
└── config/           # Application persistent data
    ├── plex/         # Plex database, metadata, thumbnails
    ├── sonarr/       # Sonarr database, indexer configs
    ├── radarr/       # Radarr database, custom formats
    └── rclone/       # Rclone config files (credentials)
```

**Storage Classes:**
- `truenas-nfs-main`: Democratic-CSI provisioner for media workloads
- Retention: Manual (no auto-delete)
- Reclaim Policy: Retain

**Capacity Planning:**
- **Archive**: 8TB allocated (currently 2.5TB used)
- **Stream**: 100GB allocated (symlinks + metadata)
- **Config**: 500GB allocated (databases + thumbnails)

#### Cloud Storage (Virtual)

**Real-Debrid (Primary Cloud)**
- **Mount Tool**: Zurg (legacy/library access)
- **Protocol**: WebDAV over HTTPS
- **Cache Policy**: VFS cache mode `full` (pre-cache metadata)
- **Polling**: 10s intervals for new content detection
- **Mount Path**: `/mnt/media/zurg/__all__/`
- **Content**: 25,000+ cached torrents (Movies, Shows)
- **Limitations**: 200+ simultaneous connections before throttling

**TorBox (Active Downloads)**
- **Mount Tool**: Rclone native WebDAV
- **Protocol**: WebDAV over HTTPS
- **Cache Policy**: VFS cache mode `full`
- **Polling**: 10s intervals
- **Mount Path**: `/mnt/media/torbox/torrents/`
- **Content**: Active downloads + Usenet cache
- **Provider Switch**: rdt-client switched from Real-Debrid to TorBox (2025-12-22)

**Why Two Cloud Providers?**
1. **Zurg/Real-Debrid**: Historical library (existing content, stable)
2. **TorBox/rdt-client**: New downloads (active pipeline, Usenet support)
3. **Redundancy**: Fallback if one provider down or rate-limited
4. **Usenet Rescue**: TorBox can download Usenet and stream without local storage

## Component Architecture (4 Zones)

### Zone 1: Cloud Gateway (Connectivity Layer)

**Role:** Establish and maintain connections to external cloud providers. Export as local filesystems.

**Components:**

#### Zurg (Legacy Library)
- **Image**: `ghcr.io/debridmediamanager/zurg-testing:latest`
- **Purpose**: Mount Real-Debrid cached torrents via WebDAV
- **Config Highlights**:
  - `retain_folder_name_extension: true` (preserve original names)
  - `auto_delete_rar_torrents: true` (cleanup archives)
  - `on_library_update: sh|/config/update_plex.sh` (notify Plex)
- **Deployment**: Standalone pod OR sidecar (sidecars preferred)
- **Port**: 8080 (WebDAV), 9999 (Web UI)

#### Rclone (TorBox Mount)
- **Image**: `docker.io/rclone/rclone:latest`
- **Purpose**: Mount TorBox WebDAV as FUSE filesystem
- **Args**:
  ```bash
  mount torbox: /mnt/media/torbox \
    --config=/config/rclone/rclone.conf \
    --allow-other \
    --vfs-cache-mode=full \
    --poll-interval=10s \
    --rc --rc-no-auth --rc-addr=:5573
  ```
- **Deployment**: Sidecar container in EVERY media app pod
- **Security**: `privileged: true` required for FUSE

#### rdt-client (Download Orchestrator)
- **Image**: `ghcr.io/rogerfar/rdtclient:latest`
- **Purpose**: Receive magnet links, push to TorBox, create symlinks
- **Provider**: TorBox (switched from Real-Debrid 2025-12-22)
- **Integration**: Webhook receiver for Sonarr/Radarr
- **Output**: Symlinks in `/mnt/media/stream` → cloud paths
- **Port**: 6500 (Web UI)

#### Riven (Backup Orchestrator)
- **Image**: `spoked/riven:latest`
- **Purpose**: Search Usenet when torrents unavailable
- **Flow**: TMDB request → Usenet indexers → TorBox download → symlink
- **Use Case**: Obscure/niche content not on torrent trackers
- **Port**: 8080 (Web UI)

**Mounts:**
- **Read/Write**: `/mnt/media/stream` (TrueNAS NFS - creates symlinks)
- **Export**: `/mnt/media/zurg` (Zurg WebDAV mount)
- **Export**: `/mnt/media/torbox` (Rclone WebDAV mount)

**Node Constraint:**
- **Historical**: Pinned to Node 4 (required for symlink resolution)
- **Current**: Sidecars on ALL nodes (resolved via sidecar pattern)

### Zone 2: Managers (Logic Layer)

**Role:** Library management, metadata retrieval, download decisions, quality profiles.

**Components:**

#### Sonarr (TV Shows)
- **Image**: `lscr.io/linuxserver/sonarr:latest`
- **Purpose**: TV show library manager
- **Root Folders**:
  - `/mnt/media/stream` (cloud pipeline - default)
  - `/mnt/media/archive` (local pipeline - manual selection)
- **Indexers**: Jackett (torrents), Prowlarr (unified)
- **Download Client**: rdt-client (TorBox provider)
- **Port**: 8989 (Web UI)

#### Radarr (Movies)
- **Image**: `lscr.io/linuxserver/radarr:latest`
- **Purpose**: Movie library manager
- **Root Folders**:
  - `/mnt/media/stream` (cloud pipeline - default)
  - `/mnt/media/archive` (local pipeline - "Archive Profile")
- **Custom Formats**: Prefer HEVC, HDR, Atmos for archive
- **Download Client**: rdt-client (TorBox provider)
- **Port**: 7878 (Web UI)

#### SABnzbd (Usenet Downloader)
- **Image**: `lscr.io/linuxserver/sabnzbd:latest`
- **Purpose**: Direct Usenet downloads to local TrueNAS
- **Output**: `/mnt/media/archive` (permanent storage)
- **Indexers**: NZBGeek, NZBFinder, DrunkenSlug
- **Use Case**: Archive profile OR TorBox rescue failed
- **Port**: 8080 (Web UI)

#### Bazarr (Subtitle Manager)
- **Image**: `lscr.io/linuxserver/bazarr:latest`
- **Purpose**: Automatic subtitle download and sync
- **Sources**: OpenSubtitles, Subscene, Addic7ed
- **Monitors**: Both `/mnt/media/stream` and `/mnt/media/archive`
- **Port**: 6767 (Web UI)

**Integration:** All managers connect to Zone 1 via internal Kubernetes Services (ClusterIP). No external exposure required.

**Node Constraint:**
- **Historical**: Pinned to Node 4 (shared FUSE mount with Zone 1)
- **Current**: Sidecars on ANY node (Node 2/3 preferred for 10G NIC)

### Zone 3: Player (Delivery Layer)

**Role:** Content playback, transcoding, user experience.

**Components:**

#### Plex Media Server
- **Image**: `lscr.io/linuxserver/plex:latest`
- **Purpose**: Primary media player and library interface
- **Libraries**:
  - **Movies**: Scans `/mnt/media/stream` AND `/mnt/media/archive` (unified view)
  - **TV Shows**: Scans `/mnt/media/stream` AND `/mnt/media/archive`
- **Transcoding**: Hardware acceleration (Intel QuickSync when available)
- **Port**: 32400 (PMS), 443 (HTTPS via Nginx sidecar)
- **Exposure**: MetalLB LoadBalancer on Node 2/3

#### Rclone Sidecars
- **rclone-zurg**: Mounts Real-Debrid cache
- **rclone-torbox**: Mounts TorBox downloads
- **Deployment**: Co-located in same pod as Plex
- **Purpose**: Ensure symlinks resolve (cloud paths accessible)

#### Nginx Sidecar (Optional)
- **Image**: `docker.io/nginx:latest`
- **Purpose**: TLS termination for Plex
- **Certificate**: Let's Encrypt wildcard cert via Cert-Manager
- **Port**: 443 (HTTPS) → 32400 (PMS)

**Network:**
- **Service**: LoadBalancer (MetalLB IP: 172.16.100.x)
- **Route**: `plex.apps.ossus.sigtomtech.com` (TLS passthrough)

**Node Constraint:**
- **Preferred**: Node 2/3 for superior networking and CPU
- **Fallback**: Node 4 allowed if Node 2/3 unavailable

### Zone 4: Discovery (User Interface)

**Role:** Content discovery, user requests, trending lists, automation.

**Components:**

#### Overseerr
- **Image**: `sctx/overseerr:latest`
- **Purpose**: Netflix-style request and discovery interface
- **Features**:
  - TMDB trending lists
  - IMDB "Coming Soon" integration
  - User request system with approval workflow
  - Plex Discover integration
- **Automation**:
  - **Trakt**: Auto-request highly-rated content (>80% score)
  - **Mdblist**: Auto-request genre lists (e.g., "80s Cartoons")
- **Integration**: Sends requests to Sonarr/Radarr via API
- **Port**: 5055 (Web UI)
- **Exposure**: Route `overseerr.apps.ossus.sigtomtech.com`

#### Plex Discover (Native)
- **Built-in**: Plex client native discovery
- **Features**: Cross-platform availability checks
- **Integration**: Automatic with Plex Pass subscription

**Node Constraint:** None (stateless, can run anywhere)

## Data Flow Scenarios

### Scenario A: The Weekly Stream (Default Pipeline)

**Use Case:** User requests "New Show S01E05" OR Sonarr detects new episode release

**Flow:**
```
1. User Request (Overseerr) OR Sonarr Auto-Search
   ↓
2. Sonarr searches indexers (Jackett/Prowlarr)
   ↓ (finds torrent magnet link)
3. Sonarr sends magnet → rdt-client (Zone 1)
   ↓
4. rdt-client pushes magnet → TorBox API
   ↓
5. TorBox downloads torrent to cloud cache
   ↓
6. rdt-client polls TorBox for completion
   ↓
7. rdt-client creates symlink:
   /mnt/media/stream/Shows/NewShow/S01E05.mkv → /mnt/media/torbox/torrents/xyz/file.mkv
   ↓
8. Sonarr detects file, imports to library
   ↓
9. Plex scans /mnt/media/stream, follows symlink
   ↓
10. Plex plays file directly from TorBox mount (rclone-torbox sidecar)
```

**Storage Impact:**
- **Local**: 0 GB (symlink only, ~100 bytes)
- **Cloud**: Temporary (TorBox cache, auto-expires after 30 days idle)

**Latency:**
- **Download**: 30 seconds (TorBox fetches from seeders)
- **Import**: 5 seconds (symlink creation + Sonarr scan)
- **Playback**: Instant (streaming from TorBox)

### Scenario B: The Archive (Keeper Pipeline)

**Use Case:** User requests "Movie X" with "Archive Profile" OR tags as "Local" in Overseerr

**Flow:**
```
1. User Request (Overseerr) with "4K Remux" profile
   ↓
2. Radarr searches Usenet indexers (Prowlarr → NZBGeek)
   ↓ (finds 4K Remux NZB, 60GB)
3. Radarr sends NZB → SABnzbd (Zone 2)
   ↓
4. SABnzbd downloads from Usenet servers
   ↓ (parallel connections, 10-30 minutes)
5. SABnzbd extracts to /mnt/media/archive/Movies/MovieX.4K.Remux.mkv
   ↓
6. Radarr detects file, imports to library
   ↓
7. Plex scans /mnt/media/archive, adds to library
   ↓
8. Plex plays file from TrueNAS local storage (no cloud dependency)
```

**Storage Impact:**
- **Local**: 60 GB (permanent, RAID-Z2 protected)
- **Cloud**: 0 GB (no cloud provider involved)

**Quality:**
- **Video**: 4K HEVC 10-bit HDR
- **Audio**: DTS-HD Master Audio 7.1
- **Bitrate**: 80-120 Mbps (pristine quality)

**Use Case:**
- Personal favorites (rewatched frequently)
- Content likely to be removed from streaming (licensing)
- Maximum quality for home theater setup

### Scenario C: The Rescue (Obscure Content)

**Use Case:** Content unavailable on torrents OR Real-Debrid cache expired

**Flow:**
```
1. User Request (Overseerr) for "Obscure Anime 1995"
   ↓
2. Sonarr searches torrent indexers (no results)
   ↓
3. Riven (Zone 1) triggered as fallback
   ↓
4. Riven searches Usenet indexers (NZBGeek, DrunkenSlug)
   ↓ (finds rare NZB)
5. Riven sends NZB → TorBox Usenet downloader
   ↓
6. TorBox downloads to cloud cache (no local storage used)
   ↓
7. Riven creates symlink:
   /mnt/media/stream/Shows/ObscureAnime/S01E01.mkv → /mnt/media/torbox/usenet/xyz/file.mkv
   ↓
8. Plex scans, plays from TorBox Usenet cache (rclone-torbox sidecar)
```

**Storage Impact:**
- **Local**: 0 GB (symlink only)
- **Cloud**: Temporary (TorBox Usenet cache, 30 days)

**Advantage:**
- Access to Usenet backlog (10+ years retention)
- No local storage cost for one-time watches
- Faster than traditional Usenet download + import

## Storage Topology Deep Dive

### Mount Structure (Pod Perspective)

```
/mnt/media/                           <- PVC (TrueNAS NFS, RWX)
├── zurg/                             <- FUSE mount (rclone-zurg sidecar)
│   └── __all__/                      <- Real-Debrid cached torrents
│       ├── Movies/
│       │   ├── MovieA.2024.1080p.mkv
│       │   └── MovieB.2023.4K.mkv
│       └── Shows/
│           └── ShowX/
│               └── Season 01/
│                   ├── S01E01.mkv
│                   └── S01E02.mkv
├── torbox/                           <- FUSE mount (rclone-torbox sidecar)
│   ├── torrents/                     <- TorBox active downloads
│   │   └── abc123/
│   │       └── file.mkv
│   └── usenet/                       <- TorBox Usenet cache (Riven)
│       └── xyz789/
│           └── file.mkv
├── archive/                          <- TrueNAS NFS (permanent)
│   ├── Movies/
│   │   └── MovieC.2024.4K.Remux.mkv (60GB)
│   └── Shows/
│       └── ShowY/
│           └── Season 01/
│               └── S01E01.4K.mkv (8GB)
├── stream/                           <- TrueNAS NFS (symlinks)
│   ├── Movies/
│   │   ├── MovieA → /mnt/media/zurg/__all__/Movies/MovieA.mkv
│   │   └── MovieB → /mnt/media/torbox/torrents/abc123/file.mkv
│   └── Shows/
│       └── ShowX → /mnt/media/zurg/__all__/Shows/ShowX/
└── config/                           <- TrueNAS NFS (app state)
    ├── plex/
    │   ├── Library/
    │   └── Preferences.xml
    ├── sonarr/
    │   └── sonarr.db
    └── radarr/
        └── radarr.db
```

### Volume Types Explained

#### PVC (media-library-pvc)
- **Type**: NFS (TrueNAS)
- **Size**: 10TB provisioned
- **Access Mode**: RWX (shared across all pods)
- **Mount Path**: `/mnt/media` (all apps)
- **Contains**: `archive/`, `stream/`, `config/` directories

#### emptyDir (pod-local)
- **Type**: Ephemeral (tmpfs or node disk)
- **Size**: Limited by node capacity
- **Access Mode**: Pod-local (not shared)
- **Mount Path**: N/A (not used in media stack)
- **Alternative**: Considered for FUSE mounts but abandoned due to lack of persistence

#### FUSE Mounts (sidecars)
- **Type**: Virtual filesystem (WebDAV → FUSE)
- **Backend**: Real-Debrid (Zurg) or TorBox (Rclone)
- **Mount Path**: `/mnt/media/zurg` and `/mnt/media/torbox`
- **Propagation**: `Bidirectional` (sidecar → main container)
- **Requirement**: `privileged: true` (access `/dev/fuse`)

### Symlink Resolution

**Problem:** Plex running in container can't follow symlinks to paths outside container filesystem.

**Solution:** Ensure symlink target is mounted inside same container.

**Example:**
```bash
# Symlink created by rdt-client
/mnt/media/stream/Shows/Peacemaker/S02E05.mkv → /mnt/media/torbox/torrents/abc123/file.mkv

# In Plex pod:
# - /mnt/media/stream mounted from PVC ✓
# - /mnt/media/torbox mounted by rclone-torbox sidecar ✓
# - mountPropagation: HostToContainer on main container ✓
# Result: Symlink resolves correctly ✓
```

**Why Sidecars?**
- Standalone rclone pod on Node 2 can't propagate FUSE mount to Plex pod on Node 3
- Kubernetes network namespaces isolate FUSE mounts per-pod
- Sidecar ensures rclone and main app share same network namespace

## Sidecar Pattern Implementation

### Why Sidecars Over Standalone?

**Failed Architecture (Pre-2025-12-23):**
```
Node 2:
- rclone-zurg pod (mounts /mnt/media/zurg)

Node 3:
- plex pod (tries to access /mnt/media/zurg)
- Result: Transport endpoint is not connected
```

**Reason:** FUSE mounts are network namespace-local. Pod on Node 3 sees empty directory.

**Working Architecture (Post-2025-12-23):**
```
Node 3:
- plex pod
  ├── rclone-zurg container (mounts /mnt/media/zurg)
  ├── rclone-torbox container (mounts /mnt/media/torbox)
  └── plex container (accesses mounts via Bidirectional propagation)
- Result: All mounts visible ✓
```

**Trade-offs:**
- **Pro:** Works on ANY node (no affinity required)
- **Pro:** Reliable mount propagation
- **Con:** Higher resource usage (1 rclone per app instead of 1 shared)
- **Con:** More complex pod specs

### Sidecar Components

#### Init Container (init-dirs)
```yaml
initContainers:
- name: init-dirs
  image: docker.io/alpine:latest
  command: ["/bin/sh", "-c", "mkdir -p /mnt/media/zurg /mnt/media/torbox"]
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
```

**Purpose:** Create mount point directories before rclone sidecars start. Prevents "directory not found" errors.

#### Sidecar 1: rclone-zurg
```yaml
- name: rclone-zurg
  image: docker.io/rclone/rclone:latest
  securityContext:
    privileged: true
  args:
  - "mount"
  - "zurg:"
  - "/mnt/media/zurg"
  - "--config=/config/rclone/rclone.conf"
  - "--allow-other"
  - "--vfs-cache-mode=full"
  - "--poll-interval=10s"
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional
  - name: rclone-zurg-config
    mountPath: /config/rclone
    readOnly: true
```

**Purpose:** Mount Real-Debrid via Zurg WebDAV. Provides access to 25,000+ cached torrents.

#### Sidecar 2: rclone-torbox
```yaml
- name: rclone-torbox
  image: docker.io/rclone/rclone:latest
  securityContext:
    privileged: true
  args:
  - "mount"
  - "torbox:"
  - "/mnt/media/torbox"
  - "--config=/config/rclone/rclone.conf"
  - "--allow-other"
  - "--vfs-cache-mode=full"
  - "--poll-interval=10s"
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: Bidirectional
  - name: rclone-config
    mountPath: /config/rclone
    readOnly: true
```

**Purpose:** Mount TorBox WebDAV. Provides access to active downloads + Usenet cache.

#### Main Container (e.g., Plex)
```yaml
- name: plex
  image: lscr.io/linuxserver/plex:latest
  volumeMounts:
  - name: media-storage
    mountPath: /mnt/media
    mountPropagation: HostToContainer  # <- NOT Bidirectional
  - name: media-storage
    mountPath: /config
    subPath: config/plex
```

**Purpose:** Main application. Uses `HostToContainer` propagation to RECEIVE mounts from sidecars (one-way).

### mountPropagation Explained

| Mode | Direction | Use Case |
|------|-----------|----------|
| `None` | Isolated | Default (no propagation) |
| `HostToContainer` | Host → Container | Main app receives mounts FROM sidecars |
| `Bidirectional` | Both ways | Sidecar creates mounts visible to host AND other containers |

**Correct Pattern:**
- **Sidecars**: `Bidirectional` (create FUSE mounts)
- **Main Container**: `HostToContainer` (receive FUSE mounts)

**Wrong Pattern:**
- **All containers**: `None` → Mounts not visible ❌
- **Main container**: `Bidirectional` → Unnecessary (not creating mounts) ❌

## Node Affinity Strategy

### Preferred vs. Required

**Historical (Pre-2025-12-23): Hard Constraint**
```yaml
# BAD: Locks app to specific node
spec:
  nodeSelector:
    kubernetes.io/hostname: wow-ocp-node4
```

**Problem:**
- App can't start if Node 4 unavailable (single point of failure)
- No load balancing across nodes
- Maintenance requires manual rescheduling

**Current (Post-2025-12-23): Soft Preference**
```yaml
# GOOD: Prefers Node 2/3 but allows flexibility
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

**Benefits:**
- Scheduler tries Node 2/3 first (10G NIC, better CPU)
- Falls back to Node 4 if Node 2/3 full or unavailable
- High availability (app always scheduled)
- Load balancing across preferred nodes

### Why Prefer Node 2/3?

| Node | NICs | CPU | Storage Network | Media Suitability |
|------|------|-----|-----------------|-------------------|
| Node 2 | 4x1G bond + 10G | Xeon X5650 (12T) | ✓ VLAN 160 stable | **Excellent** |
| Node 3 | 4x1G bond + 10G | Xeon X5650 (12T) | ✓ VLAN 160 stable | **Excellent** |
| Node 4 | 2x1G hybrid | Xeon E5440 (4T) | ⚠ VLAN 160 flaky | **Avoid** |

**Recommendation:** Use Node 2/3 for:
- High bandwidth apps (Plex transcoding)
- Media managers (Sonarr/Radarr parallel searches)
- Apps with frequent TrueNAS access

## Security Context Requirements

### Privileged Containers

**Requirement:** FUSE mounts require `privileged: true` for `/dev/fuse` access.

**Applied To:**
- ✓ `rclone-zurg` sidecar
- ✓ `rclone-torbox` sidecar
- ✗ Main app container (Plex, Sonarr, etc.)

**Why Main Container Doesn't Need Privileged:**
- Main container READS from FUSE mount (already established by sidecar)
- Only sidecar needs to CREATE FUSE mount (requires `/dev/fuse`)
- Principle of least privilege (minimize attack surface)

### Service Account Bindings

```bash
# Grant privileged SCC to media-stack service accounts
oc adm policy add-scc-to-user privileged -z plex -n media-stack
oc adm policy add-scc-to-user privileged -z managers -n media-stack
```

**Service Accounts:**
- `plex`: For Zone 3 (Player)
- `managers`: For Zone 2 (Sonarr, Radarr, Bazarr, SABnzbd)
- `cloud-gateway`: For Zone 1 (Zurg, rdt-client, Riven)
- `discovery`: For Zone 4 (Overseerr)

## Networking & Exposure

### Internal (ClusterIP)

**Services (in-cluster only):**
- `sonarr:8989` (Zone 2 → Zone 1 communication)
- `radarr:7878` (Zone 2 → Zone 1 communication)
- `rdt-client:6500` (Zone 1 webhook receiver)
- `bazarr:6767` (Zone 2 → Zone 3 integration)

### External (LoadBalancer + Routes)

**Plex:**
- **Service Type**: LoadBalancer (MetalLB)
- **IP**: 172.16.100.x (dynamically assigned from pool)
- **Port**: 32400 (PMS), 443 (HTTPS via Nginx sidecar)
- **Route**: `plex.apps.ossus.sigtomtech.com` (TLS passthrough)
- **Certificate**: Let's Encrypt wildcard cert

**Overseerr:**
- **Service Type**: ClusterIP
- **Route**: `overseerr.apps.ossus.sigtomtech.com` (TLS edge termination)
- **Port**: 5055 (HTTP backend)

**Sonarr/Radarr (Admin Only):**
- **Service Type**: ClusterIP
- **Route**: `sonarr.apps.ossus.sigtomtech.com` (TLS edge termination)
- **Auth**: Basic auth via OpenShift OAuth proxy

## Lessons Learned

### December 2025 Sidecar Migration

From PROGRESS.md (2025-12-23):

> **ARCHITECTURAL UPGRADE**: Migrated entire media stack to Sidecar Pattern.
> - **Change**: Added `rclone-zurg` and `rclone-torbox` containers to every deployment (Plex, Sonarr, Radarr, Bazarr, Sabnzbd, Riven, Rdt-client).
> - **Result**: Resolved FUSE/NFS mount propagation issues. Apps no longer need to be pinned to a single node.
> - **Optimization**: Replaced hard `nodeSelector` with `nodeAffinity` (preferred) for Node 2 and 3 to utilize 10G NICs and superior CPU resources.
> - **Outcome**: Verified cross-pod mount consistency and successful deployment to Node 3 via ArgoCD.

**Key Takeaways:**
1. **Standalone rclone pods don't work** in Kubernetes due to network namespace isolation
2. **Sidecar pattern is mandatory** for FUSE mounts in multi-node clusters
3. **mountPropagation: Bidirectional** is critical for sidecar → main container visibility
4. **nodeAffinity (preferred)** beats hard nodeSelector for high availability
5. **Privileged SCC** only required for sidecars, not main containers

### Provider Switch (TorBox)

From PROGRESS.md (2025-12-22):

> Switched `rdt-client` provider to TorBox to resolve Zurg/Real-Debrid sync and symlink issues.

**Problem:** Real-Debrid rate limiting causing failed symlinks and Zurg cache staleness.

**Solution:** Migrate active downloads to TorBox while keeping Zurg for historical library.

**Result:** Dual-provider architecture with Zurg (legacy) + TorBox (active).

## Future Enhancements

### Planned Features

1. **Jellyfin Integration**: Add Jellyfin as alternative player (Zone 3)
2. **Tdarr**: Add transcode automation for archive pipeline (convert to HEVC)
3. **Requestrr**: Discord bot for Overseerr requests
4. **Autoscan**: Real-time Plex library updates (replace polling)
5. **Unmanic**: GPU-accelerated transcoding for archive optimization

### Capacity Planning

**Current Usage:**
- **Archive**: 2.5TB / 8TB (31%)
- **Stream**: 45GB / 100GB (45% - symlinks + metadata)
- **Config**: 120GB / 500GB (24%)

**Projected (1 Year):**
- **Archive**: 6TB (assuming 1 movie/week @ 60GB)
- **Stream**: 80GB (linear growth with request volume)
- **Config**: 200GB (Plex metadata growth)

**Action Items:**
- Monitor TrueNAS capacity monthly
- Expand archive dataset if >80% full
- Implement automatic cleanup for stream symlinks (>90 days old)

## Quick Reference

### Zone Summary

| Zone | Role | Apps | Node Preference | External Access |
|------|------|------|-----------------|-----------------|
| Zone 1 | Cloud Gateway | Zurg, Rclone, rdt-client, Riven | Node 2/3 | No (internal only) |
| Zone 2 | Managers | Sonarr, Radarr, SABnzbd, Bazarr | Node 2/3 | Admin only (OAuth) |
| Zone 3 | Player | Plex | Node 2/3 | Yes (LoadBalancer) |
| Zone 4 | Discovery | Overseerr | Any | Yes (Route) |

### Storage Summary

| Path | Backend | Size | Purpose | Retention |
|------|---------|------|---------|-----------|
| `/mnt/media/zurg/__all__` | Real-Debrid (FUSE) | Infinite | Legacy library | 30 days idle |
| `/mnt/media/torbox/torrents` | TorBox (FUSE) | Infinite | Active downloads | 30 days idle |
| `/mnt/media/archive` | TrueNAS NFS | 8TB | Permanent 4K | Permanent |
| `/mnt/media/stream` | TrueNAS NFS | 100GB | Symlinks | 90 days cleanup |
| `/mnt/media/config` | TrueNAS NFS | 500GB | App state | Permanent |

### Deployment Checklist

For any new media app:

- [ ] Includes `init-dirs` initContainer
- [ ] Includes `rclone-zurg` sidecar with `privileged: true`
- [ ] Includes `rclone-torbox` sidecar with `privileged: true`
- [ ] Sidecars use `mountPropagation: Bidirectional`
- [ ] Main container uses `mountPropagation: HostToContainer`
- [ ] Service account has `privileged` SCC binding
- [ ] Node affinity prefers Node 2/3 (NOT hard nodeSelector)
- [ ] Mounts PVC `media-library-pvc` at `/mnt/media`
- [ ] Secrets `rclone-zurg-config` and `rclone-config` attached
- [ ] Resource limits set for sidecars (prevent runaway CPU)

## Related Documentation

- **SKILL.md**: Operational workflows and troubleshooting
- **sidecar-pattern.md**: Detailed sidecar implementation guide
- **Project Design - HybridMedia Stack.md**: Original design document (this is a summary)
- **PROGRESS.md**: Historical changes and lessons learned
