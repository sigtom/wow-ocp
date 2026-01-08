#!/bin/bash
# Storage Capacity - NFS and LVM usage across cluster

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

WARN_THRESHOLD=80
CRIT_THRESHOLD=90
TRUENAS_IP="172.16.160.100"

SHOW_UNUSED=false
if [[ "${1:-}" == "--show-unused" ]]; then
    SHOW_UNUSED=true
fi

check_prerequisites() {
    if ! command -v oc &> /dev/null; then
        echo -e "${RED}ERROR: 'oc' command not found${NC}" >&2
        exit 1
    fi
    if ! oc whoami &> /dev/null; then
        echo -e "${RED}ERROR: Not logged into OpenShift cluster${NC}" >&2
        exit 1
    fi
}

get_color() {
    local usage=$1
    if (( $(echo "$usage >= $CRIT_THRESHOLD" | bc -l) )); then
        echo "$RED"
    elif (( $(echo "$usage >= $WARN_THRESHOLD" | bc -l) )); then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

bytes_to_gb() {
    local bytes=$1
    echo "scale=2; $bytes / 1024 / 1024 / 1024" | bc
}

main() {
    check_prerequisites
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                     Storage Capacity Report                        ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # TrueNAS ZFS Pool
    echo -e "${BOLD}TrueNAS ZFS Pool (wow-ts10TB)${NC}"
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${TRUENAS_IP} "exit" &>/dev/null; then
        POOL_INFO=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -o name,used,avail -Hp wow-ts10TB" 2>/dev/null | head -1)
        if [[ -n "$POOL_INFO" ]]; then
            read -r NAME USED AVAIL <<< "$POOL_INFO"
            TOTAL=$((USED + AVAIL))
            PERCENT=$(echo "scale=1; ($USED * 100) / $TOTAL" | bc)
            
            USED_GB=$(bytes_to_gb "$USED")
            AVAIL_GB=$(bytes_to_gb "$AVAIL")
            TOTAL_GB=$(bytes_to_gb "$TOTAL")
            
            COLOR=$(get_color "$PERCENT")
            echo "  Total: ${TOTAL_GB} GB"
            echo "  Used: ${USED_GB} GB"
            echo "  Available: ${AVAIL_GB} GB"
            echo -e "  Usage: ${COLOR}${PERCENT}%${NC}"
        else
            echo -e "  ${YELLOW}Could not retrieve pool info${NC}"
        fi
    else
        echo -e "  ${YELLOW}Cannot connect to TrueNAS (${TRUENAS_IP})${NC}"
    fi
    echo ""
    
    # PVC Summary by StorageClass
    echo -e "${BOLD}PVC Summary by StorageClass${NC}"
    
    STORAGE_CLASSES="truenas-nfs truenas-nfs-dynamic lvms-vg1"
    
    for SC in $STORAGE_CLASSES; do
        echo "  StorageClass: ${BLUE}${SC}${NC}"
        
        PVC_COUNT=$(oc get pvc --all-namespaces -o json | jq "[.items[] | select(.spec.storageClassName == \"$SC\")] | length" 2>/dev/null || echo "0")
        
        if [[ "$PVC_COUNT" -gt 0 ]]; then
            TOTAL_SIZE=$(oc get pvc --all-namespaces -o json | jq "[.items[] | select(.spec.storageClassName == \"$SC\") | .spec.resources.requests.storage | rtrimstr(\"Gi\") | tonumber] | add" 2>/dev/null || echo "0")
            
            echo "    PVCs: ${PVC_COUNT}"
            echo "    Total Size: ${TOTAL_SIZE} GB"
            
            # Show top 5 PVCs
            echo "    Largest PVCs:"
            oc get pvc --all-namespaces -o json | jq -r ".items[] | select(.spec.storageClassName == \"$SC\") | \"\(.metadata.namespace)/\(.metadata.name): \(.spec.resources.requests.storage)\"" 2>/dev/null | sort -t: -k2 -hr | head -5 | while read line; do
                echo "      - $line"
            done
        else
            echo "    No PVCs found"
        fi
        echo ""
    done
    
    # Prometheus special check
    echo -e "${BOLD}Prometheus Storage (LVMS)${NC}"
    PROM_PVC=$(oc get pvc -n openshift-monitoring prometheus-k8s-db-prometheus-k8s-0 --no-headers 2>/dev/null | awk '{print $4}')
    if [[ -n "$PROM_PVC" ]]; then
        echo "  PVC: prometheus-k8s-db-prometheus-k8s-0"
        echo "  Size: $PROM_PVC"
        echo "  Note: Expanded to 100GB in Dec 2025"
        echo "  Monitor: Check usage monthly to avoid exhaustion"
    else
        echo "  PVC not found (check namespace)"
    fi
    echo ""
    
    # Show unused PVCs if requested
    if [[ "$SHOW_UNUSED" == "true" ]]; then
        echo -e "${BOLD}Unused PVCs (Bound but not mounted)${NC}"
        
        # Get all PVCs
        ALL_PVCS=$(oc get pvc --all-namespaces -o json 2>/dev/null)
        
        # Get all mounted volumes from pods
        MOUNTED_PVCS=$(oc get pods --all-namespaces -o json 2>/dev/null | jq -r '.items[].spec.volumes[]?.persistentVolumeClaim.claimName // empty' | sort -u)
        
        UNUSED_COUNT=0
        echo "$ALL_PVCS" | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.resources.requests.storage)"' | while read NS NAME SIZE; do
            if ! echo "$MOUNTED_PVCS" | grep -q "^${NAME}$"; then
                echo "  - ${NS}/${NAME} (${SIZE})"
                ((UNUSED_COUNT++))
            fi
        done
        
        if [[ $UNUSED_COUNT -eq 0 ]]; then
            echo "  None found"
        fi
        echo ""
    fi
    
    # Recommendations
    echo -e "${BOLD}Storage Health Summary${NC}"
    
    # Re-check TrueNAS status for recommendations
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${TRUENAS_IP} "exit" &>/dev/null; then
        POOL_INFO=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -o name,used,avail -Hp wow-ts10TB" 2>/dev/null | head -1)
        if [[ -n "$POOL_INFO" ]]; then
            read -r NAME USED AVAIL <<< "$POOL_INFO"
            TOTAL=$((USED + AVAIL))
            PERCENT=$(echo "scale=1; ($USED * 100) / $TOTAL" | bc)
            
            if (( $(echo "$PERCENT >= $CRIT_THRESHOLD" | bc -l) )); then
                echo -e "  ${RED}⚠ CRITICAL: TrueNAS pool >90% used${NC}"
                echo "    Actions:"
                echo "      1. Delete unused PVCs immediately"
                echo "      2. Clean up old snapshots"
                echo "      3. Expand pool (add drives)"
            elif (( $(echo "$PERCENT >= $WARN_THRESHOLD" | bc -l) )); then
                echo -e "  ${YELLOW}⚠ WARNING: TrueNAS pool >80% used${NC}"
                echo "    Actions:"
                echo "      1. Plan cleanup or expansion"
                echo "      2. Review large PVCs: oc get pvc --all-namespaces --sort-by=.spec.resources.requests.storage"
            else
                echo -e "  ${GREEN}✓ TrueNAS pool healthy (<80% used)${NC}"
            fi
        fi
    fi
    echo ""
    
    echo -e "${BOLD}Next Steps${NC}"
    echo "  Show unused PVCs: $0 --show-unused"
    echo "  TrueNAS detailed: ~/.pi/skills/truenas-ops/scripts/check-truenas-capacity.sh --detailed"
    echo "  Top consumers: ./top-consumers.sh"
    echo ""
}

main "$@"
