# Track Specification: Bug Fixes & Infrastructure Stabilization

## 1. Overview
**Track ID:** `bugfix_20251221`
**Type:** Bug Fix
**Goal:** Resolve three critical bugs affecting cluster observability, stability, and storage provisioning: broken Prometheus metrics for infrastructure operators, NFD Garbage Collector crash loops, and LVM storage manager failures.

## 2. Scope
### In Scope
1.  **Issue #1: Prometheus Rejected Resources**
    *   Bring `openshift-gitops-operator` under GitOps control (export manifests, create ArgoCD app).
    *   Patch `ServiceMonitor` resources for MetalLB and GitOps Operator to use `bearerTokenSecret` instead of `bearerTokenFile` to satisfy OpenShift 4.20 / Prometheus Operator security constraints.
2.  **Issue #9: NFD Garbage Collector CrashLoop**
    *   Diagnose port mismatch (8080 vs 8081) in NFD GC pod.
    *   Apply configuration fix (likely to the `NodeFeatureDiscovery` CR or Operator config) to align probe ports.
3.  **Issue #10: LVM Storage vg-manager Failed**
    *   Debug `lvmd.yaml` configuration error ("no device classes").
    *   Update `LVMCluster` CR to correctly select available block devices on worker nodes.

### Out of Scope
*   **Issue #8 (Pod Imbalance):** Deemed stable after manual intervention; issue closed.
*   Upgrading operator versions (unless required to fix the bug).

## 3. Technical Requirements
*   **GitOps:** All changes must be committed to git and synced via ArgoCD.
*   **Stability:** Fixes must not disrupt existing workloads (Plex, etc.) where possible.
*   **Observability:** Success is defined by green status in Prometheus targets and healthy pods.

## 4. Acceptance Criteria
*   [ ] **Prometheus:** All Targets for MetalLB and GitOps Operator are UP (Green). No "PrometheusRejectedResources" alerts.
*   [ ] **NFD:** `nfd-gc` pod is Running (2/2) and Stable (no restarts).
*   [ ] **LVM:** `vg-manager` pods are Running on all nodes. `LVMCluster` status is Ready.
*   [ ] **GitOps:** `openshift-gitops-operator` is fully managed by ArgoCD (Synced/Healthy).