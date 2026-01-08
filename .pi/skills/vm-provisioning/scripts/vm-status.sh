#!/bin/bash
# Show status of VMs across OpenShift and Proxmox platforms

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROXMOX_HOST="172.16.110.101"
PROXMOX_SSH_KEY="$HOME/.ssh/id_pfsense_sre"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}                    VM/LXC Status Across Platforms${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

###############################################################################
# OpenShift VirtualMachines
###############################################################################
echo -e "${GREEN}==> OpenShift VirtualMachines (KubeVirt)${NC}"
echo ""

if command -v oc &> /dev/null; then
    # Check if logged in
    if ! oc whoami &> /dev/null; then
        echo -e "${YELLOW}Warning: Not logged into OpenShift cluster${NC}"
        echo "Run: oc login"
        echo ""
    else
        echo "Virtual Machines:"
        oc get vm --all-namespaces -o wide 2>/dev/null || echo "No VMs found"
        echo ""
        
        echo "Virtual Machine Instances (Running VMs):"
        oc get vmi --all-namespaces -o wide 2>/dev/null || echo "No VMIs found"
        echo ""
        
        echo "DataVolumes (VM Disks):"
        oc get dv --all-namespaces 2>/dev/null | head -20 || echo "No DataVolumes found"
        echo ""
    fi
else
    echo -e "${YELLOW}Warning: 'oc' command not found. Install OpenShift CLI.${NC}"
    echo ""
fi

###############################################################################
# Proxmox VMs (QEMU)
###############################################################################
echo -e "${GREEN}==> Proxmox VMs (QEMU/KVM)${NC}"
echo ""

if [ -f "$PROXMOX_SSH_KEY" ]; then
    if ssh -i "$PROXMOX_SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
           root@"$PROXMOX_HOST" "exit" &>/dev/null; then
        
        ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" 'qm list' 2>/dev/null
        echo ""
    else
        echo -e "${YELLOW}Warning: Cannot SSH to Proxmox host $PROXMOX_HOST${NC}"
        echo "Check network connectivity and SSH key: $PROXMOX_SSH_KEY"
        echo ""
    fi
else
    echo -e "${YELLOW}Warning: Proxmox SSH key not found: $PROXMOX_SSH_KEY${NC}"
    echo ""
fi

###############################################################################
# Proxmox LXC Containers
###############################################################################
echo -e "${GREEN}==> Proxmox LXC Containers${NC}"
echo ""

if [ -f "$PROXMOX_SSH_KEY" ]; then
    if ssh -i "$PROXMOX_SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
           root@"$PROXMOX_HOST" "exit" &>/dev/null; then
        
        ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" 'pct list' 2>/dev/null
        echo ""
    else
        echo -e "${YELLOW}Warning: Cannot SSH to Proxmox host $PROXMOX_HOST${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}Warning: Proxmox SSH key not found: $PROXMOX_SSH_KEY${NC}"
    echo ""
fi

###############################################################################
# Summary
###############################################################################
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}                              Summary${NC}"
echo -e "${BLUE}==============================================================================${NC}"

# Count OpenShift VMs
if command -v oc &> /dev/null && oc whoami &> /dev/null; then
    OCP_VM_COUNT=$(oc get vm --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
    OCP_VMI_COUNT=$(oc get vmi --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
    echo "OpenShift VMs: $OCP_VM_COUNT defined, $OCP_VMI_COUNT running"
else
    echo "OpenShift VMs: N/A (not logged in or oc not found)"
fi

# Count Proxmox VMs and LXCs
if [ -f "$PROXMOX_SSH_KEY" ]; then
    if ssh -i "$PROXMOX_SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
           root@"$PROXMOX_HOST" "exit" &>/dev/null; then
        
        PROXMOX_VM_COUNT=$(ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no \
            root@"$PROXMOX_HOST" 'qm list' 2>/dev/null | tail -n +2 | wc -l || echo "0")
        PROXMOX_LXC_COUNT=$(ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no \
            root@"$PROXMOX_HOST" 'pct list' 2>/dev/null | tail -n +2 | wc -l || echo "0")
        
        echo "Proxmox VMs: $PROXMOX_VM_COUNT"
        echo "Proxmox LXCs: $PROXMOX_LXC_COUNT"
    else
        echo "Proxmox VMs: N/A (cannot connect)"
        echo "Proxmox LXCs: N/A (cannot connect)"
    fi
else
    echo "Proxmox VMs: N/A (SSH key not found)"
    echo "Proxmox LXCs: N/A (SSH key not found)"
fi

echo ""
echo -e "${BLUE}==============================================================================${NC}"
