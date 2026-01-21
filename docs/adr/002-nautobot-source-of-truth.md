# ADR 002: Nautobot as Operational Source of Truth

**Date:** 2026-01-21
**Status:** Accepted
**Context:** Management of IP addresses, VMIDs, and host metadata was fragmented across multiple YAML files, AAP surveys, and manual documentation. This led to IP conflicts and "Pet-like" behavior.

## Decision
We decided to adopt **Nautobot 3.x** as the single "Operational Source of Truth" for the entire homelab. All host metadata (hardware specs, IP linkages, physical cabling) is maintained in Nautobot.

## Rationale
1.  **Dynamic Inventory**: Ansible now pulls its host list from Nautobot, ensuring that automation always uses the correct IPs and IDs.
2.  **IPAM Safety**: Nautobot protects the IP space by marking MetalLB pools and storage networks as `Reserved`.
3.  **Visualization**: The physical cabling (DCIM) features of Nautobot provide a clear map of the rack topology, which is essential for upcoming hardware migrations.

## Consequences
*   **Workflow**: New hosts MUST be documented in Nautobot before they can be provisioned.
*   **Data Enrichment**: All existing lab devices were "hydrated" with real-world metadata (CPU/RAM/Services).
*   **Cleanup**: 170+ lines of redundant IP data were purged from Ansible `group_vars`.
