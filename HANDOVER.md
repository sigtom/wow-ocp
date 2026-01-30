# Handover: DUMB Stack Stabilization (Phase 2)

## Current State
The "Clean Start" is functionally complete on the infrastructure side. A fresh `xlarge` VM (`dumb`, 172.16.100.20) is up and running. Docker is installed, and the consolidated Real-Debrid stack is currently in its first-run initialization phase.

### Key Successes
- **VM Stability**: Kernel isolation is achieved. Zombie mounts on the Proxmox host are a thing of the past.
- **Master Engine**: Provisioning is now forceful and resilient to template inheritance bugs.
- **Nautobot Sync**: AAP is successfully pulling inventory from Nautobot via IP.

---

## Next Steps

### 1. Monitor DUMB Initialization
The `dumb` container is currently installing `poetry` and other dependencies. This can take several minutes.
- **Action**: Check logs frequently: `ssh root@172.16.100.20 "docker logs dumb --tail 50"`.
- **Goal**: Wait for the "Processes started" and "RealDebrid mount established" messages.

### 2. Verify Application Access
Once initialized, the services should be reachable via Traefik.
- **Internal**: `http://172.16.100.20:3005` (Frontend)
- **FQDNs**: Verify `dumb.sigtom.io`, `riven.sigtom.io`, `overseerr.sigtom.io`, etc.

### 3. Promote "Golden Path" to AAP
We have made several surgical fixes to the roles and inventory mappings locally to bypass the long sync cycle.
- **Action**: Ensure all local changes are committed and pushed to `main`.
- **Action**: Run one final "Master Deploy" from the AAP UI to ensure the platform can now handle the deployment end-to-end without manual intervention.

### 4. Clawd Bot Remediation
Clawd Bot is currently unresponsive due to process conflicts and network timeouts.
- **Action**: Kill duplicate gateway PIDs (`89382` and `82214`).
- **Action**: Check connectivity to the Ollama instance at `10.0.0.50`. If reachable, restart the bot gateway.

### 5. Final Library Re-Ingest
Once the stack is confirmed healthy, begin re-adding requests via Overseerr in small batches to build the Real-Debrid cache without hitting API rate limits.

---
**Architecture Note**: The stack is now consolidated. `sabnzbd` is on port **8085** to avoid conflicts. All other ports remain standard.
