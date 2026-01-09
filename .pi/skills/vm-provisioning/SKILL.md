---
name: vm-provisioning
description: Create and manage virtual machines and LXC containers on OpenShift Virtualization (KubeVirt) and Proxmox VE. Provision VMs on OpenShift or Proxmox, create LXC containers, clone from templates, and decide platform per workload. Use when creating new VMs/containers or managing virtualization infrastructure.
---

# VM Provisioning Skill

**Purpose**: Create and manage virtual machines and LXC containers on OpenShift Virtualization (KubeVirt) and Proxmox VE.

**When to use**:
- Provisioning new VMs on OpenShift cluster or Proxmox standalone host
- Creating lightweight LXC containers on Proxmox
- Cloning VMs from templates
- Deciding which platform fits the workload

## Prerequisites

### OpenShift Virtualization (KubeVirt)
- OpenShift Virtualization operator installed
- `virtctl` CLI tool available
- `truenas-nfs` StorageClass for RWX volumes (required for live migration)
- Multus CNI for additional network attachments (workload-br130, etc.)

### Proxmox VE 9
- Host: `wow-prox1.sigtomtech.com` (172.16.110.101)
- API token: `sre-bot@pve!sre-token` (stored in `PROXMOX_SRE_BOT_API_TOKEN` env var)
- SSH access via `~/.ssh/id_pfsense_sre` key
- Ansible inventory: `automation/inventory/hosts.yaml`
- Existing roles: `proxmox_vm`, `proxmox_lxc`

## Workflows

### 1. Decision Tree: Which Platform?

**Use OpenShift Virtualization when:**
- VM needs integration with cluster workloads (services, ingress, GitOps)
- Live migration support required (RWX storage)
- Running production Linux VMs
- Need declarative VM management via YAML/GitOps
- Want automatic DNS/service discovery within cluster

**Use Proxmox VM when:**
- Running Windows (better driver support)
- Need hardware passthrough (GPU, USB, etc.)
- Legacy OS not supported by KubeVirt
- Prefer out-of-cluster isolation (VLAN 110)
- Need Proxmox-specific features (ZFS snapshots, backup)

**Use Proxmox LXC when:**
- Simple Linux utilities or services
- Lower overhead than full VM needed
- Dev/test environments
- Running many small isolated environments
- OS-level containerization sufficient (not app containers)

---

### 2. Create VM on OpenShift (KubeVirt)

**Steps:**

1. **Choose or create namespace:**
   ```bash
   oc get projects
   oc new-project my-vm-namespace
   ```

2. **Select template based on OS:**
   - RHEL 9: `templates/ocp/vm-rhel9.yaml`
   - Windows: `templates/ocp/vm-windows.yaml`

3. **Customize the VM manifest:**
   - VM name and namespace
   - CPU cores and memory
   - Disk size (DataVolume)
   - Network attachments (default pod network + optional Multus)
   - Cloud-init configuration (SSH keys, network, hostname)

4. **Apply the VM:**
   ```bash
   oc apply -f templates/ocp/vm-rhel9.yaml
   ```

5. **Monitor VM startup:**
   ```bash
   oc get vm,vmi -n <namespace>
   oc get pods -n <namespace>
   ```

6. **Access VM console:**
   ```bash
   ./scripts/ocp-console.sh <vm-name> <namespace>
   # Or directly:
   virtctl console <vm-name> -n <namespace>
   ```

7. **Optional: Check DataVolume/PVC:**
   ```bash
   oc get dv,pvc -n <namespace>
   ```

**Helper script:**
```bash
./scripts/create-vm.sh ocp my-vm-name rhel9 4 8192 50
# platform: ocp, name, os, vcpu, ram_mb, disk_gb
```

---

### 3. Create VM on Proxmox (Ansible)

**Steps:**

1. **Add host to Ansible inventory** (`automation/inventory/hosts.yaml`):
   ```yaml
   all:
     hosts:
       my-new-vm:
         ansible_host: 172.16.110.XXX  # Choose free IP in VLAN 110
         vmid: XXX                      # Choose free VMID (200-999)
         proxmox_node: wow-prox1
   ```

