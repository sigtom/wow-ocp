# Track Plan: Cluster Foundations & Operationalization

## Phase 1: Networking & Connectivity [checkpoint: 8bfef40]
- [x] Task: Networking - Verify Node Network Configuration (ba87704)
- [x] Task: Networking - Configure NodeNetworkConfigurationPolicies (fa7b140)
    - [x] Define NNCP for Nodes 2 & 3 (eno3 -> br130).
    - [x] Define NNCP for Node 4 (eno2 -> br130).
    - [x] Commit to Git to trigger sync.
    - [x] Verify `Available` status on cluster.
    - [x] **NEW:** Configure VLAN 160 (Storage) on Node 4 (eno2.160).
- [x] Task: Networking - Configure VLAN 110/120 Bridges (878a6af)
    - [x] Update NNCP for Nodes 2 & 3: Add `br110` (eno3.110) and `br120` (eno3.120).
    - [x] Update NNCP for Node 4: Add `br110` (eno2.110) and `br120` (eno2.120).
    - [x] Commit and Verify.
- [x] Task: MetalLB - Verify IPAddressPool and L2Advertisement (a48f627)
- [x] Task: MetalLB - Configure Pools for VLAN 110/120 (ee22956)
    - [x] Update MetalLB `pool.yaml` with new pools.
    - [x] Update `L2Advertisement` to include `br110` and `br120`.
    - [x] Commit and Verify.
- [x] Task: Conductor - User Manual Verification 'Phase 1: Networking & Connectivity' (Protocol in workflow.md) (8bfef40)

## Phase 2: Core Infrastructure Services [checkpoint: 5cd4bc8]
- [x] Task: Monitoring - Enable User Workload Monitoring (dded13e)
- [x] Task: Registry - Deploy Local Image Registry (9bba52f)
- [x] Task: Etcd - Health Check & Performance Verification (29dba56)
- [x] Task: Conductor - User Manual Verification 'Phase 2: Core Infrastructure Services' (Protocol in workflow.md) (5cd4bc8)

## Phase 3: Access & Security
- [x] Task: Auth - Configure HTPasswd Identity Provider (75adc39)
- [~] Task: Auth - Configure OIDC Identity Provider
    - Register application with OIDC provider (Google/GitHub/Dex).
    - Create Client Secret.
    - Patch `OAuth` cluster resource to include OIDC IDP.
    - Verify login flow.
- [x] Task: RBAC - Grant Cluster Admin (d03f41f)
- [~] Task: Conductor - User Manual Verification 'Phase 3: Access & Security' (Protocol in workflow.md)

## Phase 4: Node Optimization
- [ ] Task: Tuning - Create KubeletConfig for System Reservation
    - Calculate appropriate `systemReserved` and `kubeReserved` values for FC630 nodes.
    - Apply `KubeletConfig` CRD to `worker` (and `master` if applicable) MachineConfigPools.
    - Verify Kubelet reload and configuration on nodes.
- [ ] Task: Tuning - Verify Max Pods Limit
    - Check current `maxPods` setting.
    - Adjust if necessary via `KubeletConfig`.
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Node Optimization' (Protocol in workflow.md)

## Phase 5: Day 2 Remediation & Fixes
- [ ] Task: Monitoring - Fix PrometheusOperatorRejectedResources
    - Investigate `bearerTokenFile` usage in MetalLB and GitOps ServiceMonitors.
    - Patch `ServiceMonitor` resources to use `bearerTokenSecret` or adjust security context.
    - Verify alerts are cleared.
- [ ] Task: Monitoring - Configure Alertmanager Receivers
    - Configure email or other receivers in `alertmanager-main`.
