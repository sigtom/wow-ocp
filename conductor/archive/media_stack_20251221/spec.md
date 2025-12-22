# Track Specification: Hybrid Media Stack Deployment

## Goal
Implement a high-availability, hybrid-converged media streaming and archival solution on OpenShift, as defined in the Project Design.

## Architecture
The stack is divided into four zones:
- **Zone 1: The Cloud Gateway:** Zurg (Real-Debrid), Rclone (TorBox), rdt-client (Symlinks), Riven.
- **Zone 2: The Managers:** Sonarr, Radarr, SABnzbd, Bazarr.
- **Zone 3: The Player:** Plex Media Server with Zurg/Rclone sidecars.
- **Zone 4: The Discovery Layer:** Overseerr.

## Requirements
- Use `media-stack` namespace.
- Utilize existing 11TB `media-library-pvc` for local storage.
- Implement `SealedSecrets` for all API keys and credentials.
- Configure SCCs (`privileged`, `anyuid`) for FUSE mounting.
- Use Kustomize with `base/` and `overlays/prod/` structure.
- Deploy via ArgoCD "App of Apps" pattern.

## Success Criteria
- [ ] Zone 1 components are running and cloud mounts are verified.
- [ ] Zone 2 components can orchestrate downloads and manage libraries.
- [ ] Plex (Zone 3) can play content from both local and cloud sources.
- [ ] Overseerr (Zone 4) is accessible and integrated with managers.
- [ ] Automated symlink orchestration is functional.
