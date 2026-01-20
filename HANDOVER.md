# Handover Notes - January 20, 2026

## 🚀 Recently Completed
1.  **Resolved 4K Buffering:**
    *   Enabled `vfs-cache-mode: full` with a `50G` limit on the DUMB LXC.
    *   Mapped `./cache:/cache` in Docker Compose to ensure the buffer is written to the physical host disk, which is significantly faster than the Docker overlay layer.
2.  **Automated Token Refresh:**
    *   Decypharr now proactively refreshes TorBox presigned links every 15 minutes. This eliminates the "Input/Output Error" caused by link expiration.
3.  **Security Hardening (GitOps):**
    *   All hardcoded API keys (Riven, Plex, Overseerr, RealDebrid) have been removed from templates and playbooks.
    *   Keys are now managed via the **Bitwarden -> ESO -> AAP** pipeline.
    *   **Scrubbed Git History:** Used `git-filter-repo` to purge leaked strings from every historical commit.
4.  **Stack Expansion:**
    *   **Bazarr (.20):** Installed as an isolated service on DUMB LXC for subtitle automation.
    *   **Tautulli (.21):** Installed on Downloader LXC for Plex monitoring.
    *   **FlareSolverr (.21):** Installed on Downloader LXC to bypass Cloudflare for Prowlarr.
    *   **DNS/Routing:** Automated `tautulli.sigtom.io` and `bazarr.sigtom.io` via Pi-hole sync and Traefik remote config.

## 🛠️ Infrastructure Status
*   **DUMB LXC (.20):** Running 18 cores, 16GB RAM. Disk space: 70GB free (plenty for 50GB VFS cache).
*   **Downloader LXC (.21):** Running core download services + FlareSolverr/Tautulli.
*   **Secrets:** Verified synced from Bitvault to K8s and mapped into AAP Credentials.

## 📋 Next Tasks
1.  **Monitor VFS Cache:** Observe the `/opt/dumb/cache/decypharr` folder to ensure it cleans up properly once it hits the 50GB threshold.
2.  **Overseerr Watchlist Fix:** Currently, Overseerr is throwing a `404 Not Found` when trying to sync the Plex Watchlist. This is a known issue with the latest Overseerr build.
    *   *Plan:* Switch the Overseerr container image to the `:develop` tag in the `downloaders` template to pull the latest upstream fix.
3.  **Bazarr Tuning:** Ensure Bazarr is correctly scanning the Riven symlink directories. Check for "Path Mapping" errors in the Bazarr UI if subtitles aren't appearing.
4.  **Tautulli Notifications:** Configure Tautulli to send notifications (via Apprise/Discord) if any stream hits a buffering state to help differentiate between server-side and client-side issues.
5.  **Git History Maintenance:** Since commit hashes have changed due to the scrub, ensure all other clones of this repo are reset using `git fetch origin` and `git reset --hard origin/main`.

---
*End of Handover*
