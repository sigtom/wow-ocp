#!/bin/bash
# Proxmox Capacity - VM/LXC resource allocation on wow-prox1

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

PROXMOX_HOST="${PROXMOX_HOST:-172.16.110.101}"
PROXMOX_SSH_KEY="${PROXMOX_SSH_KEY:-$HOME/.ssh/id_pfsense_sre}"
WARN_THRESHOLD=80
CRIT_THRESHOLD=90

# Hardware specs
TOTAL_CORES=32
TOTAL_THREADS=64
TOTAL_MEMORY=256

check_ssh() {
    if [ ! -f "$PROXMOX_SSH_KEY" ]; then
        echo -e "${RED}ERROR: SSH key not found: $PROXMOX_SSH_KEY${NC}" >&2; exit 1
    fi
    if ! ssh -i "$PROXMOX_SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "exit" &>/dev/null; then
        echo -e "${RED}ERROR: Cannot connect to Proxmox: $PROXMOX_HOST${NC}" >&2; exit 1
    fi
}

get_color() {
    local usage=$1
    if (( $(echo "$usage >= $CRIT_THRESHOLD" | bc -l) )); then echo "$RED"
    elif (( $(echo "$usage >= $WARN_THRESHOLD" | bc -l) )); then echo "$YELLOW"
    else echo "$GREEN"; fi
}

main() {
    check_ssh
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                  Proxmox Capacity Report (wow-prox1)               ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BOLD}Hardware Specifications${NC}"
    echo "  Model: 2x Intel Xeon E5-2683 v4"
    echo "  Cores: ${TOTAL_CORES} (${TOTAL_THREADS} threads)"
    echo "  Memory: ${TOTAL_MEMORY} GB"
    echo ""
    
    # Get VM allocations
    echo -e "${BOLD}Virtual Machine Allocations${NC}"
    ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'ENDSSH'
VMS=$(qm list | tail -n +2)
TOTAL_VM_CORES=0
TOTAL_VM_MEMORY=0

echo "$VMS" | while read vmid name status mem_pct cpu_pct pid uptime mem_mb; do
    # Get VM config
    CORES=$(qm config $vmid | grep "^cores:" | awk '{print $2}')
    MEMORY=$(qm config $vmid | grep "^memory:" | awk '{print $2}')
    
    printf "  %-15s (VMID: %-4s) - CPU: %-2s cores, Memory: %-5s MB, Status: %s\n" \
        "$name" "$vmid" "$CORES" "$MEMORY" "$status"
    
    TOTAL_VM_CORES=$((TOTAL_VM_CORES + CORES))
    TOTAL_VM_MEMORY=$((TOTAL_VM_MEMORY + MEMORY))
done

# Summary
echo ""
echo "VM Summary:"
echo "  Total Allocated Cores: ${TOTAL_VM_CORES}"
echo "  Total Allocated Memory: ${TOTAL_VM_MEMORY} MB"
ENDSSH
    echo ""
    
    # Get LXC allocations
    echo -e "${BOLD}LXC Container Allocations${NC}"
    ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'ENDSSH'
LXCS=$(pct list | tail -n +2)
TOTAL_LXC_CORES=0
TOTAL_LXC_MEMORY=0

if [[ -n "$LXCS" ]]; then
    echo "$LXCS" | while read vmid status lock name; do
        # Get LXC config
        CORES=$(pct config $vmid | grep "^cores:" | awk '{print $2}')
        MEMORY=$(pct config $vmid | grep "^memory:" | awk '{print $2}')
        
        printf "  %-15s (VMID: %-4s) - CPU: %-2s cores, Memory: %-5s MB, Status: %s\n" \
            "$name" "$vmid" "$CORES" "$MEMORY" "$status"
        
        TOTAL_LXC_CORES=$((TOTAL_LXC_CORES + CORES))
        TOTAL_LXC_MEMORY=$((TOTAL_LXC_MEMORY + MEMORY))
    done
    
    echo ""
    echo "LXC Summary:"
    echo "  Total Allocated Cores: ${TOTAL_LXC_CORES}"
    echo "  Total Allocated Memory: ${TOTAL_LXC_MEMORY} MB"
else
    echo "  No LXC containers found"
