# Plan: Configure OneLogin OIDC Identity Provider

## Phase 1: Secret Management [checkpoint: 42f551a]
- [x] Task: Read OneLogin credentials from `.env` file 5cbe12d
- [x] Task: Generate a Kubernetes Secret for the OneLogin Client Secret (dry-run) 5cbe12d
- [x] Task: Seal the Secret using `kubeseal` and the public key `pub-sealed-secrets.pem` 5cbe12d
- [x] Task: Add the `SealedSecret` to `infrastructure/auth/onelogin-sealed-secret.yaml` 5cbe12d
- [x] Task: Update `infrastructure/auth/kustomization.yaml` to include the new secret 5cbe12d
- [x] Task: Conductor - User Manual Verification 'Phase 1: Secret Management' (Protocol in workflow.md)

## Phase 2: OAuth Configuration [checkpoint: db66841]
- [x] Task: Update `infrastructure/auth/cluster-oauth.yaml` to include the OneLogin OIDC provider 075c747
- [x] Task: Verify the Kustomize build for the `infrastructure/auth/` directory 075c747
- [x] Task: Update `argocd-apps/cluster-auth.yaml` to ensure sync of authentication changes (if not already synced) 075c747
- [x] Task: Conductor - User Manual Verification 'Phase 2: OAuth Configuration' (Protocol in workflow.md)

## Phase 3: Validation and Testing
- [x] Task: Monitor the `openshift-authentication` namespace pods for successful rollout
- [x] Task: Verify the presence of the OneLogin IDP in the OpenShift Console login page
- [x] Task: Perform a test login with a OneLogin account
- [x] Task: Verify the created `Identity` and `User` resources in OpenShift
- [x] Task: Grant cluster-admin to OneLogin user `sigtom`
- [x] Task: Conductor - User Manual Verification 'Phase 3: Validation and Testing' (Protocol in workflow.md)
