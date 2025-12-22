# Specification: Deploy Prowlarr Indexer Manager

## Overview
This track involves deploying Prowlarr to the `media-stack` namespace. Prowlarr will serve as the centralized indexer management tool, synchronizing torrent and usenet indexers across Radarr, Sonarr, and Lidarr.

## Functional Requirements
- **Deployment:** Create a Kubernetes Deployment for Prowlarr in the `media-stack` namespace.
- **Persistence:** Use the existing `media-library-pvc` (StorageClass: `truenas-nfs`) and mount a subpath `/config/prowlarr` to `/config`.
- **Network:** Create a Service to expose port `9696`.
- **Ingress:** Update the existing `media-ingress` to expose Prowlarr at `https://prowlarr.sigtom.dev` with TLS.
- **Resources:** Apply standard resource boundaries (Requests: 100m/128Mi, Limits: 500m/512Mi).

## Non-Functional Requirements
- **GitOps:** Managed via Kustomize and ArgoCD.
- **Maintainability:** Consistent naming with other manager apps (Sonarr/Radarr).

## Acceptance Criteria
- [ ] `apps/managers/base/prowlarr.yaml` created.
- [ ] `apps/managers/base/kustomization.yaml` updated.
- [ ] `apps/media-stack/base/ingress.yaml` updated to include `prowlarr.sigtom.dev`.
- [ ] Prowlarr UI is accessible at `https://prowlarr.sigtom.dev`.
- [ ] Changes are committed and synced via ArgoCD.

## Out of Scope
- Initial configuration of indexers within the Prowlarr UI.
- Configuring Lidarr or Readarr.
