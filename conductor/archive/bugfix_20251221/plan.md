# Implementation Plan - Track: bugfix_20251221

## Phase 1: Prometheus Metrics Fix & GitOps Hardening (Issue #1) [checkpoint: d19a027]
This phase focuses on bringing the GitOps operator under management and fixing the metric collection errors.

- [x] Task: Export and GitOps-ify OpenShift GitOps Operator (beb0662)
    - [x] Sub-task: Query cluster for current Subscription, OperatorGroup, and Namespace.
    - [x] Sub-task: Create manifests in `infrastructure/operators/openshift-gitops-operator/base/`.
    - [x] Sub-task: Create ArgoCD Application manifest `argocd-apps/gitops-operator.yaml`.
    - [x] Sub-task: Commit and push changes.
    - [x] Sub-task: Verify ArgoCD sync.
- [x] Task: Patch ServiceMonitors (MetalLB & GitOps) (fe9fa6b)
    - [x] Sub-task: Analyze failing `ServiceMonitor` resources to identify the specific `bearerTokenFile` usage.
    - [x] Sub-task: Create Kustomize patches (overlays) for MetalLB and GitOps Operator to switch to `bearerTokenSecret`.
    - [x] Sub-task: Apply patches via GitOps.
    - [x] Sub-task: Verify Prometheus Targets are UP.
- [x] Task: Conductor - User Manual Verification 'Phase 1: Prometheus Metrics Fix & GitOps Hardening (Issue #1)' (Protocol in workflow.md)

## Phase 2: NFD Garbage Collector Fix (Issue #9) [Skipped - Upstream Bug]
This phase addresses the CrashLoopBackOff in the Node Feature Discovery operator.

- [x] Task: Diagnose NFD Port Mismatch
    - [x] Sub-task: Inspect `NodeFeatureDiscovery` CR and Pod logs.
    - [x] Sub-task: Determine if the issue is the App listening on the wrong port or the Probe checking the wrong port.
- [ ] Task: Apply NFD Fix (Skipped - CRD does not support GC config, waiting for upstream)
    - [ ] Sub-task: Create a patch for the `NodeFeatureDiscovery` CR (or Subscription config) to align ports.
    - [ ] Sub-task: Commit and push changes.
    - [ ] Sub-task: Verify `nfd-gc` pod stabilizes.
- [x] Task: Conductor - User Manual Verification 'Phase 2: NFD Garbage Collector Fix (Issue #9)' (Protocol in workflow.md)

## Phase 3: LVM Storage Recovery (Issue #10) [checkpoint: 5b51ba0]
This phase fixes the storage provisioner failures on the nodes.

- [x] Task: Debug LVM Device Discovery
    - [x] Sub-task: Inspect `LVMCluster` CR and `vg-manager` logs.
    - [x] Sub-task: Identify available raw devices on Nodes 2, 3, and 4.
- [x] Task: Update LVM Configuration (475f67d)
    - [x] Sub-task: Modify `LVMCluster` CR `deviceSelector` to correctly match physical disks.
    - [x] Sub-task: Commit and push changes.
    - [x] Sub-task: Verify `vg-manager` pods start and LVM VolumeGroups are created.
- [x] Task: Conductor - User Manual Verification 'Phase 3: LVM Storage Recovery (Issue #10)' (Protocol in workflow.md)