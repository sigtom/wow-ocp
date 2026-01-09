# Nautobot Server Role

Ansible role to deploy and configure Nautobot IPAM on Ubuntu 22.04 using Docker Compose, with NGINX reverse proxy and Let's Encrypt SSL certificates.

## Overview

This role implements a 5-phase installation process:

1. **System Preparation** - Install Docker, set timezone, configure hostname
2. **Docker Setup** - Deploy PostgreSQL, Redis, and Nautobot containers
3. **SSL Setup** - Configure NGINX and obtain Let's Encrypt certificates
4. **Initialize** - Run migrations, create superuser, collect static files
5. **Verify** - Health checks and access validation

## Requirements

### Target System
- Ubuntu 22.04 LTS (tested)
- Minimum 2GB RAM, 2 CPU cores
- 50GB disk space
- SSH access with sudo privileges

### Prerequisites
- DNS A record pointing to target server (required for Let's Encrypt)
- Port 80 and 443 accessible from the internet (for Let's Encrypt validation)
- Ansible 2.9+ on control node

### Ansible Collections
```bash
ansible-galaxy collection install community.general
```

## Role Variables

### Required (via environment variables)
```bash
export NAUTOBOT_SUPERUSER_PASSWORD='secure-admin-password'
```

### Optional (auto-generated if not provided)
```bash
export NAUTOBOT_DB_PASSWORD='postgresql-password'
export NAUTOBOT_REDIS_PASSWORD='redis-password'
export NAUTOBOT_SECRET_KEY='django-secret-key-64-chars'
```

### Default Variables (in `vars/main.yaml`)
```yaml
nautobot_domain: "ipmgmt.sigtom.dev"
nautobot_hostname: "ipmgmt"
nautobot_version: "2.3-py3.11"
nautobot_base_dir: "/opt/nautobot"
nautobot_timezone: "America/New_York"
nautobot_superuser_username: "sigtom"
nautobot_superuser_email: "sigtom@protonmail.com"
```

### Customization
Override variables in your playbook:
```yaml
- hosts: ipmgmt
  roles:
    - role: nautobot_server
      vars:
        nautobot_domain: "ipam.example.com"
        nautobot_superuser_username: "admin"
        nautobot_superuser_email: "admin@example.com"
```

## Usage

### Basic Deployment
```bash
# Set required password
export NAUTOBOT_SUPERUSER_PASSWORD='MySecurePassword123!'

# Run playbook
ansible-playbook automation/playbooks/deploy-nautobot.yaml -i automation/inventory/hosts.yaml
```

### Custom Deployment
```bash
# Set all secrets manually
export NAUTOBOT_SUPERUSER_PASSWORD='admin-password'
export NAUTOBOT_DB_PASSWORD='db-password'
export NAUTOBOT_REDIS_PASSWORD='redis-password'
export NAUTOBOT_SECRET_KEY='very-long-random-secret-key-at-least-64-characters-long'

# Run with custom domain
ansible-playbook automation/playbooks/deploy-nautobot.yaml \
  -i automation/inventory/hosts.yaml \
  -e "nautobot_domain=ipam.example.com"
```

### Run Specific Phases
```bash
# Only run system prep (Phase 1)
ansible-playbook automation/playbooks/deploy-nautobot.yaml --tags phase1

# Skip SSL setup (useful for testing)
ansible-playbook automation/playbooks/deploy-nautobot.yaml --skip-tags phase3

# Re-run initialization only
ansible-playbook automation/playbooks/deploy-nautobot.yaml --tags phase4
```

## Idempotency

The role is designed to be idempotent:
- Docker installation skipped if already present
- Secrets preserved if `.env` file exists
- Superuser creation skipped if user already exists
- SSL certificate skipped if already obtained
- Static files collection skipped if already present

Re-running the playbook is safe and will only apply missing configurations.

## Directory Structure

After deployment, the following structure exists on the target system:

```
/opt/nautobot/
├── docker-compose.yml       # Container orchestration
├── .env                      # Secrets (mode 600)
├── local_requirements.txt    # Python plugins
├── postgres/                 # PostgreSQL data
├── redis/                    # Redis data
└── nautobot/
    ├── media/                # Uploaded files
    ├── git/                  # Git repositories
    ├── jobs/                 # Custom jobs
    └── static/               # Static assets (CSS, JS)
```

## Post-Deployment

### Access Nautobot
1. Open browser: `https://ipmgmt.sigtom.dev`
2. Login with credentials:
   - Username: `sigtom` (or custom value)
   - Password: `[NAUTOBOT_SUPERUSER_PASSWORD]`

### Management Commands

```bash
# SSH to server
ssh ubuntu@172.16.110.213

# Navigate to Nautobot directory
cd /opt/nautobot

# View logs
docker compose logs -f nautobot
docker compose logs -f nautobot-worker

# Check container status
docker compose ps

# Restart services
docker compose restart

# Access Nautobot shell
docker compose exec nautobot nautobot-server nbshell

# Run management commands
docker compose exec nautobot nautobot-server --help
```

### Backup and Restore

#### Backup
```bash
# Database backup
docker compose exec -T postgres pg_dump -U nautobot nautobot | gzip > backup_$(date +%Y%m%d).sql.gz

# Configuration backup
tar -czf nautobot-config-$(date +%Y%m%d).tar.gz /opt/nautobot/.env /opt/nautobot/docker-compose.yml
```

#### Restore
```bash
# Restore database
gunzip < backup_20250108.sql.gz | docker compose exec -T postgres psql -U nautobot nautobot
```

### Upgrades

```bash
cd /opt/nautobot

# Pull latest images
docker compose pull

# Stop services
docker compose down

# Start with new images
docker compose up -d

# Run migrations
docker compose exec nautobot nautobot-server migrate

# Collect static files
docker compose exec nautobot nautobot-server collectstatic --no-input

# Restart
docker compose restart
```

## Troubleshooting

### DNS Issues
```bash
# Verify DNS resolution
dig +short ipmgmt.sigtom.dev
nslookup ipmgmt.sigtom.dev

# If DNS not ready, skip SSL phase and add later
ansible-playbook ... --skip-tags phase3
```

### Container Issues
```bash
# Check container logs
docker compose logs nautobot
docker compose logs postgres
docker compose logs redis

# Restart specific service
docker compose restart nautobot

# Rebuild and restart
docker compose up -d --force-recreate
```

### SSL Certificate Issues
```bash
# Check certificate status
sudo certbot certificates

# Test renewal
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# Re-run SSL phase
ansible-playbook ... --tags phase3
```

### Database Connection Issues
```bash
# Test PostgreSQL connection
docker compose exec postgres psql -U nautobot -d nautobot -c "SELECT version();"

# Check database logs
docker compose logs postgres
```

## Security Notes

1. **Secrets Protection**: The `.env` file has mode 600 (owner read/write only)
2. **SSL/TLS**: HTTPS enforced via Let's Encrypt with auto-renewal
3. **Passwords**: Use strong passwords (20+ characters recommended)
4. **Firewall**: Consider restricting port 80/443 to known IPs
5. **Updates**: Regularly update Docker images and system packages

## Plugins Included

- **nautobot[napalm]** - Network device automation library
- **nautobot-ssot** - Single Source of Truth plugin (for Proxmox/OpenShift sync)
- **nautobot-golden-config** - Network device configuration backups

## Support

For issues or questions:
- Nautobot Documentation: https://docs.nautobot.com
- Docker Hub: https://hub.docker.com/r/networktocode/nautobot
- GitHub Issues: https://github.com/nautobot/nautobot

## License

MIT

## Author

Created for homelab infrastructure automation.
