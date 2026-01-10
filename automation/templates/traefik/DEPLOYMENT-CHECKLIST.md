# Traefik v3.6 Deployment Checklist

## Pre-Deployment Requirements

### 1. Cloudflare API Token
- [ ] All 7 domains managed in Cloudflare account
- [ ] API token created with **Zone > DNS > Edit** permissions for ALL zones
- [ ] Token tested: `curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer YOUR_TOKEN"`

**Domains to manage:**
- nixsysadmin.io
- sigtom.com
- sigtom.dev
- sigtom.info
- sigtom.io
- sigtomtech.com
- tecnixsystems.com

### 2. DNS Records (Create BEFORE deploying Traefik)
Point all wildcard records to `172.16.100.10`:

```
traefik.sigtom.dev       A    172.16.100.10
*.nixsysadmin.io         A    172.16.100.10
*.sigtom.com             A    172.16.100.10
*.sigtom.dev             A    172.16.100.10
*.sigtom.info            A    172.16.100.10
*.sigtom.io              A    172.16.100.10
*.sigtomtech.com         A    172.16.100.10
*.tecnixsystems.com      A    172.16.100.10
```

### 3. pfSense Port Forwarding
- [ ] WAN:80 → 172.16.100.10:80 (HTTP)
- [ ] WAN:443 → 172.16.100.10:443 (HTTPS)

### 4. Ansible Prerequisites
- [ ] Proxmox API token set in environment: `PROXMOX_SRE_BOT_API_TOKEN`
- [ ] SSH key access to Proxmox host
- [ ] LXC template ubuntu24 (VMID 9024) exists on Proxmox

---

## Deployment Steps

### Step 1: Deploy LXC Container

```bash
cd ~/wow-ocp/automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-traefik.yaml
```

**Expected output:**
- LXC container created (CTID 210)
- Ubuntu 24.04 provisioned
- Docker + Docker Compose installed
- Health checks passed
- Snapshots created

**Time:** ~3-5 minutes

### Step 2: Prepare Traefik Configuration

```bash
# SSH to Traefik container
ssh root@172.16.100.10

# Create directory structure
mkdir -p /opt/traefik/{config,letsencrypt,logs}
cd /opt/traefik
```

### Step 3: Copy Configuration Files

**From your local machine:**

```bash
cd ~/wow-ocp/automation

scp templates/traefik/docker-compose.yml root@172.16.100.10:/opt/traefik/
scp templates/traefik/traefik.yml root@172.16.100.10:/opt/traefik/
scp templates/traefik/.env.example root@172.16.100.10:/opt/traefik/.env
```

### Step 4: Configure Environment Variables

**On Traefik container:**

```bash
nano /opt/traefik/.env
```

**Edit these values:**
- `CF_DNS_API_TOKEN=` → Your Cloudflare API token
- `TRAEFIK_DASHBOARD_AUTH=` → Generate with `htpasswd -nB admin`

**Generate BasicAuth:**
```bash
apt-get install -y apache2-utils
htpasswd -nB admin
# Copy output to .env file (double the $ signs: $$ )
```

### Step 5: Set Permissions

```bash
touch /opt/traefik/letsencrypt/acme.json
chmod 600 /opt/traefik/letsencrypt/acme.json
```

### Step 6: Start Traefik

```bash
cd /opt/traefik
docker compose up -d
```

### Step 7: Monitor Initial Startup

```bash
# Watch logs for certificate generation
docker compose logs -f traefik

# Look for:
# - "Server configuration reloaded"
# - ACME certificate requests for all 7 domains
# - No errors in certificate resolution
```

**Expected behavior:**
- Traefik starts and listens on ports 80, 443, 8080
- Connects to Cloudflare for DNS-01 challenges
- Requests wildcard certificates for all 7 domains
- Stores certificates in `/opt/traefik/letsencrypt/acme.json`

**Time to get all certificates:** ~2-5 minutes

### Step 8: Verify Deployment

**Check container status:**
```bash
docker ps | grep traefik
# Should show: STATUS "Up X minutes (healthy)"
```

**Check certificates:**
```bash
cat /opt/traefik/letsencrypt/acme.json | jq '.cloudflare.Certificates | length'
# Should show: 7 (one per domain)
```

**Access dashboard:**
```
https://traefik.sigtom.dev
```
- Enter BasicAuth credentials
- Should see Traefik dashboard with 0 routers/services (expected)

---

## Testing

### Test 1: Deploy Whoami Container

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

**Deploy:**
```bash
docker compose -f whoami-compose.yml up -d
```

**Test:**
```bash
curl -k https://whoami.sigtom.dev
# Should return: Hostname: <container-id>
```

**Verify in browser:**
- `https://whoami.sigtom.dev` → Should show container info with valid SSL

### Test 2: Check All Domains

Test certificate for each domain:

```bash
echo | openssl s_client -connect whoami.sigtom.dev:443 -servername whoami.sigtom.dev 2>/dev/null | openssl x509 -noout -subject -issuer
```

Create test subdomains for each domain and verify SSL works.

---

## Troubleshooting

### Issue: Certificates not generating

**Check logs:**
```bash
docker compose logs traefik | grep -i "acme\|error\|certificate"
```

**Common causes:**
- Cloudflare API token invalid or missing permissions
- DNS records not propagated
- `acme.json` permissions incorrect (must be 600)
- Firewall blocking outbound connections to Cloudflare API

**Fix:**
1. Verify API token: `curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer $CF_DNS_API_TOKEN"`
2. Check DNS: `dig @1.1.1.1 +short traefik.sigtom.dev` (should return 172.16.100.10)
3. Test outbound: `curl -I https://api.cloudflare.com`

### Issue: Dashboard not accessible

**Check:**
- DNS record for `traefik.sigtom.dev` exists and points to 172.16.100.10
- Port 443 forwarded from pfSense
- BasicAuth credentials formatted correctly (double $$)

**Debug:**
```bash
# Check Traefik is listening
netstat -tlnp | grep :443

# Check logs for dashboard router
docker compose logs traefik | grep dashboard
```

### Issue: Services not appearing in dashboard

**Check:**
- Container has `traefik.enable=true` label
- Container is on `traefik-proxy` network
- Service port is correct

**Debug:**
```bash
# List containers on traefik-proxy network
docker network inspect traefik-proxy | jq '.[0].Containers'

# Check container labels
docker inspect <container-name> | jq '.[0].Config.Labels'
```

---

## Success Criteria

- [ ] Traefik container running and healthy
- [ ] Dashboard accessible at `https://traefik.sigtom.dev`
- [ ] 7 wildcard certificates generated (check acme.json)
- [ ] Whoami test container accessible with valid SSL
- [ ] No errors in Traefik logs

---

## Next Steps After Success

1. **Deploy Nautobot** with Traefik integration
2. **Migrate Vaultwarden** to Traefik
3. **Add other services** as needed

Each new service only needs:
- Docker Compose with Traefik labels
- Connected to `traefik-proxy` network
- DNS record pointing to 172.16.100.10

**No more manual certificate management!** 🎉
