# VM Provisioning Skill

Agent skill for creating and managing virtual machines across OpenShift Virtualization (KubeVirt) and Proxmox VE platforms.

## Overview

This skill provides:
- **Decision guidance** for choosing between OpenShift VMs, Proxmox VMs, and Proxmox LXCs
- **Templates** for VM definitions on both platforms
- **Helper scripts** for automated provisioning and status checks
- **Documentation** of existing Ansible automation

## Structure

```
vm-provisioning/
├── SKILL.md                           # Main skill documentation (Agent Skills standard)
├── README.md                          # This file
├── references/
│   ├── platform-comparison.md         # When to use which platform
│   └── existing-automation.md         # Current Ansible structure
├── templates/
│   ├── ocp/
│   │   ├── vm-rhel9.yaml             # KubeVirt RHEL 9 VM
│   │   └── vm-windows.yaml           # KubeVirt Windows VM
│   └── proxmox/
│       ├── deploy-vm.yaml            # Ansible playbook using proxmox_vm role
│       └── deploy-lxc.yaml           # Ansible playbook using proxmox_lxc role
└── scripts/
    ├── create-vm.sh                  # Unified VM/LXC creation helper
    ├── vm-status.sh                  # Status across both platforms
    ├── ocp-console.sh                # virtctl console wrapper
    └── proxmox-list.sh               # List Proxmox VMs/LXCs with details
```

## Quick Start

### Check VM Status Across Platforms
```bash
.pi/skills/vm-provisioning/scripts/vm-status.sh
```

### Create OpenShift VM
```bash
.pi/skills/vm-provisioning/scripts/create-vm.sh ocp my-app-vm rhel9 4 8192 50
# Edit generated YAML, then:
oc apply -f /tmp/my-app-vm-vm.yaml
```

### Create Proxmox VM
```bash
.pi/skills/vm-provisioning/scripts/create-vm.sh proxmox-vm my-util-vm ubuntu 2 2048 20
# Follow prompts for IP and VMID, then:
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-my-util-vm.yaml
```

### Create Proxmox LXC
```bash
.pi/skills/vm-provisioning/scripts/create-vm.sh proxmox-lxc test-lxc ubuntu 1 512 8
# Follow prompts, then run generated playbook
```

### Access OpenShift VM Console
```bash
.pi/skills/vm-provisioning/scripts/ocp-console.sh my-vm my-namespace
```

### List Proxmox Resources
```bash
.pi/skills/vm-provisioning/scripts/proxmox-list.sh
```

## Platform Decision Guide

### OpenShift Virtualization (KubeVirt)
**Best for:**
- Production Linux VMs needing HA and live migration
- VMs integrated with cluster services
- GitOps-managed infrastructure
- Workloads requiring OpenShift Routes/Ingress

**Requirements:**
- OpenShift Virtualization operator installed
- `truenas-nfs` StorageClass (RWX for live migration)
- Multus CNI for additional networks

### Proxmox VM (QEMU/KVM)
**Best for:**
- Windows VMs
- Hardware passthrough (GPU, USB)
- Legacy operating systems
- Out-of-cluster isolation

**Requirements:**
- Proxmox host: wow-prox1.sigtomtech.com
- API token in `PROXMOX_SRE_BOT_API_TOKEN` env var
- SSH access via `~/.ssh/id_pfsense_sre`

### Proxmox LXC
**Best for:**
- Lightweight Linux services
- Dev/test environments
- High-density workloads
- Simple utilities (DNS, monitoring)

**Requirements:**
- Same as Proxmox VM
- `community.general` Ansible collection

See `references/platform-comparison.md` for detailed decision matrix.

## Environment Setup

### OpenShift
```bash
# Login to cluster
oc login https://api.wow.sigtomtech.com:6443

# Verify virtctl installed
virtctl version
# If not: oc krew install virt
```

### Proxmox
```bash
# Set API token
export PROXMOX_SRE_BOT_API_TOKEN="your-token-here"

# Verify SSH key
ls -l ~/.ssh/id_pfsense_sre

# Test connection
ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101 'qm list'

# Install Ansible collection (for LXC)
ansible-galaxy collection install community.general
```

## Key Files in Repo

