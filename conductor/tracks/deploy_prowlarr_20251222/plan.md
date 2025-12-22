# Plan: Deploy Prowlarr Indexer Manager

## Phase 1: Resource Creation
- [~] Task: Create `apps/managers/base/prowlarr.yaml` (Deployment & Service)
- [~] Task: Update `apps/managers/base/kustomization.yaml` to include prowlarr
- [~] Task: Update `apps/media-stack/base/ingress.yaml` to expose prowlarr.sigtom.dev
- [ ] Task: Verify Kustomize builds for both apps
- [ ] Task: Commit and Push changes to GitHub
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Resource Creation' (Protocol in workflow.md)

## Phase 2: Deployment and Validation
- [ ] Task: Verify ArgoCD successful sync of `media-managers` and `media-stack`
- [ ] Task: Verify Prowlarr pod is running
- [ ] Task: Verify Ingress route is functional and TLS is valid
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Deployment and Validation' (Protocol in workflow.md)
