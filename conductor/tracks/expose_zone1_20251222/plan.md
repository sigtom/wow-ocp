# Plan: Expose Zone 1 Services via Ingress

## Phase 1: Ingress Update
- [x] Task: Update `apps/media-stack/base/ingress.yaml` to include new TLS hosts
- [x] Task: Update `apps/media-stack/base/ingress.yaml` to include backend rules for rdt-client, zurg, and riven
- [~] Task: Verify the Kustomize build for `apps/media-stack/base`
- [ ] Task: Commit and Push changes to GitHub
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Ingress Update' (Protocol in workflow.md)

## Phase 2: Sync and Verification
- [ ] Task: Verify ArgoCD successful sync of `media-stack` application
- [ ] Task: Verify OpenShift Routes are created for the new services
- [ ] Task: Verify external accessibility (browser test) for rdt-client, zurg, and riven
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Sync and Verification' (Protocol in workflow.md)
