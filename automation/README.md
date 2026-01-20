# WOW-OCP Ansible Automation

Infrastructure-as-Code automation for Proxmox-based infrastructure using Ansible.

> **New to this project?** See [GETTING-STARTED.md](./GETTING-STARTED.md) for setup instructions.

## 🔐 Security-First Approach

**Secrets are managed through Bitwarden.** No secrets are committed to git or stored in plaintext files.

- **For OpenShift/Kubernetes**: External Secrets Operator (ESO) syncs from Bitwarden
- **For Ansible playbooks**: Native Bitwarden lookup plugin
- **Architecture documentation**: See [External Secrets Operator docs](../docs/architecture/external-secrets-bitwarden.md)

### Running Playbooks

```bash
# Unlock Bitwarden once
export BW_SESSION=$(bw unlock --raw)

# Run playbooks - secrets fetched automatically
cd automation
ansible-playbook playbooks/deploy-nautobot.yaml
```

Playbooks use Ansible's native Bitwarden lookup plugin to fetch secrets on-demand.

## 📁 Project Structure

```
automation/
├── README.md                    # This file
├── ansible.cfg                  # Ansible configuration
│
├── inventory/
│   └── hosts.yaml              # Inventory of all managed hosts
│
├── group_vars/
│   ├── all.yaml                # Global variables (non-sensitive)
│   └── all.yml                 # Additional variables
│
├── playbooks/
│   ├── deploy-nautobot-app.yaml      # Deploy Nautobot application stack
│   ├── deploy-traefik.yaml           # Deploy Traefik reverse proxy
│   ├── deploy-vaultwarden.yaml       # Deploy Vaultwarden password manager
│   ├── nautobot-create-superuser.yaml # Create/update Nautobot admin user
│   └── health-check.yaml             # Standalone health check utility
│
├── roles/
│   ├── proxmox_vm/             # Provision VMs via Proxmox API
│   ├── proxmox_lxc/            # Provision LXC containers
│   ├── technitium_dns/         # Install Technitium DNS server
│   ├── technitium_record/      # Manage DNS records
│   └── nautobot_server/        # Deploy Nautobot with Docker Compose
│
└── deploy_dns_ha.yaml          # Deploy HA DNS infrastructure
```

## 🚀 Common Operations

### Deploy Nautobot IPAM

Deploys Nautobot with PostgreSQL, Redis, and Traefik SSL integration:

```bash
# Unlock Bitwarden
export BW_SESSION=$(bw unlock --raw)

# Deploy application stack (LXC 215 must exist with Docker installed)
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-nautobot-app.yaml
```

Access at: https://ipmgmt.sigtom.dev

**Note:** LXC provisioning uses generic cattle infrastructure roles. See deployed services section for details.

### Deploy DNS Server

```bash
ansible-playbook deploy_dns_ha.yaml
```

### Provision Proxmox VM

```bash
ansible-playbook playbooks/deploy-wow-clawdbot.yaml
```

### Check Mode (Dry Run)

```bash
ansible-playbook playbooks/deploy-nautobot.yaml --check
```

### Verbose Output

```bash
ansible-playbook playbooks/deploy-nautobot.yaml -vv
```

## 🏗️ Available Roles

### proxmox_vm
Provisions VMs on Proxmox using the API (no community.general.proxmox dependency).

**Features:**
- Clone from templates
- Configure CPU, memory, storage
- Network configuration (static or DHCP)
- SSH key injection
- Wait for VM ready state

### proxmox_lxc
Provisions LXC containers on Proxmox.

**Features:**
- Create containers from templates
- Resource allocation
- Network configuration
- Root password generation

### nautobot_server
Full Nautobot deployment stack.

**Components:**
- PostgreSQL 15
- Redis 7
- Nautobot 2.3
- NGINX reverse proxy
- Let's Encrypt SSL (certbot)

**Features:**
- Automatic database initialization
- Superuser creation
- Static file collection
- Plugin support
- Persistent data volumes

### technitium_dns
Installs and configures Technitium DNS server.

### technitium_record
Manages DNS records via Technitium API.

## 🔑 Secret Management

Secrets are accessed via Ansible's native Bitwarden lookup plugin:

```yaml
# In playbooks
vars:
  bw_session: "{{ lookup('env', 'BW_SESSION') }}"
  db_password: "{{ lookup('community.general.bitwarden',
                         'nautobot-db-password',
                         field='password',
                         bw_session=bw_session) }}"
```

**Required Bitwarden Items:**
- `proxmox-sre-token` - Proxmox API authentication
- `nautobot-db-password` - PostgreSQL password
- `nautobot-redis-password` - Redis password
- `nautobot-secret-key` - Django secret key
- `nautobot-admin-password` - Admin password
- `technitium-api-url` - DNS API endpoint
- `technitium-api-token` - DNS API token

****

## 📋 Requirements

### System Requirements
- Ansible 2.14+
- Python 3.8+
- Bitwarden CLI (`bw`)
- Access to Bitwarden vault

### Ansible Collections
```bash
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.posix
```

### Python Packages
```bash
pip install requests
```

## 🔧 Configuration

### Inventory

Edit `inventory/hosts.yaml` to add/modify hosts:

```yaml
all:
  hosts:
    wow-prox1:
      ansible_host: 172.16.110.101
  children:
    proxmox_vms:
      hosts:
        my-new-vm:
          ansible_host: 172.16.110.220
          vmid: 220
          proxmox_node: wow-prox1
```

### Global Variables

Edit `group_vars/all.yaml` for non-sensitive defaults:

