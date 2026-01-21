# ADR 001: Migration to Proxmox Master Engine

**Date:** 2026-01-21
**Status:** Accepted
**Context:** The media stack (Plex, Arrs, etc.) was previously running on OpenShift (OCP) using a sidecar pattern for FUSE mounts. This introduced complexity in node pinning, high resource overhead on the OCP control plane, and issues with storage network routing.

## Decision
We decided to move all workload-heavy applications (Media Stack, Downloaders, Utilities) from OpenShift to **Proxmox LXC containers**. These containers are managed by a single **"Master Deploy"** Ansible playbook.

## Rationale
1.  **Efficiency**: LXC containers have significantly lower overhead than OpenShift pods for large-scale media applications.
2.  **Performance**: Proxmox nodes have native 10G access and direct PCIe passthrough capabilities (e.g., for GPUs).
3.  **Simplicity**: Standardized Docker Compose stacks are easier to maintain and update than complex K8s sidecar deployments.
4.  **Stability**: Keeps the OpenShift cluster focused on core orchestration and cluster-native services (AAP, DNS, ESO).

## Consequences
*   **Decommissioning**: The OCP `media-stack` namespace and related ArgoCD apps were deleted.
*   **Infrastructure**: Application lifecycle now follows the pattern: Proxmox Provisioning -> Docker -> Compose.
*   **Inventory**: Automation is now driven by metadata in Nautobot rather than manual surveys.
