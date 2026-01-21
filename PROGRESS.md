# Project Progress (v1.9)

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
