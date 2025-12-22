# Specification: Configure OneLogin OIDC Identity Provider

## Overview
This track involves integrating OneLogin as an OpenShift Identity Provider (IDP) using the OIDC (OpenID Connect) protocol. This will provide a centralized and secure authentication mechanism for the cluster, complementing the existing `htpasswd` provider.

## Functional Requirements
- **Integration:** Configure the OpenShift cluster-wide `OAuth` resource to include OneLogin as an identity provider.
- **Protocol:** Use OIDC for authentication.
- **OneLogin Tenant:** Configuration details (Issuer URL, Client ID, Client Secret) will be sourced from the local `.env` file.
- **Claim Mapping:** Map the OIDC `preferred_username` claim to the OpenShift username.
- **User Scope:** All authenticated users from the OneLogin tenant are permitted to log in.
- **Provider Coexistence:** The OneLogin provider will coexist with the existing `htpasswd` identity provider.

## Non-Functional Requirements
- **Security:** The OneLogin Client Secret must be securely stored as a `SealedSecret` in the `openshift-config` namespace.
- **GitOps:** All configurations must be managed via Kustomize and synced using ArgoCD.
- **Identity Resolution:** Use `mappingMethod: claim` to ensure users are identified by their OIDC claims.

## Acceptance Criteria
- [ ] A `SealedSecret` containing the OneLogin Client Secret is created in the `openshift-config` namespace.
- [ ] The `OAuth` cluster resource is patched via Kustomize to include the OneLogin IDP.
- [ ] The OpenShift login page displays "OneLogin" as an authentication option.
- [ ] A user can successfully authenticate to the OpenShift console using their OneLogin credentials.
- [ ] User identities are correctly created in OpenShift with usernames derived from the `preferred_username` claim.

## Out of Scope
- Configuring OIDC for individual applications (e.g., ArgoCD, Plex) if they don't use the cluster's unified authentication.
- Group synchronization from OneLogin to OpenShift RBAC groups (can be addressed in a future track).