2. **Use template playbook:**
   ```bash
   cp templates/proxmox/deploy-vm.yaml automation/playbooks/deploy-my-vm.yaml
   ```

3. **Customize playbook variables:**
   - `hosts:` target host(s)
   - Template VMID (default: 9024 for Ubuntu cloud-init template)
   - CPU, memory, disk overrides in role vars

4. **Run playbook:**
   ```bash
   cd automation
   ansible-playbook -i inventory/hosts.yaml playbooks/deploy-my-vm.yaml
   ```

5. **Verify VM creation:**
   ```bash
   ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101 'qm list'
   ```

6. **Access VM:**
   ```bash
   ssh -i ~/.ssh/id_pfsense_sre ubuntu@172.16.110.XXX
   ```

**Helper script:**
```bash
./scripts/create-vm.sh proxmox-vm my-vm-name ubuntu 2 2048 20
# Generates playbook and updates inventory
```

**Note**: The `proxmox_vm` role clones from template 9024 (Ubuntu 22.04 cloud-init), then configures network/SSH keys via Proxmox API.

---

### 4. Create LXC on Proxmox (Ansible)

**Steps:**

1. **Add host to Ansible inventory** (`automation/inventory/hosts.yaml`):
   ```yaml
   all:
     hosts:
       my-lxc:
         ansible_host: 172.16.110.XXX  # Choose free IP
         vmid: XXX                      # Choose free VMID
         proxmox_node: wow-prox1
   ```

2. **Use template playbook:**
   ```bash
   cp templates/proxmox/deploy-lxc.yaml automation/playbooks/deploy-my-lxc.yaml
   ```

3. **Customize playbook:**
   - `hosts:` target host(s)
   - OS template (default: Ubuntu 22.04 from TSVMDS01 storage)
   - CPU cores, memory, rootfs size

4. **Run playbook:**
   ```bash
   cd automation
   ansible-playbook -i inventory/hosts.yaml playbooks/deploy-my-lxc.yaml
   ```

5. **Verify LXC creation:**
   ```bash
   ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101 'pct list'
   ```

6. **Access LXC:**
   ```bash
   ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.XXX
   ```

**Helper script:**
```bash
./scripts/create-vm.sh proxmox-lxc my-lxc ubuntu 1 512 8
# Creates playbook and updates inventory
```

**Note**: The `proxmox_lxc` role uses `community.general.proxmox_nic` to create unprivileged containers with cloud-init SSH keys.

---

### 5. Clone VM from Template

#### OpenShift (KubeVirt)
KubeVirt uses DataVolumes with `sourceRef` or `pvc.cloneFrom`:

```yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: my-vm-disk
spec:
  source:
    pvc:
      namespace: templates
      name: rhel9-template-disk
  storage:
    resources:
      requests:
        storage: 50Gi
    storageClassName: truenas-nfs
```

Or use `virtctl` for faster cloning:
```bash
virtctl image-upload dv my-vm-disk \
  --source-pvc templates/rhel9-template-disk \
  --size=50Gi \
  --storage-class=truenas-nfs
```

#### Proxmox
The `proxmox_vm` role automatically clones from template VMID 9024:

```yaml
- name: Clone VM from template
  ansible.builtin.uri:
    url: "https://{{ proxmox_api_host }}:8006/api2/json/nodes/wow-prox1/qemu/9024/clone"
    method: POST
    body:
      newid: "{{ vmid }}"
      name: "{{ inventory_hostname }}"
      full: 0  # Linked clone (faster)
```

Change `full: 1` for full clone (independent disk).

---

### 6. VM Status Across Platforms

**Check all VMs/LXCs:**
```bash
./scripts/vm-status.sh
# Shows:
# - OpenShift VirtualMachines (all namespaces)
# - Proxmox QEMU VMs
# - Proxmox LXC containers
```

