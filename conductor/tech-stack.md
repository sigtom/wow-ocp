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
- **Load Balancing:** MetalLB (Layer 2) for the 172.16.130.x range
- **Ingress:** OpenShift Routes
- **TLS/SSL:** Cert-Manager with Cloudflare DNS-01 ClusterIssuer
- **Node Networking:** 10G storage (172.16.160.x) and workload (172.16.130.x) separation

## Operations & Security
- **GitOps:** ArgoCD (App of Apps pattern)
- **Configuration:** Kustomize (Base/Overlay pattern)
- **Secrets:** Bitnami Sealed Secrets
- **Security:** OpenShift Security Context Constraints (SCCs), NetworkPolicies
