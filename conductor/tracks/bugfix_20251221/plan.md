# Implementation Plan - Track: bugfix_20251221

## Phase 1: Prometheus Metrics Fix & GitOps Hardening (Issue #1)
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
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Prometheus Metrics Fix & GitOps Hardening (Issue #1)' (Protocol in workflow.md)

## Phase 2: NFD Garbage Collector Fix (Issue #9)
This phase addresses the CrashLoopBackOff in the Node Feature Discovery operator.

- [ ] Task: Diagnose NFD Port Mismatch
    - [ ] Sub-task: Inspect `NodeFeatureDiscovery` CR and Pod logs.
    - [ ] Sub-task: Determine if the issue is the App listening on the wrong port or the Probe checking the wrong port.
- [ ] Task: Apply NFD Fix
    - [ ] Sub-task: Create a patch for the `NodeFeatureDiscovery` CR (or Subscription config) to align ports.
    - [ ] Sub-task: Commit and push changes.
    - [ ] Sub-task: Verify `nfd-gc` pod stabilizes.
- [ ] Task: Conductor - User Manual Verification 'Phase 2: NFD Garbage Collector Fix (Issue #9)' (Protocol in workflow.md)

## Phase 3: LVM Storage Recovery (Issue #10)
This phase fixes the storage provisioner failures on the nodes.

- [ ] Task: Debug LVM Device Discovery
    - [ ] Sub-task: Inspect `LVMCluster` CR and `vg-manager` logs.
    - [ ] Sub-task: Identify available raw devices on Nodes 2, 3, and 4.
- [ ] Task: Update LVM Configuration
    - [ ] Sub-task: Modify `LVMCluster` CR `deviceSelector` to correctly match physical disks.
    - [ ] Sub-task: Commit and push changes.
    - [ ] Sub-task: Verify `vg-manager` pods start and LVM VolumeGroups are created.
- [ ] Task: Conductor - User Manual Verification 'Phase 3: LVM Storage Recovery (Issue #10)' (Protocol in workflow.md)