**Individual checks:**

OpenShift:
```bash
oc get vm,vmi --all-namespaces
oc get pods -l kubevirt.io/domain --all-namespaces
```

Proxmox:
```bash
./scripts/proxmox-list.sh
# Or directly:
ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101 'qm list; pct list'
```

---

## Key Variables and Defaults

### OpenShift
- **SSH Key (OCP Master)**: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEJZzVG6rJ1TLR0LD2Rf1F/Wd6LdSEa9FoEvcdTqDRd sigtom@ilum`
- **Storage Class**: `truenas-nfs` (RWX, required for live migration)
- **Network**: Default pod network + Multus (workload-br130 on VLAN 130)
- **Namespace**: Create per-app or use shared namespace

### Proxmox
- **Host**: wow-prox1.sigtomtech.com (172.16.110.101)
- **VLAN**: 110 (management)
- **Gateway**: 172.16.110.1
- **Bridge**: vmbr0
- **Storage**: TSVMDS01 (ZFS)
- **Template VMID**: 9024 (Ubuntu 22.04 cloud-init)
- **SSH Keys**: Global keys from `automation/group_vars/all.yaml`

---

## Troubleshooting

### OpenShift VMs

**VM not starting:**
```bash
oc describe vm <name> -n <namespace>
oc describe vmi <name> -n <namespace>
oc logs -n <namespace> virt-launcher-<vm-name>-xxxxx
```

**DataVolume stuck in Pending:**
```bash
oc describe dv <name> -n <namespace>
oc get pvc -n <namespace>
# Check CDI importer pod:
oc get pods -n <namespace> | grep importer
```

**Live migration fails:**
- Ensure VM uses `truenas-nfs` (RWX) StorageClass
- Check AccessMode: `ReadWriteMany` required
- Verify no node affinity/taints blocking migration

**Network issues:**
- Verify Multus NetworkAttachmentDefinition exists
- Check pod network connectivity first (default interface)
- Use `virtctl console` to access VM and debug network config

### Proxmox VMs/LXCs

**Clone fails:**
```bash
# Check template exists:
ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101 'qm config 9024'
# Check VMID not in use:
qm list | grep <vmid>
```

**LXC container won't start:**
```bash
# Check container config:
pct config <vmid>
# Try manual start with error output:
pct start <vmid>
```

**Network not configured:**
- Verify IP not in use: `ping 172.16.110.XXX`
- Check VLAN 110 tagged on vmbr0
- Verify gateway 172.16.110.1 reachable from Proxmox host

**SSH key injection fails:**
- Verify global_ssh_keys in `automation/group_vars/all.yaml`
- For VMs: Template must have cloud-init enabled
- For LXCs: `pubkey` parameter passed to proxmox_nic module

---

## Files Reference

### Documentation
- `references/platform-comparison.md` - Detailed comparison of OCP vs Proxmox
- `references/existing-automation.md` - Ansible structure and role documentation

### Templates
- `templates/ocp/vm-rhel9.yaml` - KubeVirt RHEL 9 VM
- `templates/ocp/vm-windows.yaml` - KubeVirt Windows VM
- `templates/proxmox/deploy-vm.yaml` - Ansible playbook for Proxmox VM
- `templates/proxmox/deploy-lxc.yaml` - Ansible playbook for Proxmox LXC

### Scripts
- `scripts/create-vm.sh` - Unified VM/LXC creation wrapper
- `scripts/vm-status.sh` - Show VMs across both platforms
- `scripts/ocp-console.sh` - Quick virtctl console access
- `scripts/proxmox-list.sh` - List Proxmox VMs and LXCs

### Ansible
- `automation/roles/proxmox_vm/` - Proxmox VM provisioning role
- `automation/roles/proxmox_lxc/` - Proxmox LXC provisioning role
- `automation/inventory/hosts.yaml` - Inventory with Proxmox hosts
- `automation/group_vars/all.yaml` - Global variables and credentials

---

## Examples

### Example 1: Production RHEL VM on OpenShift
```bash
# Create namespace
oc new-project prod-app