```yaml
# Networking
lab_vlan_mgmt: 110
lab_bridge: "vmbr0"
lab_gw: "172.16.110.1"

# SSH Keys
global_ssh_keys:
  - "ssh-ed25519 AAAAC3..."
```

**Note:** Never put secrets in `group_vars/` - use Bitwarden lookup instead.

## 🐛 Troubleshooting

### "Bitwarden CLI not found"
```bash
# Install Bitwarden CLI
wget https://vault.bitwarden.com/download/?app=cli&platform=linux -O bw.zip
unzip bw.zip && chmod +x bw
sudo mv bw /usr/local/bin/
```

### "BW_SESSION not set"
```bash
# Unlock Bitwarden
export BW_SESSION=$(bw unlock --raw)

# Or login first if needed
bw login
export BW_SESSION=$(bw unlock --raw)
```

### "Ansible module not found"
```bash
ansible-galaxy collection install community.general
```

### SSH Connection Issues
```bash
# Test SSH connectivity
ansible -i inventory/hosts.yaml ipmgmt -m ping

# Use verbose mode
ansible -i inventory/hosts.yaml ipmgmt -m ping -vvv
```

### Proxmox API Authentication Failures
```bash
# Verify token exists in Bitwarden
bw get item proxmox-sre-token

# Test token manually
export TOKEN=$(bw get item proxmox-sre-token --session $BW_SESSION | jq -r '.login.password')
curl -k -H "Authorization: PVEAPIToken=sre-bot@pve!sre-token=$TOKEN" \
  https://172.16.110.101:8006/api2/json/nodes
```

## 📚 Examples

### Deploy New Service

1. Create a role in `roles/my_service/`
2. Add playbook in `playbooks/deploy-my-service.yaml`
3. Add required secrets to Bitwarden vault
4. Run: `ansible-playbook playbooks/deploy-my-service.yaml`

### Add SSH Key to All VMs

Edit `group_vars/all.yaml`:

```yaml
global_ssh_keys:
  - "ssh-ed25519 AAAAC3... user@host"
  - "ssh-ed25519 AAAAC3... another@host"
```

Re-run VM provisioning playbooks.

## 🔐 Security Best Practices

✅ **DO:**
- Store secrets in Bitwarden vault
- Use Bitwarden lookup plugin in playbooks
- Review changes with `--check` before applying
- Commit playbooks and roles to git

❌ **DON'T:**
- Hardcode secrets in playbooks
- Commit `.env` files with real secrets
- Store passwords in inventory files
- Leave BW_SESSION in shell history (use `history -d`)

## 🤝 Contributing

When adding new playbooks or roles:

1. Follow existing role structure
2. Document all variables in role's `README.md`
3. Use Bitwarden lookup for any secrets
4. Add validation tasks for required variables
5. Include example usage in role documentation
6. Use `no_log: true` for sensitive operations

## 🌐 Deployed Services

### Traefik Reverse Proxy
**LXC:** 210 @ 172.16.100.10
**Purpose:** Centralized reverse proxy with automatic SSL
**Domains:** *.sigtom.dev, *.sigtom.com, *.sigtom.io, *.nixsysadmin.io, *.tecnixsystems.com, *.sigtom.info, *.sigtomtech.com
**Dashboard:** https://traefik.sigtom.dev (BasicAuth)
**Docs:** [TRAEFIK.md](./TRAEFIK.md)

### Nautobot IPAM/DCIM
**LXC:** 215 @ 172.16.100.15
**Purpose:** Network source of truth and IP address management
**URL:** https://ipmgmt.sigtom.dev
**Playbooks:** `deploy-nautobot-app.yaml`, `nautobot-create-superuser.yaml`
**Stack:** Nautobot + PostgreSQL 15 + Redis 7
**Secrets:** Managed via Bitwarden (NAUTOBOT_SECRET_KEY, NAUTOBOT_DB_PASSWORD, NAUTOBOT_SUPERUSER_PASSWORD, NAUTOBOT_SUPERUSER_API_TOKEN)

### Technitium DNS (HA Cluster)
**Primary:** OpenShift VM @ 172.16.130.210
**Secondary:** Proxmox VM @ 172.16.110.211
**Purpose:** Authoritative DNS with ad-blocking
**Dashboard:** https://dns.sigtom.dev
**Integration:** User Workload Monitoring with Prometheus + Grafana

### Vaultwarden
**LXC:** 105 @ 172.16.110.105 (Proxmox, not OpenShift)
**Purpose:** Self-hosted password manager (Bitwarden-compatible)
**URL:** https://vault.sigtomtech.com
**Stack:** Vaultwarden + Caddy (standalone TLS)
**Docs:** [VAULTWARDEN.md](./VAULTWARDEN.md)

## 📖 Additional Documentation

- [Traefik Operations](./TRAEFIK.md) - Reverse proxy configuration and service integration
- [IP Inventory](./IP-INVENTORY.md) - Complete IP address allocation across VLANs
- [Nautobot Role](./roles/nautobot_server/README.md) - Nautobot deployment details
- [External Secrets Operator](../docs/architecture/external-secrets-bitwarden.md) - ESO for OpenShift

## 🔗 Related Projects

- [WOW-OCP Main Repository](../) - OpenShift homelab GitOps
- [Bitwarden](https://bitwarden.com/) - Open source password manager
- [Nautobot](https://nautobot.com/) - Network Source of Truth and IPAM
- [Technitium DNS](https://technitium.com/dns/) - Open-source DNS server

## 📝 License

Part of the WOW-OCP homelab project.
