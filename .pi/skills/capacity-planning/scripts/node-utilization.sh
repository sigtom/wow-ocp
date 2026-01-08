#!/bin/bash
# Node Utilization - Per-node resource breakdown

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Thresholds
WARN_THRESHOLD=80
CRIT_THRESHOLD=85

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

main() {
    check_prerequisites
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                  Per-Node Capacity Utilization                     ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get list of nodes
    NODES=$(oc get nodes -o jsonpath='{.items[*].metadata.name}')
    
    HOT_NODES=()
    
    for NODE in $NODES; do
        echo -e "${BOLD}Node: ${BLUE}${NODE}${NC}"
        
        # Get node role
        ROLES=$(oc get node "$NODE" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/.*}' | sed 's/node-role\.kubernetes\.io\///g' | tr '\n' ',' | sed 's/,$//')
        echo "  Roles: ${ROLES:-worker}"
        
        # Get allocatable resources
        TOTAL_CPU=$(oc get node "$NODE" -o jsonpath='{.status.allocatable.cpu}' | sed 's/m$//' | awk '{print $1/1000}')
        TOTAL_MEMORY_KB=$(oc get node "$NODE" -o jsonpath='{.status.allocatable.memory}' | sed 's/Ki$//')
        TOTAL_MEMORY_GB=$(echo "scale=2; $TOTAL_MEMORY_KB / 1024 / 1024" | bc)
        
        # Get requested resources (all pods on this node)
        REQUESTED_CPU=$(oc get pods --all-namespaces --field-selector spec.nodeName="$NODE" -o json | jq '[.items[].spec.containers[]?.resources.requests.cpu // "0" | if type == "string" then (rtrimstr("m") | tonumber / 1000) else . end] | add' 2>/dev/null || echo "0")
        REQUESTED_MEMORY_KB=$(oc get pods --all-namespaces --field-selector spec.nodeName="$NODE" -o json | jq '[.items[].spec.containers[]?.resources.requests.memory // "0" | if type == "string" then (rtrimstr("Ki") | tonumber) else (. * 1024 * 1024) end] | add' 2>/dev/null || echo "0")
        REQUESTED_MEMORY_GB=$(echo "scale=2; $REQUESTED_MEMORY_KB / 1024 / 1024" | bc)
        
        # Calculate percentages
        if (( $(echo "$TOTAL_CPU > 0" | bc -l) )); then
            CPU_PERCENT=$(echo "scale=1; ($REQUESTED_CPU / $TOTAL_CPU) * 100" | bc)
        else
            CPU_PERCENT=0
        fi
        
        if (( $(echo "$TOTAL_MEMORY_GB > 0" | bc -l) )); then
            MEMORY_PERCENT=$(echo "scale=1; ($REQUESTED_MEMORY_GB / $TOTAL_MEMORY_GB) * 100" | bc)
        else
            MEMORY_PERCENT=0
        fi
        
        # Pod count on node
        POD_COUNT=$(oc get pods --all-namespaces --field-selector spec.nodeName="$NODE" --no-headers 2>/dev/null | wc -l)
        POD_CAPACITY=$(oc get node "$NODE" -o jsonpath='{.status.allocatable.pods}')
        POD_PERCENT=$(echo "scale=1; ($POD_COUNT / $POD_CAPACITY) * 100" | bc)
        
        # Check network capability (node labels or annotations)
        NETWORK_TYPE="Unknown"
        NODE_HOSTNAME=$(oc get node "$NODE" -o jsonpath='{.metadata.labels.kubernetes\.io/hostname}')
        case "$NODE_HOSTNAME" in
            *node2*|*node3*)
                NETWORK_TYPE="${GREEN}10G (4-port)${NC}"
                ;;
            *node4*)
                NETWORK_TYPE="${YELLOW}1G (2-port)${NC}"
                ;;
        esac
        
        # Colors based on usage
        CPU_COLOR=$(get_color "$CPU_PERCENT")
        MEMORY_COLOR=$(get_color "$MEMORY_PERCENT")
        POD_COLOR=$(get_color "$POD_PERCENT")
        
        # Print node details
        echo "  Network: $NETWORK_TYPE"
        echo ""
        echo "  CPU:"
        echo "    Allocatable: ${TOTAL_CPU} cores"
        echo "    Requested: ${REQUESTED_CPU} cores"
        echo -e "    Usage: ${CPU_COLOR}${CPU_PERCENT}%${NC}"
        echo ""
        echo "  Memory:"
        echo "    Allocatable: ${TOTAL_MEMORY_GB} GB"
        echo "    Requested: ${REQUESTED_MEMORY_GB} GB"
        echo -e "    Usage: ${MEMORY_COLOR}${MEMORY_PERCENT}%${NC}"
        echo ""
        echo "  Pods:"
        echo "    Running: ${POD_COUNT}"
        echo "    Capacity: ${POD_CAPACITY}"
        echo -e "    Usage: ${POD_COLOR}${POD_PERCENT}%${NC}"
        echo ""
        
        # Check if hot node
        if (( $(echo "$CPU_PERCENT >= $WARN_THRESHOLD" | bc -l) )) || (( $(echo "$MEMORY_PERCENT >= $WARN_THRESHOLD" | bc -l) )); then
            HOT_NODES+=("$NODE")
            echo -e "  ${YELLOW}⚠ HOT NODE - Consider rebalancing workloads${NC}"
            echo ""
        fi
        
        echo "────────────────────────────────────────────────────────────────────────"
        echo ""
    done
    
    # Summary
    echo -e "${BOLD}Summary${NC}"
    if [[ ${#HOT_NODES[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Hot Nodes (>80% CPU or Memory):${NC}"
        for NODE in "${HOT_NODES[@]}"; do
            echo "  - $NODE"
        done
        echo ""
        echo "Recommendations:"
        echo "  1. Review top consumers on hot nodes:"
        echo "     oc adm top pods --all-namespaces --sort-by=cpu | grep <node>"
        echo "  2. Consider pod anti-affinity to spread workloads"
        echo "  3. Use descheduler to rebalance (if installed)"
        echo ""
    else
        echo -e "${GREEN}✓ All nodes balanced (< ${WARN_THRESHOLD}% utilization)${NC}"
        echo ""
    fi
    
    echo -e "${BOLD}Network Considerations${NC}"
    echo "  Node 2 & 3: 10G NICs - Preferred for bandwidth-heavy workloads"
    echo "  Node 4: 1G NIC - Avoid media apps, NFS-heavy workloads"
    echo ""
    echo "To schedule on specific nodes, use nodeSelector:"
    echo "  nodeSelector:"
    echo "    kubernetes.io/hostname: wow-ocp-node2"
    echo ""
}

main "$@"
