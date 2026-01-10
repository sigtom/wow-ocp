# Getting Started with Automation

This directory contains generic Ansible automation for deploying infrastructure on Proxmox and managing services.

## Quick Start

### 1. Prerequisites

- Ansible 2.14+
- Python 3.8+
- Bitwarden CLI (`bw`) for secret management
- SSH access to Proxmox host
- Proxmox API token

### 2. Install Dependencies

```bash
cd automation

# Install Ansible collections
ansible-galaxy collection install -r requirements.yml

# Install Python dependencies
pip install requests
```

### 3. Configure Your Environment

Copy example files and customize:

```bash
# Copy inventory template
cp inventory/hosts.yaml.example inventory/hosts.yaml

# Copy variables template
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml

# Edit with your environment details
vim inventory/hosts.yaml
vim inventory/group_vars/all.yml
```

### 4. Set Up Secrets in Bitwarden

Create these items in your Bitwarden vault as "Login" items:

**Proxmox API:**
- Item name: `proxmox-sre-token`
- Password field: Your Proxmox API token (format: `UUID`)

**For Nautobot (if deploying):**
- `NAUTOBOT_SECRET_KEY` - Django secret (50+ chars)
- `NAUTOBOT_DB_PASSWORD` - PostgreSQL password
- `NAUTOBOT_SUPERUSER_PASSWORD` - Admin password
- `NAUTOBOT_SUPERUSER_API_TOKEN` - API token

**For Traefik (if deploying):**
- `CLOUDFLARE_API_TOKEN` - Cloudflare DNS API token for Let's Encrypt DNS-01

### 5. Create Your First Playbook

Copy an example playbook and customize:

```bash
# Example: Deploy an LXC container
cat > playbooks/deploy-my-service.yaml << 'EOF'
---
- name: "Deploy My Service"
  hosts: localhost
  gather_facts: false
  
  vars:
    lxc_vmid: 220
    lxc_hostname: "my-service"
    lxc_ip: "172.16.110.220"
    proxmox_node: "wow-prox1"
    size_profile: "medium"  # small, medium, large
    network_profile: "apps"  # or "proxmox-mgmt"
  
  roles:
    - role: provision_lxc_generic
    - role: health_check
      health_profile: "basic"
    - role: post_provision
      post_provisioning_enabled: true
      post_provision_profile: "docker_host"
EOF

# Run it
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-my-service.yaml
```

## Available Roles

### Infrastructure Provisioning

**provision_lxc_generic**
- Provision LXC containers on Proxmox
- T-shirt sizing (small/medium/large/xlarge)
- Network profiles (apps, proxmox-mgmt)
- Automatic health checks

**provision_vm_generic**
- Provision VMs on Proxmox
- Cloud-init support
- Resource profiles
- OS template selection

### Post-Provisioning

**post_provision**
- Docker host setup (Docker CE + Compose v2)
- Web server (nginx + certbot)
- Database preparation (PostgreSQL via Docker)

**health_check**
- SSH connectivity
- Cloud-init completion
- Package manager availability
- Disk space checks
- Service-specific checks (Docker, web, database)

**snapshot_manager**
- Create snapshots (pre-provision, post-provision)
- Automatic cleanup based on retention policy
- List and delete operations

## Configuration Reference

### Size Profiles (VMs)

```yaml
small:    1 CPU,  1GB RAM,  20GB disk
medium:   2 CPU,  2GB RAM,  40GB disk
large:    4 CPU,  4GB RAM,  80GB disk
xlarge:   8 CPU,  8GB RAM, 200GB disk
```

### Size Profiles (LXC)

```yaml
small:    1 CPU,  512MB RAM,   8GB disk
medium:   2 CPU,    2GB RAM,  20GB disk
large:    4 CPU,    4GB RAM,  50GB disk
xlarge:   8 CPU,    8GB RAM, 100GB disk
```

### Network Profiles

**apps** (default)
- Native bridge (vmbr0)
- Gateway: 172.16.100.1
- VLAN: None (native)

**proxmox-mgmt** (restricted)
- VLAN: 110
- Gateway: 172.16.110.1
- Requires justification variable

## Workflow Examples

### Deploy Traefik Reverse Proxy

```bash
# 1. Unlock Bitwarden
export BW_SESSION=$(bw unlock --raw)

# 2. Deploy (provisions LXC + installs Traefik + configures SSL)
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-traefik.yaml
```

### Deploy Nautobot IPAM

```bash
# 1. Ensure secrets exist in Bitwarden (see step 4 above)
export BW_SESSION=$(bw unlock --raw)

# 2. Deploy application stack
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-nautobot-app.yaml
```

### Health Check Existing Host

```bash
# Run standalone health check
ansible-playbook -i inventory/hosts.yaml playbooks/health-check.yaml \
  -e target_host=my-server \
  -e health_profile=docker
```

## Troubleshooting

### "Bitwarden item not found"

```bash
# List all items to verify name
bw list items --session $BW_SESSION | jq -r '.[].name'

# Get specific item
bw get item "NAUTOBOT_SECRET_KEY" --session $BW_SESSION
```

### "Proxmox API authentication failed"

```bash
# Verify token format in Bitwarden
bw get item proxmox-sre-token --session $BW_SESSION

# Test API access manually
export PROXMOX_TOKEN=$(bw get password proxmox-sre-token --session $BW_SESSION)
curl -k -H "Authorization: PVEAPIToken=sre-bot@pve!sre-token=$PROXMOX_TOKEN" \
  https://YOUR_PROXMOX_IP:8006/api2/json/nodes
```

### "SSH connection refused"

```bash
# Verify SSH key path in ansible.cfg
cat ansible.cfg | grep private_key_file

# Test SSH manually
ssh -i ~/.ssh/YOUR_KEY root@TARGET_IP
```

## Security Best Practices

1. **Never commit secrets** - Use Bitwarden for all credentials
2. **Review before applying** - Use `--check` flag for dry runs
3. **Keep inventory private** - Don't commit `hosts.yaml` or `group_vars/*.yml`
4. **Use .example files** - Commit sanitized examples, not real configs
5. **Rotate tokens regularly** - Update Bitwarden items, re-run playbooks if needed

## Project Structure

```
automation/
├── GETTING-STARTED.md          # This file
├── README.md                   # Overview and reference
├── .gitignore                  # Excludes environment-specific files
│
├── inventory/
│   ├── hosts.yaml.example      # Template - copy and customize
│   └── group_vars/
│       └── all.yml.example     # Template - copy and customize
│
├── playbooks/
│   └── *.example.yaml          # Example playbooks
│
├── roles/                      # Generic, reusable roles (committed)
└── templates/                  # Jinja2 templates (committed)
```

## Getting Help

- Check role documentation: `automation/roles/<role-name>/README.md`
- Review example playbooks in `playbooks/*.example.yaml`
- See main project README: `../README.md`
- OpenShift-specific docs: `../docs/`

## Contributing

When adding new roles or playbooks:

1. Use variables for all environment-specific values
2. Create `.example` files for playbooks
3. Document all variables in role README
4. Test with `--check` mode before committing
5. Never commit real inventory, secrets, or credentials
