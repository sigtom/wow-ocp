# Track Plan: Hybrid Media Stack Deployment

## Phase 1: Preparation & Security
- [x] Task: Security - Configure SCCs and ServiceAccounts (79d5fc2)
- [x] Task: Secrets - Create SealedSecrets for Cloud Providers (79d5fc2)
- [x] Task: Secrets - Create SealedSecrets for Indexers and *Arrs (Completed via Zone 1 Secrets)
- [x] Task: Conductor - User Manual Verification 'Phase 1: Preparation & Security' (Protocol in workflow.md)

## Phase 2: Zone 1 - Connectivity & Cloud Gateway
- [x] Task: Zone 1 - Deploy Zurg (Real-Debrid) (79d5fc2)
- [x] Task: Zone 1 - Deploy Rclone (TorBox) (79d5fc2)
- [x] Task: Zone 1 - Deploy rdt-client and Riven (PR #11)
- [x] Task: Zone 1 - Verify Cloud Mounts and Symlinking (Confirmed via Plex and Rclone logs)
- [x] Task: Conductor - User Manual Verification 'Phase 2: Zone 1 - Connectivity' (Protocol in workflow.md)

## Phase 3: Zone 2 - Management & Logic
- [x] Task: Zone 2 - Deploy Sonarr and Radarr [cdf0f98]
- [x] Task: Zone 2 - Deploy SABnzbd and Bazarr [956cf71]
- [x] Task: Zone 2 - Configure Root Folders (/stream and /archive) [a1061ad]
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Zone 2 - Management' (Protocol in workflow.md)

## Phase 4: Zone 3 & 4 - Player & Discovery
- [x] Task: Zone 3 - Update Plex Deployment with Sidecars (Completed ahead of schedule)
- [x] Task: Zone 4 - Deploy Overseerr [bd23426]
- [x] Task: Ingress - Configure Routes for Plex and Overseerr [2ea159a]
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Player & Discovery' (Protocol in workflow.md)