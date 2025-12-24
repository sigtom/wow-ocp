
# **Project Design: OpenShift Hybrid-Converged Media Stack (v1.0)**

## **1\. Executive Summary**

This project architects a high-availability media streaming and archival solution running on **Red Hat OpenShift**, utilizing a **TrueNAS** storage backend and a **Hybrid Cloud** strategy. The system is designed to minimize local storage usage for daily consumption ("Streaming") while maintaining granular control for high-quality permanent libraries ("Archiving").  
**Key Capabilities:**

* **Infinite Streaming:** Leverages Real-Debrid and TorBox to stream content on-demand without local storage overhead.  
* **Dual-Pipeline Storage:** Automated logic to route "watch-and-forget" content to the Cloud and "keeper" content to Local TrueNAS storage.  
* **Unified Namespace:** All media (Cloud and Local) appears in a single Plex library via symlink orchestration.  
* **Advanced Discovery:** Centralized "Netflix-style" request and discovery system powered by Overseerr, integrating with Plex Watchlists and Trakt/Mdblist automation.

## **2\. Infrastructure Topology**

### **A. Compute Layer (OpenShift)**

The application stack is containerized and orchestrated by OpenShift. It utilizes specific **Security Context Constraints (SCC)** (specifically privileged and anyuid) to enable FUSE file system mounting (Rclone) within pods.

### **B. Storage Layer (Hybrid)**

1. **Physical (TrueNAS):**  
   * **Protocol:** NFS (RWX \- ReadWriteMany).  
   * **Dataset Structure:**  
     * /mnt/tank/media/archive: High-capacity storage for permanent 4K Remuxes and Usenet downloads.  
     * /mnt/tank/media/stream: Low-capacity storage for Symlinks and metadata.  
     * /mnt/tank/media/config: Persistent application configurations.  
2. **Cloud (Virtual):**  
   * **Real-Debrid:** Mounted via **Zurg** (WebDAV). Primary source for cached torrents.  
   * **TorBox:** Mounted via **Rclone** (WebDAV). Secondary source for streaming Usenet NZBs.

## **3\. Component Architecture**

The stack is divided into four logical zones (Pods/Deployments) to ensure separation of concerns while maintaining shared access to mounts.

### **Zone 1: The Cloud Gateway (Connectivity)**

* **Role:** Establishes connections to external cloud providers and exposes them as local file systems.
* **Components:**
  * **Zurg:** Legacy/Library access for existing Real-Debrid content.
  * **Rclone:** Mounts TorBox WebDAV for *active* new downloads.
  * **rdt-client:** Switched to **TorBox** provider. Receives magnet links, initiates Cloud downloads, and generates local symlinks pointing to the TorBox mount.
  * **Riven:** Backup orchestrator.
* **Mounts:** Reads/Writes to TrueNAS /stream (Symlinks). Exports /mnt/zurg and /mnt/torbox via shared volume.
* **Constraint:** **MUST** run on the same node as Plex (Node 4) to ensure FUSE mount visibility and symlink resolution.

### **Zone 2: The Managers (Logic)**

* **Role:** Library management, metadata retrieval, and decision making.
* **Components:**
  * **Sonarr / Radarr:** Manage TV/Movie libraries. Configured with two Root Folders (/stream and /archive).
  * **SABnzbd:** Local Usenet downloader (Zone 2 specific).
  * **Bazarr:** Subtitle management.
* **Integration:** Connects to Zone 1 via internal Service networking.
* **Constraint:** Pinned to Node 4 to share the stable FUSE mount environment.

### **Zone 3: The Player (Delivery)**

* **Role:** Content playback and transcoding.
* **Components:**
  * **Plex Media Server:** The primary playback engine.
  * **Sidecars:** Includes lightweight **Zurg** and **Rclone** sidecar containers.
* **Network:** Exposes port 32400 via LoadBalancer (MetalLB) on Node 4.

### **Zone 4: The Discovery Layer (User Experience)**
* **Role:** Frontend interface for content discovery, trending lists, and user requests.  
* **Components:**  
  * **Overseerr:** The "Storefront." Aggregates TMDB/IMDb data into "Trending," "Upcoming," and "New Release" lists.  
  * **Plex Discover:** Native Plex integration for cross-platform availability checks.  
* **Automation:** Syncs with **Trakt** and **Mdblist** to automatically request highly-rated content or specific genres (e.g., "80s Cartoons") without user intervention.

## **4\. Data Flow Workflows**

### **Scenario A: The Weekly Stream (Default)**

1. **Trigger:** User requests "Show X" in Overseerr OR Sonarr detects a new episode release.  
2. **Route:** Sonarr sends magnet to **rdt-client** (Zone 1).  
3. **Process:** rdt-client pushes to Real-Debrid \-\> Zurg caches it \-\> rdt-client creates symlink in TrueNAS /stream.  
4. **Result:** Plex plays the file instantly from the cloud. Local storage cost: 0GB.

### **Scenario B: The Archive (Keeper)**

1. **Trigger:** User requests "Movie Y" in Overseerr and selects "Archive Profile" OR tags it as "Local".  
2. **Route:** Sonarr sends NZB to **SABnzbd** (Zone 2).  
3. **Process:** SABnzbd downloads from Usenet Indexers \-\> Extracts to TrueNAS /archive.  
4. **Result:** High-bitrate file stored permanently on local RAID.

### **Scenario C: The Rescue (Obscure Content)**

1. **Trigger:** Content is unavailable on Torrents/Real-Debrid.  
2. **Route:** **Riven** (Zone 1\) searches Usenet indexers.  
3. **Process:** Riven sends NZB to **TorBox** \-\> TorBox downloads to cloud \-\> Riven symlinks from TorBox mount.  
4. **Result:** User streams Usenet content without local download.

## **5\. Next Steps for Implementation**

1. **Provision Storage:** Verify TrueNAS RWX NFS share creation for media dataset.  
2. **Secrets Management:** Create OpenShift Secrets for Real-Debrid API, TorBox API (Rclone config), and Usenet Indexer keys.  
3. **Deploy Stack:** Apply Kubernetes Manifests for Zones 1-4.  
4. **Configure Ingress:** Expose Overseerr and Plex via OpenShift Routes for external access.