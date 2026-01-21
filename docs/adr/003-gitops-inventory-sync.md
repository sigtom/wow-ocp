# ADR 003: Inventory as Code (Git-to-Nautobot Sync)

**Date:** 2026-01-21
**Status:** Accepted
**Context:** Manually entering hardware specifications and app registries into the Nautobot UI is error-prone and violates the GitOps principle of "everything in code."

## Decision
We decided to use Nautobot's **Git Data Source** feature to ingest inventory metadata directly from the `wow-ocp` repository. We established a flattened folder structure (`/config_contexts`, `/jobs`) at the repository root.

## Rationale
1.  **Version Control**: Changes to VM sizes or the app registry are now tracked in Git history.
2.  **Automation**: A GitHub Action automatically triggers a Nautobot Sync on every push to `main`.
3.  **Atomic Commits**: We can update the deployment code and the inventory data in a single pull request.

## Consequences
*   **Structure**: The repository now hosts Nautobot Config Contexts and Python Jobs at the top level.
*   **Infrastructure**: The Nautobot stack was repaired with Celery workers to support this automated background syncing.
