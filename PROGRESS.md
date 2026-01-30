# Project Progress (v2.0)

- [2026-01-30]: **IRONCLAD VM PROVISIONING & STACK CONSOLIDATION**
    - **Infrastructure Pivot**: Migrated the DUMB stack from a flakey LXC environment to a stable, isolated Proxmox VM. This provides hard kernel isolation and native FUSE support, ending the "zombie mount" slog.
    - **Master Engine Hardening**: Re-engineered the `provision_vm_generic` role to be forcefully idempotent. Implemented a "Break Glass" provisioning pattern that uses direct Proxmox CLI commands to override sticky template inheritance issues (like inherited VLAN tags).
    - **Automatic Disk Scaling**: Integrated automatic root partition expansion (`growpart` + `resize2fs`) into the provisioning role, ensuring the VM has the full 100GB capacity before the first large package install.
    - **Stack Consolidation**: Merged the entire media ecosystem (Plex, Riven, Arrs, Sabnzbd, qBittorrent, Tautulli, Bazarr) into a single, unified Docker Compose deployment on the `dumb` VM.
    - **Real-Debrid Transition**: Fully purged the stack of Torbox references. Swapped all configurations to **Real-Debrid** and verified API connectivity via the `dumb` container logs.
    - **AAP Resilience**:
        - Resolved the "Nautobot Dynamic Sync" failure by fixing missing API tokens in the AAP credentials.
        - Switched the inventory endpoint to an IP address (`172.16.100.15`) to ensure sync reliability even when cluster DNS is down.
    - **Dev Loop Optimization**: Established a "Local-First" development workflow, allowing for rapid iteration and verification before promoting code to the 10-minute AAP sync cycle.
    - **Outcome**: Fresh `xlarge` VM is UP, Docker is verified, and the consolidated stack is currently initializing its first-run environment.

- [2026-01-24]: **DUMB STACK RESTORATION & CLEAN SLATE**

    - **Mount Architecture Repair**: Identified and resolved a critical issue where the LXC host had **32 duplicate FUSE mounts** of `torbox_direct`. This caused severe I/O errors and prevented Riven from verifying file existence.
    - **Host-Only Mount Policy**: Enforced a "Host-Only" mount strategy. Disabled all internal `rclone` and `zurg` instances within the `dumb` container to prevent race conditions. The container now strictly consumes the host's clean mount.
    - **Cache Stabilization**: Reconfigured the host's Rclone service to use the dedicated SSD (`/mnt/vfs_cache`) and enabled Remote Control (`--rc`) for instant cache refreshing.
    - **Library Purge & Rebuild**:
        - Identified 250+ "Zombie" requests in Riven from a previous Overseerr database state.
        - Executed a surgical purge of Riven's database and the Torbox cloud storage, deleting all 45 orphaned torrents.
        - Established **Overseerr** as the single Source of Truth.
        - Successfully re-ingested requests for **The Lord of the Rings** and restored full functionality.
    - **Ranking Optimization**: Updated Riven's ranking profile to strictly prioritize **Remux** and **English** releases, ensuring high-quality 4K files are selected over lower-quality multi-language rips.
    - **Permission Fix**: Corrected ownership of the `riven_symlinks` directory to `1000:1000`, resolving "Permission Denied" errors that blocked symlink creation.
    - **Final Clean Slate**:
        - Truncated Riven's PostgreSQL database to remove all residual items.
        - Disabled **Plex Watchlist** sync to prevent library pollution.
        - Verified file system contains **only** *The Fellowship of the Ring* and *The Two Towers*.
    - **Outcome**: The system is now healthy, self-healing, and actively processing the library queue with zero "zombie" items.

