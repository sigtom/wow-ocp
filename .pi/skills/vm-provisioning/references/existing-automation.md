# Existing Ansible Automation Structure

This document details the current Ansible automation in place for Proxmox VM and LXC provisioning.

---

## Directory Structure

```
automation/
├── inventory/
│   └── hosts.yaml              # Ansible inventory (Proxmox host + VMs/LXCs)
├── group_vars/
│   └── all.yaml                # Global variables (credentials, SSH keys, networking)
├── roles/
│   ├── proxmox_vm/            # VM provisioning role
│   │   └── tasks/
│   │       └── main.yaml
│   ├── proxmox_lxc/           # LXC provisioning role
│   │   └── tasks/
│   │       └── main.yaml
│   ├── technitium_dns/        # Technitium DNS installation
│   └── technitium_record/     # Technitium DNS record management
└── playbooks/
    └── (user-created playbooks use roles)
```

---

## Inventory: `inventory/hosts.yaml`

**Purpose**: Define Proxmox host and target VMs/LXCs with their properties.

**Example**:
```yaml
all:
  hosts:
    wow-prox1:
      ansible_host: 172.16.110.101
      proxmox_api_host: 172.16.110.101
    
    dns2:
      ansible_host: 172.16.110.211
      vmid: 211
      proxmox_node: wow-prox1
    
    my-lxc:
      ansible_host: 172.16.110.220
      vmid: 220
      proxmox_node: wow-prox1
```

**Key Variables**:
- `ansible_host`: IP address of the VM/LXC (must be free in VLAN 110)
- `vmid`: Proxmox VM ID (must be unique)
- `proxmox_node`: Proxmox node name (always `wow-prox1` in this setup)

**Host Groups**: All hosts are under `all:`. Add custom groups if needed for targeting subsets.

---

## Global Variables: `group_vars/all.yaml`

**Purpose**: Store credentials, SSH keys, and networking defaults used across all playbooks.

**Current Contents**:
```yaml
# Proxmox API Credentials
pve_api_user: "sre-bot@pve"
pve_api_token_id: "sre-token"
pve_api_token_secret: "{{ lookup('env', 'PROXMOX_SRE_BOT_API_TOKEN') }}"

# Global SSH Keys to inject into VMs/LXCs
global_ssh_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILPyc7oAxzmaymnrZWblYRbTH/hOd+OPaQStsMNi/3bU sigtom@localhost.localdomain"
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEEJZzVG6rJ1TLR0LD2Rf1F/Wd6LdSEa9FoEvcdTqDRd sigtom@ilum"

# Networking Defaults
lab_vlan_mgmt: 110
lab_bridge: "vmbr0"
lab_gw: "172.16.110.1"
```

**Environment Variable**:
Set `PROXMOX_SRE_BOT_API_TOKEN` before running playbooks:
```bash
export PROXMOX_SRE_BOT_API_TOKEN="your-token-here"
```

**SSH Keys**: Add new keys to `global_ssh_keys` list to inject into all future VMs/LXCs.

---

## Role: `proxmox_vm`

**Purpose**: Clone a VM from a cloud-init template and configure it.

**Location**: `automation/roles/proxmox_vm/tasks/main.yaml`

**What it does**:
1. Checks if VM already exists (via Proxmox API)
2. Clones VM from template VMID 9024 (Ubuntu 22.04 cloud-init)
3. Waits for clone operation to complete
4. Configures VM via SSH to Proxmox host:
   - Injects SSH keys from `global_ssh_keys`
   - Sets static IP from `ansible_host`
   - Sets gateway to `lab_gw`
   - Configures CPU and memory (default: 1 core, 1024MB)
5. Starts the VM
6. Waits for cloud-init to complete (20 seconds)

**Template Used**:
- **VMID 9024**: Ubuntu 22.04 cloud-init template
- **Storage**: TSVMDS01 (ZFS)
- **Clone Mode**: Linked clone (`full: 0`) for faster provisioning

