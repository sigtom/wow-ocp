# Track Specification: Cluster Foundations & Operationalization

## Goal
Establish a robust, production-grade foundation for the OpenShift 4.20 Homelab. This track focuses on enabling critical operational capabilities—networking, monitoring, registry, and security—before deploying user-facing applications.

## Core Requirements

### 1. Networking & Connectivity
- **Workload VLAN:** Configure and verify VLAN 130 (172.16.130.0/24) connectivity across all 3 Dell FC630 nodes.
- **MetalLB:** Verify Layer 2 mode functionality and ensuring IP address pool (172.16.130.x) is correctly advertising.

### 2. Core Infrastructure Services
- **Monitoring Stack:** Enable the user-workload-monitoring config. Verify Prometheus, Alertmanager, and Grafana are healthy.
- **Local Registry:** Deploy a local image registry to cache frequently used images and host private builds, reducing dependency on Docker Hub.
- **Etcd Health:** Verify Etcd performance and stability for the 3-node compact cluster topology.

### 3. Access & Security
- **Authentication:**
  - Configure `htpasswd` identity provider for local emergency access.
  - Configure OIDC identity provider (e.g., Google, GitHub, or generic OIDC) for primary user access.
- **RBAC:** Ensure `cluster-admin` is correctly assigned to the primary user.

### 4. Node Optimization
- **Kubelet Configuration:** Apply `KubeletConfig` to reserve appropriate resources (CPU/Memory) for the system and control plane components on the hybrid control-plane/worker nodes to prevent starvation.
- **Pod Limits:** Verify/Set maximum pod limits per node to match hardware capacity.

## Success Criteria
- All nodes can route traffic on VLAN 130.
- MetalLB assigns and announces IPs for services.
- Prometheus targets are up; default alerts are firing/ready.
- Private images can be pushed/pulled from the local registry.
- Users can log in via OIDC and HTPasswd.
- Node resource reservations are active and visible in `oc describe node`.