fi
ENDSSH
    echo ""
    
    # Get totals and calculate percentages
    ALLOCATED_DATA=$(ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" << 'ENDSSH'
VM_CORES=$(qm list | tail -n +2 | awk '{sum=0; for(i=1; i<=NF; i++) if($i ~ /^[0-9]+$/) sum+=$i} END {print sum}' || echo 0)
VM_CORES=0
for vmid in $(qm list | tail -n +2 | awk '{print $1}'); do
    CORES=$(qm config $vmid | grep "^cores:" | awk '{print $2}')
    VM_CORES=$((VM_CORES + CORES))
done

VM_MEMORY=0
for vmid in $(qm list | tail -n +2 | awk '{print $1}'); do
    MEMORY=$(qm config $vmid | grep "^memory:" | awk '{print $2}')
    VM_MEMORY=$((VM_MEMORY + MEMORY))
done

LXC_CORES=0
for vmid in $(pct list | tail -n +2 | awk '{print $1}'); do
    CORES=$(pct config $vmid 2>/dev/null | grep "^cores:" | awk '{print $2}')
    [[ -n "$CORES" ]] && LXC_CORES=$((LXC_CORES + CORES))
done

LXC_MEMORY=0
for vmid in $(pct list | tail -n +2 | awk '{print $1}'); do
    MEMORY=$(pct config $vmid 2>/dev/null | grep "^memory:" | awk '{print $2}')
    [[ -n "$MEMORY" ]] && LXC_MEMORY=$((LXC_MEMORY + MEMORY))
done

TOTAL_CORES=$((VM_CORES + LXC_CORES))
TOTAL_MEMORY=$((VM_MEMORY + LXC_MEMORY))

echo "$TOTAL_CORES $TOTAL_MEMORY"
ENDSSH
    )
    
    read ALLOCATED_CORES ALLOCATED_MEMORY_MB <<< "$ALLOCATED_DATA"
    ALLOCATED_MEMORY_GB=$(echo "scale=2; $ALLOCATED_MEMORY_MB / 1024" | bc)
    AVAILABLE_CORES=$((TOTAL_CORES - ALLOCATED_CORES))
    AVAILABLE_MEMORY_GB=$(echo "scale=2; $TOTAL_MEMORY - $ALLOCATED_MEMORY_GB" | bc)
    
    CPU_PERCENT=$(echo "scale=1; ($ALLOCATED_CORES / $TOTAL_CORES) * 100" | bc)
    MEM_PERCENT=$(echo "scale=1; ($ALLOCATED_MEMORY_GB / $TOTAL_MEMORY) * 100" | bc)
    
    CPU_COLOR=$(get_color "$CPU_PERCENT")
    MEM_COLOR=$(get_color "$MEM_PERCENT")
    
    echo -e "${BOLD}Capacity Summary${NC}"
    echo "  CPU:"
    echo "    Total: ${TOTAL_CORES} cores"
    echo "    Allocated: ${ALLOCATED_CORES} cores"
    echo "    Available: ${AVAILABLE_CORES} cores"
    echo -e "    Utilization: ${CPU_COLOR}${CPU_PERCENT}%${NC}"
    echo ""
    echo "  Memory:"
    echo "    Total: ${TOTAL_MEMORY} GB"
    echo "    Allocated: ${ALLOCATED_MEMORY_GB} GB"
    echo "    Available: ${AVAILABLE_MEMORY_GB} GB"
    echo -e "    Utilization: ${MEM_COLOR}${MEM_PERCENT}%${NC}"
    echo ""
    
    # Storage
    echo -e "${BOLD}Storage Usage${NC}"
    ssh -i "$PROXMOX_SSH_KEY" -o StrictHostKeyChecking=no root@"$PROXMOX_HOST" "pvesm status" 2>/dev/null
    echo ""
    
    # Recommendations
    echo -e "${BOLD}Capacity Status${NC}"
    if (( $(echo "$CPU_PERCENT >= $CRIT_THRESHOLD" | bc -l) )) || (( $(echo "$MEM_PERCENT >= $CRIT_THRESHOLD" | bc -l) )); then
        echo -e "  ${RED}⚠ CRITICAL: >90% utilization${NC}"
        echo "    - No new VMs/LXCs without removal"
        echo "    - Consider migrating to OpenShift"
    elif (( $(echo "$CPU_PERCENT >= $WARN_THRESHOLD" | bc -l) )) || (( $(echo "$MEM_PERCENT >= $WARN_THRESHOLD" | bc -l) )); then
        echo -e "  ${YELLOW}⚠ WARNING: >80% utilization${NC}"
        echo "    - Defer non-critical workloads"
        echo "    - Review VM/LXC sizing"
    else
        echo -e "  ${GREEN}✓ HEALTHY: Capacity available${NC}"
    fi
    echo ""
    
    echo -e "${BOLD}Next Steps${NC}"
    echo "  List VMs/LXCs: ~/.pi/skills/vm-provisioning/scripts/proxmox-list.sh"
    echo "  Create VM: ~/.pi/skills/vm-provisioning/scripts/create-vm.sh proxmox-vm <name> ubuntu <cpu> <ram> <disk>"
    echo ""
}

main "$@"
