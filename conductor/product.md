# Product Guide - OpenShift 4.20 Homelab

## Initial Concept
The project is a private OpenShift 4.20 Homelab running on Dell FC630 blades, designed to host a hybrid environment of containers and virtual machines. It serves as both a production-grade media server and an enterprise-level technology sandbox.

## Target Audience
- **The Sole Engineer:** A Gen X engineer managing the cluster for personal learning, media hosting, and experimentation. The system is designed for self-reliance and deep technical control.

## Core Goals
- **Production-Grade Media Hosting:** Providing a rock-solid environment for Plex, the Arr-stack, and storage for an 11TB library.
- **Enterprise Tech Sandbox:** Gaining hands-on experience with OpenShift 4.20, Virtualization, GitOps (ArgoCD), and advanced networking (MetalLB).
- **Infrastructure Consolidation:** Moving personal workloads and VMs from various platforms onto a unified, high-performance blade cluster.

## Key Features & Roadmap
- **Storage & Media Management (Complete):** Integration with TrueNAS via CSI, managing the 11TB media library, and deploying the media stack (Plex/Jellyfin).
- **GitOps & Automation (Complete):** Managing all configurations via Kustomize and ArgoCD, implementing Sealed Secrets for security, and using Cert-Manager for TLS.
- **Infrastructure & Networking (Complete):** 
    - Hybrid workload management (Containers + VMs).
    - Advanced Layer 2 networking (VLANs 110, 120, 130, 160).
    - MetalLB Load Balancing on dedicated bridges.
    - Node Optimization (Kubelet Tuning) for compact cluster topology.
- **Core Services (Complete):**
    - User Workload Monitoring with persistent storage.
    - Internal Image Registry with persistent storage.
    - Authentication via HTPasswd and RBAC.

## Success Criteria
- **Reliability ("Set it and forget it"):** The media stack runs reliably without manual intervention, and backups are automated.
- **GitOps Excellence ("Zero Manual Apply"):** All cluster changes are driven strictly through Git (ArgoCD), with zero manual `oc apply` commands.
- **Hardware Optimization ("Hardware Mastery"):** Fully utilizing the Dell blade capabilities, including live migration for VMs and optimized 10G storage networking.