# Plan: Configure OneLogin OIDC Identity Provider

## Phase 1: Secret Management
- [x] Task: Read OneLogin credentials from `.env` file
- [x] Task: Generate a Kubernetes Secret for the OneLogin Client Secret (dry-run)
- [x] Task: Seal the Secret using `kubeseal` and the public key `pub-sealed-secrets.pem`
- [x] Task: Add the `SealedSecret` to `infrastructure/auth/onelogin-sealed-secret.yaml`
- [x] Task: Update `infrastructure/auth/kustomization.yaml` to include the new secret
- [~] Task: Conductor - User Manual Verification 'Phase 1: Secret Management' (Protocol in workflow.md)

## Phase 2: OAuth Configuration
- [ ] Task: Update `infrastructure/auth/cluster-oauth.yaml` to include the OneLogin OIDC provider
- [ ] Task: Verify the Kustomize build for the `infrastructure/auth/` directory
- [ ] Task: Update `argocd-apps/cluster-auth.yaml` to ensure sync of authentication changes (if not already synced)
- [ ] Task: Conductor - User Manual Verification 'Phase 2: OAuth Configuration' (Protocol in workflow.md)

## Phase 3: Validation and Testing
- [ ] Task: Monitor the `openshift-authentication` namespace pods for successful rollout
- [ ] Task: Verify the presence of the OneLogin IDP in the OpenShift Console login page
- [ ] Task: Perform a test login with a OneLogin account
- [ ] Task: Verify the created `Identity` and `User` resources in OpenShift
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Validation and Testing' (Protocol in workflow.md)
