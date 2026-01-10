# Traefik v3.6 Deployment Guide

## Managed Domains

This Traefik instance manages SSL certificates for the following domains:
- `*.nixsysadmin.io`
- `*.sigtom.com`
- `*.sigtom.dev`
- `*.sigtom.info`
- `*.sigtom.io`
- `*.sigtomtech.com`
- `*.tecnixsystems.com`

## Quick Start

### 1. Deploy the LXC Container

```bash
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-traefik.yaml
```

### 2. SSH to the Traefik Container

```bash
ssh root@172.16.100.10
```

### 3. Create Traefik Directory Structure

```bash
mkdir -p /opt/traefik/{config,letsencrypt,logs}
cd /opt/traefik
```

### 4. Copy Configuration Files

Transfer the following files from `automation/templates/traefik/` to `/opt/traefik/`:
- `docker-compose.yml`
- `traefik.yml`
- `.env.example`

```bash
# On your local machine (from automation/ directory)
scp templates/traefik/docker-compose.yml root@172.16.100.10:/opt/traefik/
scp templates/traefik/traefik.yml root@172.16.100.10:/opt/traefik/
scp templates/traefik/.env.example root@172.16.100.10:/opt/traefik/.env
```

### 5. Configure Environment Variables

Edit `/opt/traefik/.env`:

```bash
nano /opt/traefik/.env
```

**Required:**
- `CF_DNS_API_TOKEN` - Cloudflare API token with DNS edit permissions (for ALL 7 domains)
- `TRAEFIK_DASHBOARD_AUTH` - BasicAuth credentials for dashboard

**Generate BasicAuth password:**
```bash
# Install htpasswd if not available
apt-get install -y apache2-utils

# Generate password (replace 'admin' and 'your-password')
htpasswd -nB admin
# Copy the output to TRAEFIK_DASHBOARD_AUTH
```

### 6. Set Proper Permissions

```bash
touch /opt/traefik/letsencrypt/acme.json
chmod 600 /opt/traefik/letsencrypt/acme.json
```

### 7. Start Traefik

```bash
cd /opt/traefik
docker compose up -d
```

### 8. Verify Deployment

```bash
# Check logs
docker compose logs -f traefik

# Verify Traefik is running
docker ps | grep traefik
```

### 9. Test Dashboard Access

Open browser: `https://traefik.sigtom.dev`

## DNS Configuration

### Cloudflare DNS Records

Create the following A records pointing to `172.16.100.10` (or your Traefik LXC IP):

```
# Dashboard
traefik.sigtom.dev       → 172.16.100.10

# Wildcard records for all domains
*.nixsysadmin.io         → 172.16.100.10
*.sigtom.com             → 172.16.100.10
*.sigtom.dev             → 172.16.100.10
*.sigtom.info            → 172.16.100.10
*.sigtom.io              → 172.16.100.10
*.sigtomtech.com         → 172.16.100.10
*.tecnixsystems.com      → 172.16.100.10
```

**IMPORTANT:** All 7 domains must be managed by the SAME Cloudflare account and the API token must have DNS edit permissions for ALL zones.

## pfSense Port Forwarding

Forward external ports 80 and 443 to Traefik:

```
WAN:80  → 172.16.100.10:80  (HTTP)
WAN:443 → 172.16.100.10:443 (HTTPS)
```

## Adding Services Behind Traefik

### Example: Whoami Test Service

Create `/opt/traefik/whoami-compose.yml`:

```yaml
services:
  whoami:
    image: traefik/whoami:latest
    container_name: whoami
    networks:
      - traefik-proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.rule=Host(`whoami.sigtom.dev`)"
      - "traefik.http.routers.whoami.entrypoints=websecure"
      - "traefik.http.routers.whoami.tls.certresolver=cloudflare"
      - "traefik.http.services.whoami.loadbalancer.server.port=80"

networks:
  traefik-proxy:
    external: true
```

Deploy:
```bash
docker compose -f whoami-compose.yml up -d
```

Test: `https://whoami.sigtom.dev`

### Example: Nautobot Integration

When you deploy Nautobot later, add these labels to the Nautobot container:

```yaml
services:
  nautobot:
    image: networktocode/nautobot:latest
    networks:
      - traefik-proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nautobot.rule=Host(`ipmgmt.sigtom.dev`)"
      - "traefik.http.routers.nautobot.entrypoints=websecure"
      - "traefik.http.routers.nautobot.tls.certresolver=cloudflare"
      - "traefik.http.services.nautobot.loadbalancer.server.port=8000"

networks:
  traefik-proxy:
    external: true
```

## Troubleshooting

### Check Traefik Logs
```bash
docker compose logs -f traefik
```

### Verify Certificate Status
```bash
cat /opt/traefik/letsencrypt/acme.json | jq
```

### Test Docker Network
```bash
docker network ls | grep traefik-proxy
docker network inspect traefik-proxy
```

### Common Issues

**Issue:** Certificates not generating for some domains
- Verify ALL 7 domains are in the same Cloudflare account
- Ensure Cloudflare API token has permissions for ALL zones
- Check `acme.json` permissions (must be 600)
- Review logs for ACME challenge errors: `docker compose logs traefik | grep -i acme`

**Issue:** Dashboard not accessible
- Verify DNS record for `traefik.sigtom.dev` points to 172.16.100.10
- Check BasicAuth credentials are correctly formatted (double $$ in docker-compose)
- Ensure port 443 is forwarded from pfSense

**Issue:** Services not appearing
- Verify container is on `traefik-proxy` network
- Check `traefik.enable=true` label is set
- Ensure correct service port is specified
- Check container logs: `docker compose logs <service-name>`

**Issue:** DNS-01 challenge failing
- Verify Cloudflare API token is valid
- Test token: `curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer YOUR_TOKEN"`
- Check Traefik can reach Cloudflare DNS servers (1.1.1.1, 8.8.8.8)

## Next Steps

Once Traefik is working:
1. Test with whoami container
2. Verify certificates are issued for all domains
3. Deploy Nautobot with Traefik labels
4. Add more services as needed

## Security Recommendations

1. **Disable Dashboard in Production**: Remove port 8080 from docker-compose.yml
2. **Use Strong BasicAuth**: Generate strong passwords with htpasswd
3. **Limit API Token Permissions**: Use Cloudflare API tokens with minimal scope
4. **Enable Rate Limiting**: Add rate limit middleware for production
5. **Monitor Logs**: Set up log aggregation (e.g., Grafana Loki)