# Customize template
cp templates/ocp/vm-rhel9.yaml /tmp/prod-vm.yaml
# Edit: name, cores, memory, disk size, network

# Apply
oc apply -f /tmp/prod-vm.yaml

# Monitor
oc get vm,vmi,dv,pvc -n prod-app

# Access console
./scripts/ocp-console.sh prod-vm prod-app
```

### Example 2: Windows VM on Proxmox for Active Directory
```bash
# Add to inventory
cat >> automation/inventory/hosts.yaml <<EOF
    ad-dc01:
      ansible_host: 172.16.110.50
      vmid: 250
      proxmox_node: wow-prox1
EOF

# Create playbook for Windows (manual ISO install)
# Note: proxmox_vm role is for cloud-init Linux
# For Windows, create VM manually in Proxmox GUI or use different template

./scripts/proxmox-list.sh
# Then install Windows via Proxmox console
```

### Example 3: Dev LXC for Testing
```bash
# Quick create
./scripts/create-vm.sh proxmox-lxc test-dev ubuntu 1 512 8

# This generates playbook and updates inventory
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-test-dev.yaml

# Access
ssh root@172.16.110.XXX
```

### Example 4: Clone Template on OpenShift
```bash
# Clone from existing template PVC
cat <<EOF | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: my-cloned-disk
  namespace: my-namespace
spec:
  source:
    pvc:
      namespace: templates
      name: rhel9-template
  storage:
    resources:
      requests:
        storage: 30Gi
    storageClassName: truenas-nfs
EOF

# Then reference in VM spec:
# volumes:
#   - name: rootdisk
#     dataVolume:
#       name: my-cloned-disk
```

---

## Best Practices

1. **Inventory Management**: Always update `automation/inventory/hosts.yaml` before running Ansible playbooks
2. **VMID Allocation**: Use ranges:
   - 100-199: Infrastructure VMs
   - 200-299: Application VMs
   - 300-399: LXC containers
   - 900+: Templates
3. **IP Allocation**: Document IPs in inventory, check with `ping` before assigning
4. **SSH Keys**: Use consistent keys from `group_vars/all.yaml` for Proxmox, OCP master key for KubeVirt
5. **Storage**: Use `truenas-nfs` (RWX) for OCP VMs needing live migration, otherwise `truenas-nfs-dynamic` (RWO) is fine
6. **GitOps**: Commit OpenShift VM YAMLs to Git and manage via ArgoCD for production workloads
7. **Backup**: Proxmox VMs/LXCs use Proxmox Backup Server, OCP VMs use Velero or snapshot-based backups
8. **Monitoring**: Add VMs to existing monitoring stack (Prometheus for OCP, node_exporter for Proxmox)

---

## Integration with Other Skills

- **sealed-secrets**: Encrypt sensitive VM configs (passwords, tokens) before committing
- **argocd-ops**: Deploy OpenShift VMs via GitOps, sync status, rollback
- **truenas-ops**: Verify NFS storage health before creating VMs with large disks
- **openshift-debug**: Troubleshoot VM pods, PVC provisioning, virt-launcher issues

---

## Quick Reference Commands

```bash
# OpenShift
oc get vm,vmi --all-namespaces
virtctl console <vm> -n <ns>
virtctl start <vm> -n <ns>
virtctl stop <vm> -n <ns>
virtctl migrate <vm> -n <ns>
oc get dv,pvc -n <ns>

# Proxmox (via SSH)
ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101
qm list                    # List VMs
pct list                   # List LXCs
qm start <vmid>           # Start VM
qm stop <vmid>            # Stop VM
pct start <vmid>          # Start LXC
pct enter <vmid>          # Enter LXC console

# Ansible
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/<playbook>.yaml
ansible-playbook -i inventory/hosts.yaml playbooks/<playbook>.yaml --check  # Dry run
ansible <host> -i inventory/hosts.yaml -m ping  # Test connectivity
```
