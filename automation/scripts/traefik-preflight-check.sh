#!/bin/bash
# ============================================================================
# Traefik Pre-Flight Checks
# ============================================================================
# Run this before deploying Traefik to verify prerequisites
# ============================================================================

set -e

echo "=========================================="
echo "Traefik v3.6 Pre-Flight Checks"
echo "=========================================="
echo ""

ERRORS=0

# Check 1: Cloudflare API Token
echo "✓ Checking Cloudflare API token..."
if [ -z "$CF_DNS_API_TOKEN" ]; then
    echo "  ❌ ERROR: CF_DNS_API_TOKEN not set"
    echo "     Set it with: export CF_DNS_API_TOKEN='your-token-here'"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ CF_DNS_API_TOKEN is set"
    
    # Verify token is valid
    echo "  ✓ Verifying token with Cloudflare API..."
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_DNS_API_TOKEN")
    
    if echo "$response" | grep -q '"success":true'; then
        echo "  ✅ Token is valid"
    else
        echo "  ❌ ERROR: Token validation failed"
        echo "     Response: $response"
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

# Check 2: Ansible Collections
echo "✓ Checking Ansible collections..."
if ansible-galaxy collection list | grep -q "community.docker"; then
    echo "  ✅ community.docker collection installed"
else
    echo "  ⚠️  WARNING: community.docker collection not found"
    echo "     Install with: ansible-galaxy collection install -r requirements.yml"
fi
echo ""

# Check 3: DNS Records (optional check)
echo "✓ Checking DNS records..."
TRAEFIK_IP="172.16.100.10"

for domain in "traefik.sigtom.dev" "whoami.sigtom.dev"; do
    resolved_ip=$(dig +short "$domain" @1.1.1.1 | head -1)
    if [ "$resolved_ip" == "$TRAEFIK_IP" ]; then
        echo "  ✅ $domain → $resolved_ip"
    else
        echo "  ⚠️  WARNING: $domain → $resolved_ip (expected $TRAEFIK_IP)"
        echo "     DNS may not be configured yet - Traefik will wait for it"
    fi
done
echo ""

# Check 4: Proxmox API Token
echo "✓ Checking Proxmox API token..."
if [ -z "$PROXMOX_SRE_BOT_API_TOKEN" ]; then
    echo "  ❌ ERROR: PROXMOX_SRE_BOT_API_TOKEN not set"
    echo "     Set it with: export PROXMOX_SRE_BOT_API_TOKEN='your-token-here'"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✅ PROXMOX_SRE_BOT_API_TOKEN is set"
fi
echo ""

# Check 5: SSH Access to Proxmox
echo "✓ Checking SSH access to Proxmox..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 root@172.16.110.101 "echo 'OK'" 2>/dev/null | grep -q "OK"; then
    echo "  ✅ SSH access to Proxmox confirmed"
else
    echo "  ❌ ERROR: Cannot SSH to Proxmox (172.16.110.101)"
    echo "     Verify SSH keys are configured"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Summary
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo "✅ All checks passed! Ready to deploy."
    echo ""
    echo "Run deployment with:"
    echo "  cd automation"
    echo "  ansible-playbook -i inventory/hosts.yaml playbooks/deploy-traefik.yaml"
    echo "=========================================="
    exit 0
else
    echo "❌ $ERRORS error(s) found. Fix them before deploying."
    echo "=========================================="
    exit 1
fi