### Ansible Automation
- `automation/inventory/hosts.yaml` - Inventory of Proxmox host and VMs/LXCs
- `automation/group_vars/all.yaml` - Global variables (credentials, SSH keys)
- `automation/roles/proxmox_vm/` - VM provisioning role
- `automation/roles/proxmox_lxc/` - LXC provisioning role

### OpenShift Examples
- `apps/technitium-dns/base/technitium-vm.yaml` - Example KubeVirt VM in production

## Integration with Other Skills

- **sealed-secrets**: Encrypt sensitive VM configs before Git commit
- **argocd-ops**: Deploy OpenShift VMs via GitOps, manage sync
- **truenas-ops**: Verify NFS storage health before VM creation
- **openshift-debug**: Troubleshoot VM pods, PVC provisioning

## Troubleshooting

### OpenShift VM Issues
```bash
# Check VM/VMI status
oc get vm,vmi -n <namespace>
oc describe vmi <name> -n <namespace>

# Check virt-launcher pod
oc get pods -n <namespace>
oc logs -n <namespace> virt-launcher-<vm>-xxxxx

# Check DataVolume
oc get dv,pvc -n <namespace>
oc describe dv <name> -n <namespace>
```

### Proxmox Issues
```bash
# Check Proxmox host connectivity
.pi/skills/vm-provisioning/scripts/proxmox-list.sh

# Verify API token
curl -k -H "Authorization: PVEAPIToken=sre-bot@pve!sre-token=$PROXMOX_SRE_BOT_API_TOKEN" \
  https://172.16.110.101:8006/api2/json/nodes/wow-prox1/qemu

# Check template exists
ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101 'qm list | grep 9024'
```

## Common Workflows

### 1. Deploy Production DB on OpenShift
```bash
# Create RHEL 9 VM with PostgreSQL
.pi/skills/vm-provisioning/scripts/create-vm.sh ocp postgres-vm rhel9 4 8192 100

# Edit generated YAML: customize network, add data disk
vim /tmp/postgres-vm-vm.yaml

# Apply
oc apply -f /tmp/postgres-vm-vm.yaml

# Monitor
oc get vm,vmi,dv -n postgres-vm-ns -w

# Access console
.pi/skills/vm-provisioning/scripts/ocp-console.sh postgres-vm postgres-vm-ns

# Install PostgreSQL via Ansible or manual
```

### 2. Create Windows RDP Server on Proxmox
```bash
# Since Windows needs manual install, create VM in Proxmox GUI:
# 1. Upload Windows ISO to TSVMDS01
# 2. Create VM with Windows ISO attached
# 3. Install Windows via VNC console
# 4. Configure RDP, network, join domain

# Or use template if available
```

### 3. Dev Environment LXC
```bash
# Quick dev container
.pi/skills/vm-provisioning/scripts/create-vm.sh proxmox-lxc dev-test ubuntu 2 1024 16

# Enter VMID (e.g., 350) and IP (e.g., 172.16.110.50)
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-dev-test.yaml

# Access
ssh root@172.16.110.50

# Install dev tools via Ansible or manual
```

## Best Practices

1. **Inventory Management**: Always update `automation/inventory/hosts.yaml` before Ansible runs
2. **VMID Allocation**: Use ranges (100-199: infra, 200-299: apps, 300-399: LXCs, 900+: templates)
3. **IP Allocation**: Document IPs in inventory, verify with `ping` before assigning
4. **GitOps**: Commit OpenShift VM YAMLs to Git, manage via ArgoCD for production
5. **Storage**: Use `truenas-nfs` (RWX) for OCP VMs needing live migration
6. **Backup**: Proxmox Backup Server for Proxmox VMs/LXCs, Velero for OpenShift VMs
7. **Monitoring**: Add VMs to monitoring stack (Prometheus for OCP, node_exporter for Proxmox)

## Contributing

When adding new VM templates or improving scripts:
1. Test on non-production environment first
2. Update SKILL.md with new workflows
3. Add examples to this README
4. Document any new prerequisites

## References

- [OpenShift Virtualization Documentation](https://docs.openshift.com/container-platform/4.20/virt/about_virt/about-virt.html)
- [KubeVirt Documentation](https://kubevirt.io/user-guide/)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox API](https://pve.proxmox.com/pve-docs/api-viewer/)

## License

Part of wow-ocp homelab infrastructure. Internal use only.
