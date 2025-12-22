# Plan: Configure Alertmanager Receivers (Slack)

## Phase 1: Secret Management [checkpoint: 4563b54]
- [x] Task: Generate Slack Webhook Secret (dry-run) 7f3c5cb
- [x] Task: Seal the Secret using `kubeseal` and the public key `pub-sealed-secrets.pem` 7f3c5cb
- [x] Task: Add the `SealedSecret` to `infrastructure/monitoring/slack-webhook-sealed-secret.yaml` 7f3c5cb
- [x] Task: Update `infrastructure/monitoring/kustomization.yaml` to include the new resource 7f3c5cb
- [x] Task: Conductor - User Manual Verification 'Phase 1: Secret Management' (Protocol in workflow.md)

## Phase 2: Alertmanager Configuration [checkpoint: 654e32d]
- [x] Task: Research/Confirm Alertmanager configuration method for OCP 4.20 (likely patching `alertmanager-main` secret) 20c71e7
- [x] Task: Create Alertmanager configuration manifest (YAML) with Slack receiver details ef136b5
- [x] Task: Update cluster-monitoring-config.yaml to mount the slack-webhook secret ef136b5
- [x] Task: Create Kustomize overlay to apply the configuration to the cluster ef136b5
- [x] Task: Update `argocd-apps/cluster-monitoring.yaml` to ensure sync of configuration changes ef136b5
- [x] Task: Conductor - User Manual Verification 'Phase 2: Alertmanager Configuration' (Protocol in workflow.md)

## Phase 3: Validation and Alert Testing [checkpoint: 9b110e4]
- [x] Task: Verify ArgoCD successful sync of monitoring components
- [x] Task: Check Alertmanager Status via OC CLI to confirm receiver is active
- [x] Task: Verify that the `AlertmanagerReceiversNotConfigured` alert has cleared
- [x] Task: Trigger a test alert or wait for a watchdog alert to verify Slack delivery
- [x] Task: Conductor - User Manual Verification 'Phase 3: Validation and Alert Testing' (Protocol in workflow.md)
