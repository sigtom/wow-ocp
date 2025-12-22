# Plan: Configure Alertmanager Receivers (Slack)

## Phase 1: Secret Management [checkpoint: 4563b54]
- [x] Task: Generate Slack Webhook Secret (dry-run) 7f3c5cb
- [x] Task: Seal the Secret using `kubeseal` and the public key `pub-sealed-secrets.pem` 7f3c5cb
- [x] Task: Add the `SealedSecret` to `infrastructure/monitoring/slack-webhook-sealed-secret.yaml` 7f3c5cb
- [x] Task: Update `infrastructure/monitoring/kustomization.yaml` to include the new resource 7f3c5cb
- [x] Task: Conductor - User Manual Verification 'Phase 1: Secret Management' (Protocol in workflow.md)

## Phase 2: Alertmanager Configuration
- [ ] Task: Research/Confirm Alertmanager configuration method for OCP 4.20 (likely patching `alertmanager-main` secret)
- [ ] Task: Create Alertmanager configuration manifest (YAML) with Slack receiver details
- [ ] Task: Create Kustomize overlay to apply the configuration to the cluster
- [ ] Task: Update `argocd-apps/cluster-monitoring.yaml` to ensure sync of configuration changes
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Alertmanager Configuration' (Protocol in workflow.md)

## Phase 3: Validation and Alert Testing
- [ ] Task: Verify ArgoCD successful sync of monitoring components
- [ ] Task: Check Alertmanager Status via OC CLI to confirm receiver is active
- [ ] Task: Verify that the `AlertmanagerReceiversNotConfigured` alert has cleared
- [ ] Task: Trigger a test alert or wait for a watchdog alert to verify Slack delivery
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Validation and Alert Testing' (Protocol in workflow.md)