**Key Tasks**:
```yaml
# Check if VM exists
- ansible.builtin.uri:
    url: "https://{{ proxmox_api_host }}:8006/api2/json/nodes/wow-prox1/qemu/{{ vmid }}/status/current"
    method: GET
    headers:
      Authorization: "PVEAPIToken={{ pve_api_user }}!{{ pve_api_token_id }}={{ pve_api_token_secret }}"
    validate_certs: no
    status_code: [200, 404, 500]
  register: vm_check

# Clone from template
- ansible.builtin.uri:
    url: "https://{{ proxmox_api_host }}:8006/api2/json/nodes/wow-prox1/qemu/9024/clone"
    method: POST
    body_format: form-urlencoded
    body:
      newid: "{{ vmid }}"
      name: "{{ inventory_hostname }}"
      full: 0  # Linked clone
  when: vm_check.status != 200

# Configure via SSH (network, keys, resources)
- ansible.builtin.shell: |
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i ~/.ssh/id_pfsense_sre root@{{ hostvars[proxmox_node].ansible_host }} << 'REMOTE'
    echo "{{ global_ssh_keys | join('\n') }}" > /tmp/keys.pub
    qm set {{ vmid }} --sshkeys /tmp/keys.pub
    qm set {{ vmid }} --ipconfig0 "ip={{ ansible_host }}/24,gw={{ lab_gw }}"
    qm set {{ vmid }} --memory 1024 --cores 1
    rm /tmp/keys.pub
    REMOTE

# Start VM
- ansible.builtin.uri:
    url: "https://{{ proxmox_api_host }}:8006/api2/json/nodes/wow-prox1/qemu/{{ vmid }}/status/start"
    method: POST
```

**Usage in Playbook**:
```yaml
---
- hosts: my-vm
  gather_facts: no
  roles:
    - proxmox_vm
```

**Customization**:
- Override CPU/memory by setting vars before role:
  ```yaml
  - hosts: my-vm
    vars:
      vm_cores: 4
      vm_memory: 4096
    roles:
      - proxmox_vm
  ```
- Change template VMID by modifying `/qemu/9024/clone` URL in role

**Limitations**:
- Only works with cloud-init enabled templates
- Requires SSH access to Proxmox host with `~/.ssh/id_pfsense_sre` key
- Hardcoded to `wow-prox1` node

---

## Role: `proxmox_lxc`

**Purpose**: Create and start an LXC container with SSH keys and network config.

**Location**: `automation/roles/proxmox_lxc/tasks/main.yaml`

**What it does**:
1. Creates unprivileged LXC container using `community.general.proxmox_nic` module
2. Configures:
   - OS template: Ubuntu 22.04 from TSVMDS01 storage
   - SSH public keys from `global_ssh_keys`
   - Static IP from `ansible_host` on VLAN 110
   - Root filesystem size (default: 8GB)
   - CPU cores (default: 1)
   - Memory (default: 512MB)
3. Starts the container using `community.general.proxmox` module

**Key Tasks**:
```yaml
# Create LXC container
- community.general.proxmox_nic:
    api_user: "{{ pve_api_user }}"
    api_token_id: "{{ pve_api_token_id }}"
    api_token_secret: "{{ pve_api_token_secret }}"
    api_host: "{{ proxmox_api_host }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ vmid }}"
    hostname: "{{ inventory_hostname }}"
    ostemplate: "TSVMDS01:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    password: "{{ lookup('password', '/dev/null length=20 chars=ascii_letters,digits') }}"
    pubkey: "{{ global_ssh_keys | join('\n') }}"
    storage: "TSVMDS01"
    rootfs: "TSVMDS01:8"
    memory: 512
    cores: 1
    net0: "name=eth0,bridge={{ lab_bridge }},tag={{ lab_vlan_mgmt }},ip={{ ansible_host }}/24,gw={{ lab_gw }}"
    state: present
    unprivileged: yes

# Start LXC container
- community.general.proxmox:
    api_user: "{{ pve_api_user }}"
    api_token_id: "{{ pve_api_token_id }}"
    api_token_secret: "{{ pve_api_token_secret }}"
    api_host: "{{ proxmox_api_host }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ vmid }}"
    state: started
```