- [2026-01-23]: **HYBRID MEDIA INFRASTRUCTURE HARDENING & MASS MIGRATION**
    - **VFS Cache Isolation**: Successfully provisioned a dedicated **250GB SSD virtual disk** on Proxmox and attached it to the DUMB LXC. Isolated the Rclone VFS cache to this disk, permanently resolving the "Root Disk Full" crash risk.
    - **4K Streaming Optimization**: Tuned Rclone VFS with **100GB capacity, 2GB read-ahead, and 256MB buffers**. These settings allow the system to survive VPN jitter and stream high-bitrate 4K Remuxes seamlessly.
    - **Infrastructure Unification**: Established a **Host-Level Direct Mount** (`torbox_direct`) on the LXC host. This unified "Super-Mount" sees both Torrents and Usenet files in a single flat list, bypassing Docker's FUSE propagation bugs.
    - **Systematic Path Alignment**: Re-architected the stack to use the new unified mount. All apps (Plex, Riven, Sonarr, Radarr) now look at the host mount for a single source of truth.
    - **Mass Migration**: Successfully migrated **373 mainstream movies** from the NAS to the Cloud using an automated "Delete & Re-add" workflow. This ensured 100% path accuracy and fresh 4K metadata for every title.
    - **Automated Usenet Bridge**: Deployed a persistent **Usenet-to-Cloud Bridge** for rare content. Automated the upload of the entire **M.A.S.K.** series from NZBGeek directly to the cloud.
    - **Stability Pass**: Applied a **Global MeGusta Block** in Prowlarr to prevent memory-exhaustion crashes. Purged corrupted *Gundam* cache chunks.
    - **Automation Integrity**: Fully codified all surgical fixes into `@automation/` templates and created a new post-deployment API configuration playbook.

    ### **Unified Cloud Architecture (v1.0)**
    ```mermaid
    graph TD
        subgraph "LXC Host (Wow-Prox1)"
            HM["Host Mount: /mnt/debrid/torbox_direct"]
            SSD["250GB SSD Cache"]
            USB["Usenet Bridge Daemon"]
            HM --- SSD
        end

        subgraph "Docker Container (DUMB)"
            Riven["Riven (Librarian)"]
            Plex["Plex (Player)"]
            Arrs["Radarr/Sonarr (Managers)"]
            Decy["Decypharr (Postman)"]
        end

        HM -->|Bind Mount| Riven
        HM -->|Bind Mount| Arrs
        Riven -->|Creates Symlinks| Plex
        Arrs -->|API Commands| Decy
        Decy -->|API Commands| Cloud((Torbox Cloud))
        USB -->|Pushes NZBs| Cloud
        Cloud -.->|WebDAV| HM
    ```

- [2026-01-22]: **HYBRID MEDIA STACK OPTIMIZATION & DATA MIGRATION**
    - **Hybrid Architecture**: Established a "Dual-Path" media engine. Users now use the `archive` tag for permanent NAS storage and the `cloud` tag for instant Debrid (TorBox) streaming.
    - **Path Alignment**: Surgically moved 116+ symlinked titles from stale `decypharr_symlinks` paths to the unified `riven_symlinks` library. Updated Radarr/Sonarr databases via API to match the new filesystem structure.
    - **NAS Reclamation**: Migrated the entire Sonarr library (23 shows) to the Cloud and purged **~442GB** of local video files from the TrueNAS `TV_Shows` share. Reclaimed an additional **~1.2TB** from the `Movies` share by replacing 2015-2025 titles with Cloud versions.
    - **Streaming Performance**:
        - **Direct Play Fix**: Identified that Chrome was forcing 4K transcodes (1200% CPU usage) due to codec limitations. Transitioned user to **Plex MacOS App**, resulting in 0% CPU overhead and seamless Direct Play.
        - **Ultra-Performance VFS**: Configured aggressive Rclone VFS settings (2GB read-ahead, 256MB chunks, 8 transfers) to survive VPN speed fluctuations between Tampa (DC) and Hudson (Home).
        - **Local Network Logic**: Updated Plex `lanNetworks` and Custom Access URLs to ensure Tampa-to-Hudson traffic is treated as local, removing the 20Mbps "Remote" bitrate cap.
    - **Quality Intelligence**: Reprioritized the `Cloud-Unlimited` profile to prefer **Web-DL 2160p** (+2000 score) over Remuxes. This ensures high-quality HDR/DV playback while reducing bandwidth requirements by 75% compared to 100GB Remuxes.
    - **Automation Refinement**: Automated Plex library rescans from three independent triggers (Riven, Radarr/Sonarr, and Plex periodic). Updated `@automation/` Jinja templates to permanently codify these performance settings.
    - **Library Recovery**: Initiated bulk requests in Overseerr for **350+ orphaned or low-quality movies** to ensure the entire TorBox history is symlinked and metadata-rich in Plex.
    - **System Stability**: Resolved a critical "Full Disk" incident on the DUMB LXC by right-sizing the VFS cache limit from 50GB to 20GB and implemented auto-cleanup of old cache chunks.

