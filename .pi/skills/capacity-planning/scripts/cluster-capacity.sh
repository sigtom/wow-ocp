#!/bin/bash
# Cluster Capacity Check - Show overall CPU, memory, and pod utilization

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Thresholds
WARN_THRESHOLD=85
CRIT_THRESHOLD=90

ALERT_MODE=false
if [[ "${1:-}" == "--alert" ]]; then
    ALERT_MODE=true
fi

print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}               OpenShift Cluster Capacity Report                    ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_prerequisites() {
    if ! command -v oc &> /dev/null; then
        echo -e "${RED}ERROR: 'oc' command not found${NC}" >&2
        exit 1
    fi
    
    if ! oc whoami &> /dev/null; then
        echo -e "${RED}ERROR: Not logged into OpenShift cluster${NC}" >&2
        echo "Run: oc login" >&2
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

get_status() {
    local usage=$1
    if (( $(echo "$usage >= $CRIT_THRESHOLD" | bc -l) )); then
        echo "CRITICAL"
    elif (( $(echo "$usage >= $WARN_THRESHOLD" | bc -l) )); then
        echo "WARNING"
    else
        echo "OK"
    fi
}

main() {
    check_prerequisites
    
    if [[ "$ALERT_MODE" == "false" ]]; then
        print_header
    fi
    
    # Get node information
    NODE_COUNT=$(oc get nodes --no-headers | wc -l)
    
    # Get allocatable resources (total available for pods)
    TOTAL_CPU=$(oc get nodes -o json | jq '[.items[].status.allocatable.cpu | rtrimstr("m") | tonumber] | add / 1000' 2>/dev/null || echo "0")
    TOTAL_MEMORY_KB=$(oc get nodes -o json | jq '[.items[].status.allocatable.memory | rtrimstr("Ki") | tonumber] | add' 2>/dev/null || echo "0")
    TOTAL_MEMORY_GB=$(echo "scale=2; $TOTAL_MEMORY_KB / 1024 / 1024" | bc)
    
    # Get requested resources (by pods)
    REQUESTED_CPU=$(oc get pods --all-namespaces -o json | jq '[.items[].spec.containers[]?.resources.requests.cpu // "0" | if type == "string" then (rtrimstr("m") | tonumber / 1000) else . end] | add' 2>/dev/null || echo "0")
    REQUESTED_MEMORY_KB=$(oc get pods --all-namespaces -o json | jq '[.items[].spec.containers[]?.resources.requests.memory // "0" | if type == "string" then (rtrimstr("Ki") | tonumber) else (. * 1024 * 1024) end] | add' 2>/dev/null || echo "0")
    REQUESTED_MEMORY_GB=$(echo "scale=2; $REQUESTED_MEMORY_KB / 1024 / 1024" | bc)
    
    # Calculate available
    AVAILABLE_CPU=$(echo "scale=2; $TOTAL_CPU - $REQUESTED_CPU" | bc)
    AVAILABLE_MEMORY_GB=$(echo "scale=2; $TOTAL_MEMORY_GB - $REQUESTED_MEMORY_GB" | bc)
    
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
    
    # Get pod counts
    TOTAL_PODS=$(oc get pods --all-namespaces --no-headers 2>/dev/null | wc -l)
    RUNNING_PODS=$(oc get pods --all-namespaces --no-headers --field-selector=status.phase=Running 2>/dev/null | wc -l)
    POD_CAPACITY=$(oc get nodes -o json | jq '[.items[].status.allocatable.pods | tonumber] | add' 2>/dev/null || echo "0")
    
    if (( $POD_CAPACITY > 0 )); then
        POD_PERCENT=$(echo "scale=1; ($RUNNING_PODS / $POD_CAPACITY) * 100" | bc)
    else
        POD_PERCENT=0
    fi
    
    # Determine colors and status
    CPU_COLOR=$(get_color "$CPU_PERCENT")
    CPU_STATUS=$(get_status "$CPU_PERCENT")
    MEMORY_COLOR=$(get_color "$MEMORY_PERCENT")
    MEMORY_STATUS=$(get_status "$MEMORY_PERCENT")
    POD_COLOR=$(get_color "$POD_PERCENT")
    POD_STATUS=$(get_status "$POD_PERCENT")
    
    # Determine overall status
    OVERALL_STATUS="OK"
    if [[ "$CPU_STATUS" == "CRITICAL" ]] || [[ "$MEMORY_STATUS" == "CRITICAL" ]]; then
        OVERALL_STATUS="CRITICAL"
        OVERALL_COLOR="$RED"
    elif [[ "$CPU_STATUS" == "WARNING" ]] || [[ "$MEMORY_STATUS" == "WARNING" ]]; then
        OVERALL_STATUS="WARNING"
        OVERALL_COLOR="$YELLOW"
    else
        OVERALL_COLOR="$GREEN"
    fi
    
    # Print report
    if [[ "$ALERT_MODE" == "true" ]]; then
        # Alert mode: only print warnings/critical
        echo "CLUSTER CAPACITY ALERT - $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        ALERT_COUNT=0
        
        if [[ "$CPU_STATUS" != "OK" ]]; then
            echo "[${CPU_STATUS}] CPU utilization: ${CPU_PERCENT}% (>${WARN_THRESHOLD}%)"
            echo "  Current: ${REQUESTED_CPU}/${TOTAL_CPU} cores"
            if [[ "$CPU_STATUS" == "CRITICAL" ]]; then
                echo "  Action: No new deployments until <90%"
            else
                echo "  Action: Defer non-critical workloads"
            fi
            echo ""
            ((ALERT_COUNT++))
        fi
        
        if [[ "$MEMORY_STATUS" != "OK" ]]; then
            echo "[${MEMORY_STATUS}] Memory utilization: ${MEMORY_PERCENT}% (>${WARN_THRESHOLD}%)"
            echo "  Current: ${REQUESTED_MEMORY_GB}/${TOTAL_MEMORY_GB} GB"
            if [[ "$MEMORY_STATUS" == "CRITICAL" ]]; then
                echo "  Action: No new deployments without removal"
            else
                echo "  Action: Defer non-critical workloads"
            fi
            echo ""
            ((ALERT_COUNT++))
        fi
        
        if [[ "$POD_STATUS" != "OK" ]]; then
            echo "[${POD_STATUS}] Pod count: ${POD_PERCENT}% (>${WARN_THRESHOLD}%)"
            echo "  Current: ${RUNNING_PODS}/${POD_CAPACITY} pods"
            echo "  Action: Review pod scheduling limits"
            echo ""
            ((ALERT_COUNT++))
        fi
        
        if [[ $ALERT_COUNT -eq 0 ]]; then
            echo "[OK] All capacity metrics within thresholds"
            echo ""
        fi
        
        exit $([ $ALERT_COUNT -gt 0 ] && echo 1 || echo 0)
    else
        # Normal mode: full report
        echo -e "${BOLD}Cluster Overview${NC}"
        echo "  Nodes: $NODE_COUNT"
        echo "  Overall Status: ${OVERALL_COLOR}${OVERALL_STATUS}${NC}"
        echo ""
        
        echo -e "${BOLD}CPU Resources${NC}"
        echo "  Total Allocatable: ${TOTAL_CPU} cores"
        echo "  Requested: ${REQUESTED_CPU} cores"
        echo "  Available: ${AVAILABLE_CPU} cores"
        echo -e "  Utilization: ${CPU_COLOR}${CPU_PERCENT}%${NC} [${CPU_STATUS}]"
        echo ""
        
        echo -e "${BOLD}Memory Resources${NC}"
        echo "  Total Allocatable: ${TOTAL_MEMORY_GB} GB"
        echo "  Requested: ${REQUESTED_MEMORY_GB} GB"
        echo "  Available: ${AVAILABLE_MEMORY_GB} GB"
        echo -e "  Utilization: ${MEMORY_COLOR}${MEMORY_PERCENT}%${NC} [${MEMORY_STATUS}]"
        echo ""
        
        echo -e "${BOLD}Pod Resources${NC}"
        echo "  Total Pods: $TOTAL_PODS"
        echo "  Running Pods: $RUNNING_PODS"
        echo "  Pod Capacity: $POD_CAPACITY"
        echo -e "  Utilization: ${POD_COLOR}${POD_PERCENT}%${NC} [${POD_STATUS}]"
        echo ""
        
        # Capacity bar (ASCII art)
        echo -e "${BOLD}Capacity Visualization${NC}"
        draw_bar() {
            local percent=$1
            local label=$2
            local color=$3
            local bar_width=50
            local filled=$(echo "scale=0; ($percent * $bar_width) / 100" | bc)
            local empty=$((bar_width - filled))
            
            printf "  %-8s [" "$label"
            printf "${color}"
            printf "%${filled}s" | tr ' ' '█'
            printf "${NC}"
            printf "%${empty}s" | tr ' ' '░'
            printf "] %5.1f%%\n" "$percent"
        }
        
        draw_bar "$CPU_PERCENT" "CPU" "$CPU_COLOR"
        draw_bar "$MEMORY_PERCENT" "Memory" "$MEMORY_COLOR"
        draw_bar "$POD_PERCENT" "Pods" "$POD_COLOR"
        echo ""
        
        # Thresholds
        echo -e "${BOLD}Capacity Thresholds${NC}"
        echo "  Warning: ${YELLOW}${WARN_THRESHOLD}%${NC}"
        echo "  Critical: ${RED}${CRIT_THRESHOLD}%${NC}"
        echo ""
        
        # Recommendations
        if [[ "$OVERALL_STATUS" == "CRITICAL" ]]; then
            echo -e "${RED}${BOLD}⚠ CRITICAL CAPACITY${NC}"
            echo "  Actions required:"
            echo "    1. Block all new deployments"
            echo "    2. Scale down non-critical workloads"
            echo "    3. Remove unused resources"
            echo "    4. Consider cluster expansion"
            echo ""
        elif [[ "$OVERALL_STATUS" == "WARNING" ]]; then
            echo -e "${YELLOW}${BOLD}⚠ WARNING - CAPACITY PRESSURE${NC}"
            echo "  Recommendations:"
            echo "    1. Defer non-critical deployments"
            echo "    2. Review top consumers: ./scripts/top-consumers.sh"
            echo "    3. Plan capacity cleanup or expansion"
            echo ""
        else
            echo -e "${GREEN}${BOLD}✓ HEALTHY CAPACITY${NC}"
            echo "  Cluster has adequate headroom for new workloads"
            echo ""
        fi
        
        # Next steps
        echo -e "${BOLD}Next Steps${NC}"
        echo "  Per-node breakdown: ./scripts/node-utilization.sh"
        echo "  Top consumers: ./scripts/top-consumers.sh"
        echo "  Storage capacity: ./scripts/storage-capacity.sh"
        echo "  Monthly report: ./scripts/capacity-report.sh"
        echo ""
    fi
}

main "$@"
