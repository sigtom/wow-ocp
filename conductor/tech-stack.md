# Technology Stack - OpenShift Homelab

## Core Platform
- **Orchestration:** Red Hat OpenShift Container Platform 4.20
- **Compute:** 3x Dell FC630 Blades (Hybrid Containers + VMs)
- **Virtualization:** OpenShift Virtualization (KubeVirt)

## Storage & Data
- **Storage Backend:** TrueNAS Scale 25.10 ("Fangtooth")
- **CSI Driver:** democratic-csi (NFS) using `image: next` tag
- **Backup:** OADP (Velero) for critical PVCs

## Networking & Connectivity
- **Layer 2 Networking:** NMState (NodeNetworkConfigurationPolicy) for persistent bridge/VLAN configuration.
- **Load Balancing:** MetalLB (Layer 2) for ranges 110.x, 120.x, 130.x.
- **Ingress:** OpenShift Routes
- **TLS/SSL:** Cert-Manager with Cloudflare DNS-01 ClusterIssuer
- **Node Networking:** 10G storage (VLAN 160) and workload (VLAN 130) separation.

## Operations & Security
- **GitOps:** ArgoCD (App of Apps pattern)
- **Configuration:** Kustomize (Base/Overlay pattern)
- **Secrets:** Bitnami Sealed Secrets
- **Security:** OpenShift Security Context Constraints (SCCs), NetworkPolicies, HTPasswd IDP + RBAC.

## Monitoring & Observability
- **Cluster Monitoring:** Prometheus/Alertmanager (Default)
- **User Workload:** Prometheus User Workload Monitoring (Enabled with PV storage)
- **Registry:** OpenShift Image Registry (Managed with PV storage)