- [2026-01-21]: **MAJOR ARCHITECTURAL REFACTOR: METADATA-DRIVEN INFRASTRUCTURE**
    - **Inventory Source of Truth**: Successfully migrated from static files/surveys to **Nautobot Dynamic Inventory**.
    - **Nautobot Enrichment**: Surgically aligned Nautobot with the lab state. 14+ hosts (OCP, Proxmox, TrueNAS, MikroTik) are now fully enriched with Primary IPs, hardware specs (CPU/RAM/Disk), and 17+ service definitions.
    - **Physical Topology**: Discovered the 10G copper network layout via automated SNMP discovery and codified it into Nautobot "Cables." Discovered OCP nodes are trunked on SFP+ Port 13.
    - **GitOps Loop**: Tied Nautobot directly to the Git repository. Pushing to `main` now automatically triggers a Nautobot Git Sync via GitHub Actions.
    - **Master Deployment Engine**:
        - Created the **`Master Deploy`** orchestrator playbook and the generic **`docker_app`** role.
        - The engine handles the full lifecycle: Provisioning (Native) -> SSH Bootstrap -> Docker -> App Stack.
        - Transitioned `provision_lxc_generic` and `provision_vm_generic` to native Proxmox modules for true idempotency.
    - **SSH Resilience**: Built a bulletproof **`bootstrap_ssh`** role that uses the Proxmox API to restore access if a host is unreachable.
    - **Decommissioning**: Successfully removed the legacy Media Stack footprint from OpenShift (Plex, Sonarr, Radarr, etc.) and purged 6,000+ lines of redundant automation code/docs.
    - **Nautobot Repair**: Restored Nautobot background job functionality by adding Celery Worker and Scheduler containers.
    - **Workflow Impact**: Manual data entry is now replaced by "Inventory-First" automation. Changes to hardware or apps are now made in Git/Nautobot and reconciled by Ansible.

- [2026-01-20]: **DUMB STACK OPTIMIZATION & SECURITY HARDENING**
    - **Token Automation**: Implemented 15-minute proactive TorBox token refresh logic in Decypharr to eliminate "Expired Token" I/O errors.
    - **Streaming Performance**: Enabled **Full VFS Cache (50GB)** on DUMB LXC. Fixed buffering by mapping persistent cache volume to host disk, bypassing Docker overlay overhead.
    - **Stack Expansion**: Deployed **Bazarr** (.20), **Tautulli** (.21), and **FlareSolverr** (.21). Automated DNS (`.io` domain) and Traefik routing via AAP.
    - **Riven Fixes**: Corrected Riven `rclone_path` to TorBox and enabled 2160p (4K) and Remux support in ranking profiles.
    - **Security Cleanup**: Identified and remediated leaked API keys in Git. Transitioned Riven, Plex, and Overseerr secrets to **Bitwarden -> ESO -> AAP** pipeline.
    - **History Scrubbing**: Used `git-filter-repo` to permanently erase sensitive credential strings from the entire Git history.
    - **Automation Engine**: Upgraded Execution Environment (HomeLab EE) to **Ansible Core 2.20.1** using the community `dev-tools` Fedora-based image for better collection compatibility.

- [2026-01-20]: **DUMB DEBRID TOKEN AUTOMATION**
    - **Issue**: Alien Earth S01E01 failed with I/O error due to expired TorBox presigned tokens.
    - **Fix**: Shortened `download_links_refresh_interval` to 15 minutes and `auto_expire_links_after` to 24 hours in Decypharr config.
    - **Automation**: Templatized Decypharr `config.json` via Ansible and updated AAP Seeder to map necessary media API credentials.
    - **Outcome**: Verified tokens are proactively rotated before expiration, resolving streaming errors.

- [2026-01-20]: **AAP PLATFORM & INVENTORY REPAIR (PHASE 4)**
    - **Seeder Refactor**: Successfully refactored `setup-aap.yml` to use the `awx.awx` collection, resolving "Unknown Plugin" errors post-2.20 upgrade.
    - **Inventory IP Discovery**: Fixed Proxmox Dynamic Inventory by implementing explicit `ansible_host` mapping from `proxmox_net0.ip`. AAP now correctly targets hosts via IP instead of unresolvable names.
    - **Metadata Enrichment**: Added `proxmox_vmid`, `proxmox_vmtype`, and `proxmox_node` facts to all discovered hosts for automated OOB management.
    - **SSH Bootstrap Fix**: Resolved `add_host` validation crashes in AAP by moving conditional logic to the Play level. Utility now handles manual IPs and inventory hosts safely.
    - **ESO Stabilization**:
        - Fixed `external-secrets` ComparisonError in ArgoCD by removing redundant/conflicting ClusterSecretStore manifests.
        - Resolved `pathconf: Permission denied` restart loop by converting liveness/readiness probes from `exec` (wget) to native `httpGet`.
    - **Security Recovery**: Successfully rotated leaked TorBox API keys across the entire pipeline (Bitvault -> ESO -> AAP -> DUMB LXC).
    - **Zilean Integration**: Discovered and verified the Torznab endpoint (`/torznab`) for Zilean and integrated it into the Prowlarr/Sonarr search flow for instant cache hits.
    - **Status**: AAP Platform is 100% operational; Proxmox inventory is synced with 14 hosts; Media stack is fully restored.
