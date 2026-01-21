# Lab Context (Active Stack)

**Last Updated:** 2026-01-21
**Purpose:** Quick-reference for active IPs, URLs, and architectural components.

---

##  Core Infrastructure

| Component | URL / Host | IP / Network | Role |
| :--- | :--- | :--- | :--- |
| **Nautobot** | https://ipmgmt.sigtom.dev | `172.16.100.15` | Source of Truth (IPAM/DCIM) |
| **AAP** | https://aap.apps.ossus... | OCP Namespace | Orchestration (Master Deploy) |
| **ArgoCD** | https://argocd.apps.ossus... | OCP Namespace | GitOps (Cluster Management) |
| **Technitium** | https://dns.sigtom.dev | `172.16.100.210` | Primary DNS & Ad-blocking |
| **Proxmox** | wow-prox1 | `172.16.110.101` | External Compute Node |
| **TrueNAS** | wow-ts01 | `172.16.110.100` | NFS Storage (VLAN 160) |

---

##  Active Application Stack (DUMB)

| Application | Hostname | IP | Port |
| :--- | :--- | :--- | :--- |
| **Traefik** | traefik.sigtom.dev | `172.16.100.10` | 80, 443, 8080 |
| **DUMB (Brain)** | dumb.sigtom.dev | `172.16.100.20` | 3005, 3000, 8080 |
| **Downloaders** | downloaders.sigtom.dev | `172.16.100.21` | 8080, 8081 |
| **Vaultwarden** | vault.sigtom.dev | `172.16.110.105` | 80 |
| **Bitwarden-Lite**| bitvault.sigtom.dev | `172.16.100.16` | 8080 |

---

##  Common Logic & Pattern Reference

*   **Deployment**: Always use `automation/playbooks/master-deploy.yaml`.
*   **Secrets**: Pulled from **Bitwarden** via **ESO** into OCP/AAP.
*   **Inventory**: Managed in **Nautobot** via Git Sync from `main`.
*   **OS Standards**: Prefer **Ubuntu 24.04** for LXCs; **Fedora 43** for VMs.
*   **Storage**: Use **NFS Host Bind Mounts** (`/mnt/nas`) for massive media data.

---

##  Maintenance & Discovery
*   **Physical Topology**: Documented via Nautobot Cables.
*   **Re-Discovery**: Run the "Discover Physical Cables" Job in Nautobot to sync SNMP data.
*   **Alerting**: OCP Alertmanager -> Apprise (Currently Silent).
