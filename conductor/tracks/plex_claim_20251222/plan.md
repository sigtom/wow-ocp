# Plan: Plex Server Claiming Procedure

## Phase 1: Preparation (GitOps) [checkpoint: 6224d8e]
- [x] Task: Update `apps/plex/base/deployment.yaml` to add `PLEX_CLAIM` env var mapped to secret `plex-claim` key `claimToken` a38d5b7
- [x] Task: Create a placeholder `SealedSecret` for `plex-claim` (to satisfy Kustomize build) a38d5b7
- [x] Task: Update `apps/plex/base/kustomization.yaml` to include the secret a38d5b7
- [x] Task: Commit and Push preparation changes a38d5b7
- [x] Task: Conductor - User Manual Verification 'Phase 1: Preparation' (Protocol in workflow.md)

## Phase 2: Execution (Operational)
- [x] Task: Pause ArgoCD application `plex`
- [x] Task: Scale Plex deployment to 0
- [x] Task: **USER ACTION** Delete `Preferences.xml` from TrueNAS
- [x] Task: **USER ACTION** Update `.env` with NEW `PLEX_CLAIM`
- [x] Task: Read `.env`, Generate Secret, Seal it, and **Directly Apply** to Cluster
- [x] Task: Scale Plex deployment to 1
- [x] Task: Conductor - User Manual Verification 'Phase 2: Execution' (Protocol in workflow.md)

## Phase 3: Reconciliation
- [ ] Task: Overwrite local `apps/plex/base/plex-claim-sealed-secret.yaml` with the newly generated one
- [ ] Task: Commit and Push the real SealedSecret
- [ ] Task: Unpause ArgoCD application `plex`
- [ ] Task: Verify ArgoCD Sync
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Reconciliation' (Protocol in workflow.md)
