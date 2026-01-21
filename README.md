# OpenShift 4.20 Homelab Configuration (GitOps)

This repository contains the GitOps configuration and Infrastructure as Code (IaC) for a private OpenShift 4.20 cluster and a Proxmox-based "Cattle" infrastructure. It manages a hybrid environment supporting containerized applications, virtual machines, and automated lab operations.

## 🏛️ Architecture

### Hardware
*   **OpenShift (OCP):** 3x Dell FC630 PowerEdge Blades (wow-ocp-node2-4).
*   **Hypervisor:** Proxmox VE host (wow-prox1) for lightweight workloads and discovery.
*   **Storage:** TrueNAS Scale 25.10 ("Fangtooth") providing NFS storage.
*   **Network:** 10G/1G Hybrid. Physical topology is documented in Nautobot.

### Software Stack
*   **Platform:** Red Hat OpenShift 4.20 + OpenShift Virtualization.
*   **Source of Truth:** [Nautobot IPAM/DCIM](https://ipmgmt.sigtom.dev) (Dynamic Inventory).
*   **Orchestration:** [Ansible Automation Platform (AAP)](https://aap.apps.ossus.sigtomtech.com).
*   **GitOps:** ArgoCD using the "App of Apps" pattern for cluster services.
*   **Secrets:** Bitwarden (Vault) + External Secrets Operator (ESO).
*   **Ingress:** Traefik (Proxmox) & OpenShift Routes (OCP) with Cloudflare DNS-01.

## 📁 Repository Structure

*   `apps/`: Active cluster applications (AAP, Technitium, Vaultwarden).
*   `infrastructure/`: Core cluster services (Storage, Operators, Monitoring).
*   `automation/`: Ansible roles and playbooks for Proxmox and application lifecycle.
*   `config_contexts/`: Nautobot configuration specs (T-shirt sizes, app registry).
*   `jobs/`: Custom Nautobot Python jobs for network discovery.
*   `argocd-apps/`: ArgoCD Application definitions.

## 🚀 Operational Workflows

### 1. Master Deployment (The "Cattle" Pattern)
Application deployment on Proxmox is driven by Nautobot metadata.
1. Define the VM/LXC and its apps in **Nautobot**.
2. Run the **Master Deploy** playbook in AAP.
3. Ansible automatically handles Provisioning -> SSH Bootstrap -> Docker -> App Stack.

### 2. Secret Management
Raw secrets are never committed.
*   **OCP**: ESO pulls secrets directly from Bitwarden into the cluster.
*   **Ansible**: The Master Playbook fetches secrets on-demand during deployment.

### 3. GitOps Loop
This repository is tied to Nautobot via GitHub Actions. Pushing to `main` automatically triggers a Nautobot Git Sync, ensuring your inventory always matches your code.

## 📖 Documentation

*   [Runbooks](./docs/runbooks/README.md): Troubleshooting guides for common cluster issues.
*   [Architecture](./docs/architecture/external-secrets-bitwarden.md): Deep dives into the secret management and networking layers.

---
Managed with ❤️ by SigTomtech.
