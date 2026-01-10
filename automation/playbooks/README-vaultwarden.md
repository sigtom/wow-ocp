# Vaultwarden Deployment with Caddy TLS

## What This Playbook Does

1. **Creates LXC Container** (VMID 105, 172.16.110.105)
   - Ubuntu 24.04
   - Docker support (`nesting=1`, `keyctl=1`)
   - 2 CPU cores, 2 GB RAM, 20 GB disk

2. **Installs Docker CE**
   - Docker Engine
   - Docker Compose plugin

3. **Deploys Vaultwarden + Caddy**
   - Vaultwarden: Password manager backend
   - Caddy: Automatic HTTPS reverse proxy
   - Let's Encrypt TLS via Cloudflare DNS-01

## Prerequisites

### 1. Environment Variable
```bash
export PROXMOX_SRE_BOT_API_TOKEN="your-token-here"
```

### 2. DNS Record
Ensure this DNS record exists (or create it):
```
vault.sigtomtech.com → 172.16.110.105
```

### 3. Cloudflare Credentials
The playbook automatically uses credentials from your OpenShift cert-manager:
- **Email**: tec.thor@gmail.com
- **API Token**: Retrieved from `cert-manager/cloudflare-api-token` secret

## Deployment

```bash
cd automation
export PROXMOX_SRE_BOT_API_TOKEN="your-token"
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-vaultwarden.yaml
```

**Expected Duration**: 3-5 minutes

## What Gets Created

```
/opt/vaultwarden/
├── docker-compose.yaml       # Service definitions
├── Caddyfile                 # Caddy reverse proxy config
├── .env                      # Cloudflare API token (600 permissions)
├── vaultwarden-data/         # Vaultwarden database and files
├── caddy-data/               # TLS certificates (auto-managed)
└── caddy-config/             # Caddy runtime config
```

## Architecture

```
Internet/LAN
     │
     ▼
vault.sigtomtech.com (172.16.110.105:443)
     │
     ├─► Caddy (port 443)
     │    ├─► Let's Encrypt DNS-01 via Cloudflare
     │    └─► TLS termination
     │
     └─► Vaultwarden (internal port 80)
          └─► SQLite database in vaultwarden-data/
```

## First-Time Access

1. **Wait for initial cert provisioning** (30-60 seconds)
   ```bash
   ssh root@172.16.110.105
   docker logs -f caddy
   # Look for: "certificate obtained successfully"
   ```

2. **Access web UI**: https://vault.sigtomtech.com

3. **Create admin account** (first user becomes admin)

4. **Disable signups**:
   ```bash
   ssh root@172.16.110.105
   cd /opt/vaultwarden
   # Edit docker-compose.yaml: SIGNUPS_ALLOWED=false
   docker compose up -d
   ```

## Security Notes

### Generated Files
- `.env` file contains Cloudflare API token (mode 0600)
- Only root can read this file
- Not committed to git

### Hardening Recommendations
1. Disable signups after initial setup
2. Enable admin panel (set `ADMIN_TOKEN` env var)
3. Set up firewall rules to restrict access
4. Configure backup automation
5. Monitor certificate expiration (Caddy auto-renews)

## DNS-01 Challenge Flow

1. Caddy requests cert from Let's Encrypt
2. Let's Encrypt challenges: "Prove you own vault.sigtomtech.com"
3. Caddy creates TXT record via Cloudflare API: `_acme-challenge.vault.sigtomtech.com`
4. Let's Encrypt validates DNS record
5. Certificate issued and stored in `caddy-data/`
6. Auto-renewal every 60 days

**Why DNS-01?**
- Works with internal IPs (no need to expose ports externally)
- No need for port 80 to be publicly accessible
- Can issue wildcard certs (if needed later)

## Troubleshooting

### Initial cert provisioning takes > 2 minutes
```bash
ssh root@172.16.110.105
docker logs caddy

# Common issues:
# - Cloudflare API token invalid
# - DNS record doesn't exist
# - Cloudflare API rate limit
```

### Can't access via HTTPS
```bash
# Check DNS resolution
nslookup vault.sigtomtech.com

# Check port accessibility
curl -v https://172.16.110.105

# Check Caddy status
ssh root@172.16.110.105
docker ps
docker logs caddy
```

### Certificate expired
```bash
# This should never happen (Caddy auto-renews)
# Force renewal:
ssh root@172.16.110.105
docker exec caddy caddy reload --force
```

## Management

### View Logs
```bash
ssh root@172.16.110.105
docker logs -f vaultwarden  # Application logs
docker logs -f caddy        # TLS/proxy logs
```

### Restart Services
```bash
systemctl restart vaultwarden  # Restarts both containers
# OR
docker restart vaultwarden
docker restart caddy
```

### Update Vaultwarden
```bash
cd /opt/vaultwarden
docker compose pull
docker compose up -d
```

### Backup
```bash
cd /opt/vaultwarden
tar -czf ~/vaultwarden-backup-$(date +%Y%m%d).tar.gz \
  vaultwarden-data/ caddy-data/ docker-compose.yaml Caddyfile .env
```

## Files Modified

- `automation/inventory/hosts.yaml` - Added vaultwarden host
- `automation/playbooks/deploy-vaultwarden.yaml` - Main deployment playbook
- `docs/vaultwarden-operations.md` - Detailed operations guide

## References

- **Vaultwarden**: https://github.com/dani-garcia/vaultwarden
- **Caddy**: https://caddyserver.com/
- **Caddy DNS Cloudflare**: https://github.com/caddy-dns/cloudflare
- **Let's Encrypt**: https://letsencrypt.org/
