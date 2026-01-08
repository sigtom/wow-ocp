#!/bin/bash
# List all Proxmox VMs and LXC containers with detailed information

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROXMOX_HOST="${PROXMOX_HOST:-172.16.110.101}"
PROXMOX_SSH_KEY="${PROXMOX_SSH_KEY:-$HOME/.ssh/id_pfsense_sre}"

# Check SSH key exists
if [ ! -f "$PROXMOX_SSH_KEY" ]; then
    echo -e "${YELLOW}Error: SSH key not found: $PROXMOX_SSH_KEY${NC}"
    echo "Set PROXMOX_SSH_KEY environment variable or ensure key exists"
    exit 1
fi

# Test connection
if ! ssh -i "$PROXMOX_SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
     root@"$PROXMOX_HOST" "exit" &>/dev/null; then
    echo -e "${YELLOW}Error: Cannot connect to Proxmox host: $PROXMOX_HOST${NC}"
    echo "Check network connectivity and SSH key"
    exit 1
fi

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}                    Proxmox VMs and LXCs on $PROXMOX_HOST${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

###############################################################################
# QEMU/KVM Virtual Machines
###############################################################################
echo -e "${GREEN}==> QEMU/KVM Virtual Machines${NC}"
echo ""

ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'ENDSSH'
qm list
echo ""

# Show more details for each VM
echo "Detailed VM Information:"
echo "------------------------"
for vmid in $(qm list | tail -n +2 | awk '{print $1}'); do
    echo ""
    echo "VMID: $vmid"
    qm config $vmid | grep -E "^(name|cores|memory|net0|ipconfig0|scsihw|bootdisk)" || true
done
ENDSSH

echo ""

###############################################################################
# LXC Containers
###############################################################################
echo -e "${GREEN}==> LXC Containers${NC}"
echo ""

ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'ENDSSH'
pct list
echo ""

# Show more details for each LXC
echo "Detailed LXC Information:"
echo "-------------------------"
for vmid in $(pct list | tail -n +2 | awk '{print $1}'); do
    echo ""
    echo "VMID: $vmid"
    pct config $vmid | grep -E "^(hostname|cores|memory|net0|rootfs|ostype)" || true
done
ENDSSH

echo ""

###############################################################################
# Storage Usage
###############################################################################
echo -e "${GREEN}==> Storage Usage${NC}"
echo ""

ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'ENDSSH'
pvesm status
ENDSSH

echo ""

###############################################################################
# Node Status
###############################################################################
echo -e "${GREEN}==> Node Status${NC}"
echo ""

ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'ENDSSH'
echo "Uptime:"
uptime
echo ""

echo "CPU Info:"
lscpu | grep -E "^(Model name|CPU\(s\)|Thread|Core)"
echo ""

echo "Memory Usage:"
free -h
echo ""

echo "Disk Usage:"
df -h | grep -E "(Filesystem|/$|TSVMDS01)"
ENDSSH

echo ""
echo -e "${BLUE}==============================================================================${NC}"

# Optional: Show network bridges
echo -e "${GREEN}==> Network Bridges${NC}"
echo ""

ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'ENDSSH'
ip -br link show type bridge
ENDSSH

echo ""
echo -e "${BLUE}==============================================================================${NC}"
echo "To manage VMs/LXCs:"
echo "  Start VM:   ssh -i $PROXMOX_SSH_KEY root@$PROXMOX_HOST 'qm start <vmid>'"
echo "  Stop VM:    ssh -i $PROXMOX_SSH_KEY root@$PROXMOX_HOST 'qm stop <vmid>'"
echo "  Start LXC:  ssh -i $PROXMOX_SSH_KEY root@$PROXMOX_HOST 'pct start <vmid>'"
echo "  Stop LXC:   ssh -i $PROXMOX_SSH_KEY root@$PROXMOX_HOST 'pct stop <vmid>'"
echo "  Enter LXC:  ssh -i $PROXMOX_SSH_KEY root@$PROXMOX_HOST 'pct enter <vmid>'"
echo -e "${BLUE}==============================================================================${NC}"