**Usage in Playbook**:
```yaml
---
- hosts: my-lxc
  gather_facts: no
  roles:
    - proxmox_lxc
```

**Customization**:
- Override resources:
  ```yaml
  - hosts: my-lxc
    vars:
      lxc_cores: 2
      lxc_memory: 1024
      lxc_rootfs_size: 16
    roles:
      - proxmox_lxc
  ```
- Change OS template by modifying `ostemplate` parameter in role

**Modules Required**:
- `community.general` collection:
  ```bash
  ansible-galaxy collection install community.general
  ```

**Limitations**:
- Only creates unprivileged containers (safer but limited privileges)
- Requires OS template to exist in TSVMDS01 storage
- No automatic DNS registration (use `technitium_record` role separately)

---

## Role: `technitium_dns`

**Purpose**: Install and configure Technitium DNS server on a target host.

**Not directly related to VM provisioning**, but useful for DNS setup after VM/LXC creation.

**Usage**: Apply to a VM/LXC after it's created and accessible via SSH.

---

## Role: `technitium_record`

**Purpose**: Add/update DNS records in Technitium DNS server.

**Use Case**: Automatically register new VMs/LXCs in DNS after provisioning.

**Usage**:
```yaml
- hosts: localhost
  roles:
    - role: technitium_record
      vars:
        dns_server: "172.16.110.211"
        dns_zone: "sigtomtech.com"
        dns_record: "my-vm"
        dns_record_type: "A"
        dns_record_value: "172.16.110.250"
```

---

## How to Run Playbooks

### Basic Usage
```bash
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/my-playbook.yaml
```

### Dry Run (Check Mode)
```bash
ansible-playbook -i inventory/hosts.yaml playbooks/my-playbook.yaml --check
```

### Verbose Output
```bash
ansible-playbook -i inventory/hosts.yaml playbooks/my-playbook.yaml -v
# Or -vv, -vvv for more verbosity
```

### Target Specific Host
```bash
ansible-playbook -i inventory/hosts.yaml playbooks/my-playbook.yaml --limit my-vm
```

### Pass Extra Variables
```bash
ansible-playbook -i inventory/hosts.yaml playbooks/my-playbook.yaml \
  -e "vm_cores=4" -e "vm_memory=8192"
```

---

## Example Playbook: Deploy VM

**File**: `automation/playbooks/deploy-vm.yaml`

```yaml
---
- name: Deploy Proxmox VM
  hosts: my-vm
  gather_facts: no
  roles:
    - proxmox_vm

- name: Register VM in DNS
  hosts: localhost
  gather_facts: no
  roles:
    - role: technitium_record
      vars:
        dns_server: "172.16.110.211"
        dns_zone: "sigtomtech.com"
        dns_record: "{{ hostvars['my-vm'].inventory_hostname }}"
        dns_record_type: "A"
        dns_record_value: "{{ hostvars['my-vm'].ansible_host }}"
```

**Run**:
```bash
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-vm.yaml
```

---

## Example Playbook: Deploy LXC

**File**: `automation/playbooks/deploy-lxc.yaml`

```yaml
---
- name: Deploy Proxmox LXC
  hosts: my-lxc
  gather_facts: no
  roles:
    - proxmox_lxc

- name: Wait for LXC to boot
  hosts: my-lxc
  gather_facts: no
  tasks:
    - name: Wait for SSH
      wait_for_connection:
        delay: 5
        timeout: 60

- name: Configure LXC
  hosts: my-lxc
  tasks:
    - name: Update packages
      apt:
        update_cache: yes
        upgrade: dist
```

**Run**:
```bash
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-lxc.yaml
```

---

## Best Practices

### 1. Inventory Management
- Always add new VMs/LXCs to `inventory/hosts.yaml` before running playbooks
- Use descriptive hostnames matching DNS entries
- Document VMID ranges (e.g., 200-299 for VMs, 300-399 for LXCs)

