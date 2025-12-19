# OpenShift 4.20 Homelab Configuration

This repository contains the GitOps configuration and Infrastructure as Code (IaC) for a private OpenShift 4.20 cluster running on Dell FC630 blade servers. It manages a hybrid environment supporting both containerized applications and virtual machines.

## Architecture

### Hardware
*   **Compute:** 3x Dell FC630 PowerEdge Blades.
*   **Storage:** TrueNAS Scale 25.10 ("Fangtooth") providing NFS via `democratic-csi`.
*   **Network:** Hybrid 10G/1G Setup.
    *   Machine Network: 172.16.100.0/24
    *   Workload Network: 172.16.130.0/24 (VLAN 130)
    *   Storage Network: 172.16.160.0/24 (VLAN 160)

### Core Stack
*   **Platform:** Red Hat OpenShift Container Platform 4.20
*   **Virtualization:** OpenShift Virtualization (KubeVirt) for hybrid workloads (RHEL/Windows).
*   **GitOps:** ArgoCD using the "App of Apps" pattern.
*   **Secrets:** Bitnami Sealed Secrets (encrypted at rest in Git).
*   **Ingress/Certificates:** OpenShift Routes + Cert-Manager (Cloudflare DNS-01).
*   **Load Balancing:** MetalLB (Layer 2) for LoadBalancer Services.

## Repository Structure

The repository follows a strict Kustomize-based structure:

*   `apps/`: User-facing applications (Plex, Media Stack).
*   `infrastructure/`: Core cluster services (Storage, Operators, Cert-Manager).
*   `argocd-apps/`: Application definitions for ArgoCD sync.
*   `conductor/`: AI-driven project management and state tracking.

## Operational Workflow

1.  **GitOps First:** All cluster changes are committed to this repository. Manual `oc apply` is discouraged except for debugging or "Day 0" bootstrapping.
2.  **Secret Management:** Secrets are encrypted locally using `kubeseal` before being committed. Raw secrets are never tracked.
3.  **App of Apps:** The `root-app.yaml` bootstraps the cluster infrastructure and applications.

## AI-Assisted Operations (Gemini)

This repository is managed with the assistance of the Gemini CLI using the **Conductor** methodology.

*   **Role:** The AI acts as a Senior SRE, handling planning, manifest generation, and operational checks. It does not replace the engineer but accelerates execution and enforces standards.
*   **Context:** The `GEMINI.md` file defines the "Rules of Engagement," ensuring the AI adheres to specific operational constraints (e.g., resource limits, safety checks, hardware specifics) and "Do No Harm" protocols.
*   **Tracks:** Development follows a structured implementation plan stored in `conductor/tracks/`, ensuring systematic progress on features like networking, monitoring, and app deployment.
