# Specification: Expose Zone 1 Services via Ingress

## Overview
This track involves updating the existing `media-ingress` configuration to expose the Zone 1 "Cloud Gateway" services: `rdt-client`, `zurg`, and `riven`. This will allow external access to their web interfaces and WebDAV endpoints within the homelab environment.

## Functional Requirements
- **Hostnames:** Expose services using the following hostnames:
    - `rdt-client.sigtom.dev`
    - `zurg.sigtom.dev`
    - `riven.sigtom.dev`
- **TLS:** Each hostname must be included in the TLS configuration using the `media-sigtom-tls` secret.
- **Backend Mapping:** Map hostnames to their respective internal services and ports:
    - `rdt-client.sigtom.dev` -> `rdt-client:6500`
    - `zurg.sigtom.dev` -> `zurg:9999`
    - `riven.sigtom.dev` -> `riven:80` (internal service port)

## Non-Functional Requirements
- **GitOps:** Managed via Kustomize and ArgoCD.
- **Certificate Management:** Use the `cloudflare-prod` cluster issuer (handled by existing Ingress annotations).
- **Security:** Access is within the homelab firewall and VPN.

## Acceptance Criteria
- [ ] `apps/media-stack/base/ingress.yaml` is updated with the new TLS hosts and rules.
- [ ] OpenShift Routes are automatically created by the Ingress controller.
- [ ] `https://rdt-client.sigtom.dev`, `https://zurg.sigtom.dev`, and `https://riven.sigtom.dev` are accessible and secured via TLS.
- [ ] Changes are committed and synced via ArgoCD.

## Out of Scope
- Initial configuration of the individual services (e.g., setting up RD API keys in RdtClient).
- Provisioning new TLS certificates (existing `media-sigtom-tls` should handle it via SAN).
