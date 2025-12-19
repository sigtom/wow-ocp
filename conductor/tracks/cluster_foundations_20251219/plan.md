# Track Plan: Cluster Foundations & Operationalization

## Phase 1: Networking & Connectivity
- [ ] Task: Networking - Verify Node Network Configuration
    - Validate that VLAN 130 interface exists and is up on all nodes.
    - Test ping connectivity between nodes on the 172.16.130.x subnet.
- [ ] Task: MetalLB - Verify IPAddressPool and L2Advertisement
    - Check `IPAddressPool` CR for correct range (172.16.130.x).
    - Check `L2Advertisement` CR.
    - Deploy a test `Service` with `type: LoadBalancer` and verify IP assignment and reachability.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Networking & Connectivity' (Protocol in workflow.md)

## Phase 2: Core Infrastructure Services
- [ ] Task: Monitoring - Enable User Workload Monitoring
    - Create/Update `cluster-monitoring-config` ConfigMap in `openshift-monitoring`.
    - Create `user-workload-monitoring-config` ConfigMap in `openshift-user-workload-monitoring`.
    - Verify Prometheus and Alertmanager pods are running.
- [ ] Task: Registry - Deploy Local Image Registry
    - Configure the internal OpenShift registry to use persistent storage (TrueNAS NFS or PVC).
    - Expose the registry via Route (if needed for external push) or internal Service.
    - Verify `podman login` and `podman push` to the registry.
- [ ] Task: Etcd - Health Check & Performance Verification
    - Run `oc adm diagnostics` or similar checks for Etcd.
    - Check disk I/O latency metrics for Etcd partition.
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Core Infrastructure Services' (Protocol in workflow.md)

## Phase 3: Access & Security
- [ ] Task: Auth - Configure HTPasswd Identity Provider
    - Create `htpasswd` secret.
    - Patch `OAuth` cluster resource to include HTPasswd IDP.
- [ ] Task: Auth - Configure OIDC Identity Provider
    - Register application with OIDC provider (Google/GitHub/Dex).
    - Create Client Secret.
    - Patch `OAuth` cluster resource to include OIDC IDP.
    - Verify login flow.
- [ ] Task: RBAC - Grant Cluster Admin
    - Create `ClusterRoleBinding` to grant `cluster-admin` to the OIDC user.
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Access & Security' (Protocol in workflow.md)

## Phase 4: Node Optimization
- [ ] Task: Tuning - Create KubeletConfig for System Reservation
    - Calculate appropriate `systemReserved` and `kubeReserved` values for FC630 nodes.
    - Apply `KubeletConfig` CRD to `worker` (and `master` if applicable) MachineConfigPools.
    - Verify Kubelet reload and configuration on nodes.
- [ ] Task: Tuning - Verify Max Pods Limit
    - Check current `maxPods` setting.
    - Adjust if necessary via `KubeletConfig`.
- [ ] Task: Conductor - User Manual Verification 'Phase 4: Node Optimization' (Protocol in workflow.md)