### 2. Variable Management
- Store common variables in `group_vars/all.yaml`
- Use host-specific variables in inventory for per-VM customization
- Never commit secrets to Git (use env vars like `PROXMOX_SRE_BOT_API_TOKEN`)

### 3. Playbook Organization
- Keep playbooks in `playbooks/` directory
- Name playbooks descriptively: `deploy-<service>.yaml`
- Use roles for reusability, tasks for one-off configs

### 4. Testing
- Always use `--check` mode first to preview changes
- Test on dev/staging hosts before production
- Verify SSH connectivity: `ansible <host> -i inventory/hosts.yaml -m ping`

### 5. Documentation
- Comment complex tasks in roles
- Document custom variables in playbook headers
- Keep inventory comments for IP allocation tracking

---

## Troubleshooting

### Ansible Can't Connect to Proxmox API
**Check**:
- `PROXMOX_SRE_BOT_API_TOKEN` environment variable set
- Token has correct permissions in Proxmox
- Proxmox host reachable: `ping 172.16.110.101`

**Debug**:
```bash
curl -k -H "Authorization: PVEAPIToken=sre-bot@pve!sre-token=$PROXMOX_SRE_BOT_API_TOKEN" \
  https://172.16.110.101:8006/api2/json/nodes/wow-prox1/qemu
```

### VM Clone Fails
**Check**:
- Template VMID 9024 exists: `ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101 'qm list | grep 9024'`
- VMID not already in use: `qm list | grep <vmid>`
- Storage TSVMDS01 has space: `pvesm status`

### SSH Key Injection Fails
**Check**:
- `~/.ssh/id_pfsense_sre` key exists and has correct permissions (600)
- SSH to Proxmox host works: `ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101`
- Global SSH keys valid in `group_vars/all.yaml`

### LXC Creation Fails
**Check**:
- `community.general` collection installed: `ansible-galaxy collection list | grep community.general`
- OS template exists: `ssh -i ~/.ssh/id_pfsense_sre root@172.16.110.101 'pveam list TSVMDS01'`
- VMID not in use: `pct list | grep <vmid>`

### VM/LXC Network Not Working
**Check**:
- IP not already in use: `ping 172.16.110.XXX` (should fail before creation)
- VLAN 110 configured on vmbr0: Check Proxmox network settings
- Gateway 172.16.110.1 reachable from Proxmox: `ping 172.16.110.1`

---

## Extending Automation

### Add Support for Windows VMs
1. Create new role `proxmox_vm_windows`
2. Use different template VMID (Windows ISO or template)
3. Skip SSH key injection (use other config method)
4. Handle Windows-specific networking

### Add Post-Provisioning Tasks
1. Create role `post_provision`
2. Include tasks for:
   - Package installation
   - Security hardening
   - Monitoring agent setup
   - DNS registration

### Integrate with OpenShift
1. Add VMs to OpenShift as external nodes (not recommended)
2. Or use for bootstrapping OCP infrastructure VMs
3. Could automate haproxy/bastion VM deployment

---

## Summary

The existing Ansible automation provides:
- **Inventory**: Centralized host definitions in `inventory/hosts.yaml`
- **Variables**: Global config in `group_vars/all.yaml`
- **Roles**:
  - `proxmox_vm`: Clone and configure VMs from cloud-init template
  - `proxmox_lxc`: Create and start LXC containers
  - `technitium_dns` / `technitium_record`: DNS management
- **Playbooks**: User-created, leverage roles for VM/LXC provisioning

**Strengths**:
- Idempotent (safe to re-run)
- Template-based (fast cloning)
- SSH key injection for secure access
- Network config via cloud-init

**Gaps**:
- No Windows VM support (manual or different role needed)
- No integration with OpenShift
- No automatic DNS registration in playbooks
- Limited customization without modifying roles

**Future Enhancements**:
- Full-featured Windows VM role
- GitOps-triggered Ansible runs via ArgoCD/Jenkins
- Automated DNS registration in VM/LXC roles
- Integration with TrueNAS for VM storage provisioning
