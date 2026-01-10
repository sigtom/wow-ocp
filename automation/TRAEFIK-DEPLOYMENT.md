# Traefik v3.6 Fully Automated Deployment

## Overview

This playbook deploys a complete Traefik v3.6 reverse proxy setup with:
- ✅ LXC container provisioning
- ✅ Docker + Docker Compose installation
- ✅ Traefik configuration deployment
- ✅ Let's Encrypt SSL certificates (DNS-01 via Cloudflare)
- ✅ Health checks and verification
- ✅ Test container deployment (whoami)
- ✅ End-to-end SSL validation

**Total automation time:** ~5-10 minutes

---

## Prerequisites (Manual Steps Required)

### 1. Create Cloudflare API Token

1. Go to: https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token"
3. Use template: **"Edit zone DNS"**
4. Select **ALL 7 zones**:
   - nixsysadmin.io
   - sigtom.com
   - sigtom.dev
   - sigtom.info
   - sigtom.io
   - sigtomtech.com
   - tecnixsystems.com
5. Click "Continue to summary" → "Create Token"
6. **Save the token securely** (you won't see it again)

### 2. Create DNS Wildcard Records

In Cloudflare DNS, create these A records pointing to **172.16.100.10**:

```
traefik.sigtom.dev       A    172.16.100.10
whoami.sigtom.dev        A    172.16.100.10
*.nixsysadmin.io         A    172.16.100.10
*.sigtom.com             A    172.16.100.10
*.sigtom.dev             A    172.16.100.10
*.sigtom.info            A    172.16.100.10
*.sigtom.io              A    172.16.100.10
*.sigtomtech.com         A    172.16.100.10
*.tecnixsystems.com      A    172.16.100.10
```

**Note:** DNS propagation can take 1-5 minutes. The playbook will wait for certificates.

### 3. Configure pfSense Port Forwarding

Forward external traffic to Traefik:

- **Firewall → NAT → Port Forward**
- Add rules:
  - `WAN:80  → 172.16.100.10:80  (HTTP)`
  - `WAN:443 → 172.16.100.10:443 (HTTPS)`

### 4. Install Ansible Collections

```bash
cd automation
ansible-galaxy collection install -r requirements.yml
```

---

## Deployment

### Step 1: Set Environment Variables

```bash
# Cloudflare API token (REQUIRED)
export CF_DNS_API_TOKEN="your-cloudflare-api-token-here"

# Proxmox API token (should already be set)
export PROXMOX_SRE_BOT_API_TOKEN="your-proxmox-token-here"
```

### Step 2: Run Pre-Flight Checks (Optional but Recommended)

```bash
cd automation
./scripts/traefik-preflight-check.sh
```

This will verify:
- ✅ Cloudflare API token is valid
- ✅ Proxmox API token is set
- ✅ SSH access to Proxmox
- ✅ DNS records are configured (warning if not)
- ✅ Ansible collections installed

### Step 3: Deploy Traefik

```bash
cd automation
ansible-playbook -i inventory/hosts.yaml playbooks/deploy-traefik.yaml
```

**What happens:**
1. **Phase 1: Infrastructure** (~2 min)
   - Create LXC container (CTID 210)
   - Install Ubuntu 24.04
   - Install Docker + Docker Compose
   - Run health checks

2. **Phase 2: Configuration** (~1 min)
   - Copy Traefik Docker Compose
   - Copy Traefik static config
   - Generate BasicAuth credentials
   - Create `.env` file with tokens
   - Set up directories and permissions

3. **Phase 3: Deploy & Verify** (~3 min)
   - Start Traefik container
   - Wait for certificate acquisition (2 min)
   - Verify 7 wildcard certificates issued
   - Check for errors in logs

4. **Phase 4: Testing** (~2 min)
   - Deploy whoami test container
   - Verify HTTPS access
   - Validate SSL certificate

5. **Phase 5: Cleanup**
   - Create post-provision snapshot
   - Generate deployment summary

---

## Post-Deployment Verification

### 1. Check Deployment Summary

```bash
cat automation/.traefik-deployment-summary.txt
```

### 2. Get Dashboard Credentials

```bash
cat automation/.traefik-credentials
```

### 3. Access Dashboard

Open browser: **https://traefik.sigtom.dev**

- Enter credentials from `.traefik-credentials`
- You should see Traefik dashboard
- Check: **Routers** section should show `whoami` router
- Check: **Services** section should show `whoami-test` service

### 4. Test Whoami Service

Open browser: **https://whoami.sigtom.dev**

Should display:
```
Hostname: <container-id>
IP: 172.20.0.x
RemoteAddr: <your-ip>
GET / HTTP/1.1
...
```

**Verify SSL:** Green lock in browser, certificate issued by "Let's Encrypt"

### 5. Check Certificates

```bash
ssh root@172.16.100.10
cd /opt/traefik
cat letsencrypt/acme.json | jq '.cloudflare.Certificates | length'
# Should output: 7
```

### 6. View Traefik Logs

```bash
ssh root@172.16.100.10
cd /opt/traefik
docker compose logs -f traefik
```

Look for:
- ✅ `Server configuration reloaded`
- ✅ Certificate acquisition messages
- ❌ No ACME errors

---

## Troubleshooting

### Certificates Not Generated

**Check logs:**
```bash
ssh root@172.16.100.10
cd /opt/traefik
docker compose logs traefik | grep -i "acme\|error\|certificate"
```

**Common causes:**
- Cloudflare API token invalid → Verify with `curl`
- DNS records not created → Check Cloudflare DNS
- DNS not propagated → Wait 5 minutes, restart Traefik
- Firewall blocking Cloudflare API → Check outbound rules

**Fix and retry:**
```bash
# Fix the issue, then restart Traefik
ssh root@172.16.100.10
cd /opt/traefik
docker compose restart traefik
docker compose logs -f traefik
```

### Dashboard Not Accessible

**Check:**
1. DNS record: `dig +short traefik.sigtom.dev` → Should return 172.16.100.10
2. Port forwarding: Verify pfSense rule for port 443
3. Traefik running: `ssh root@172.16.100.10 'docker ps | grep traefik'`
4. Certificate exists: Check acme.json

### Whoami Test Fails

**Check:**
1. Container running: `ssh root@172.16.100.10 'docker ps | grep whoami'`
2. On correct network: `docker inspect whoami-test | jq '.[0].NetworkSettings.Networks'`
3. Labels correct: `docker inspect whoami-test | jq '.[0].Config.Labels'`
4. DNS record: `dig +short whoami.sigtom.dev`

---

## Next Steps

### 1. Deploy Nautobot Behind Traefik

Nautobot will use the same pattern:
- Connect to `traefik-proxy` network
- Add Traefik labels for routing
- SSL handled automatically by Traefik

### 2. Migrate Existing Services

Move Vaultwarden, DNS2, etc. to use Traefik:
- Add to `traefik-proxy` network
- Add Traefik labels
- Remove nginx/certbot

### 3. Add More Services

Any new Docker app only needs:
```yaml
networks:
  - traefik-proxy

labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.sigtom.dev`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=cloudflare"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

---

## Files Generated

After deployment, these files will exist:

- `.traefik-credentials` - Dashboard login (keep secure!)
- `.traefik-deployment-summary.txt` - Deployment details
- `/tmp/traefik_admin_pass` - Generated password (auto-deleted by system)

**On Traefik LXC (172.16.100.10):**
- `/opt/traefik/docker-compose.yml` - Main compose file
- `/opt/traefik/traefik.yml` - Static config
- `/opt/traefik/.env` - Environment variables (Cloudflare token)
- `/opt/traefik/letsencrypt/acme.json` - SSL certificates
- `/opt/traefik/logs/` - Traefik logs

---

## Security Notes

1. **`.traefik-credentials`** contains plaintext password - keep secure, don't commit to git
2. **Cloudflare API token** is stored in `/opt/traefik/.env` - limit token scope to DNS edit only
3. **Dashboard access** is protected with BasicAuth - consider disabling port 8080 in production
4. **acme.json** contains private keys - permissions set to 600 automatically

---

## Support

If deployment fails:

1. Check pre-flight results: `./scripts/traefik-preflight-check.sh`
2. Review playbook output for specific error
3. Check Traefik logs: `ssh root@172.16.100.10 'cd /opt/traefik && docker compose logs'`
4. Verify DNS propagation: `dig +short traefik.sigtom.dev @1.1.1.1`
5. Test Cloudflare API: `curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer $CF_DNS_API_TOKEN"`

Common errors and solutions documented in playbook output.
