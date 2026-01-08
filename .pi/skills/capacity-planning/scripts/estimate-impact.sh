#!/bin/bash
# Estimate Impact - Calculate capacity impact of new workload

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

WARN_THRESHOLD=85
CRIT_THRESHOLD=90

usage() {
    cat <<EOF
Usage: $0 <cpu_cores> <memory_gb> <replicas>

Estimate capacity impact of deploying new workload.

Parameters:
  cpu_cores  : CPU cores per pod (e.g., 2)
  memory_gb  : Memory GB per pod (e.g., 4)
  replicas   : Number of replicas (e.g., 3)

Example:
  $0 2 4 3
  # 3 replicas × 2 CPU × 4GB = 6 CPU cores, 12GB RAM total

EOF
    exit 1
}

[[ $# -ne 3 ]] && usage

CPU_PER_POD=$1
MEM_PER_POD=$2
REPLICAS=$3

# Validate inputs
if ! [[ "$CPU_PER_POD" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$MEM_PER_POD" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$REPLICAS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Invalid input. Use numbers only.${NC}" >&2
    usage
fi

check_prerequisites() {
    if ! command -v oc &> /dev/null || ! oc whoami &> /dev/null; then
        echo -e "${RED}ERROR: Not logged into OpenShift${NC}" >&2; exit 1
    fi
}

get_color() {
    local usage=$1
    if (( $(echo "$usage >= $CRIT_THRESHOLD" | bc -l) )); then echo "$RED"
    elif (( $(echo "$usage >= $WARN_THRESHOLD" | bc -l) )); then echo "$YELLOW"
    else echo "$GREEN"; fi
}

main() {
    check_prerequisites
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}              New Workload Capacity Impact Estimation               ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Calculate workload requirements
    TOTAL_CPU=$(echo "$CPU_PER_POD * $REPLICAS" | bc)
    TOTAL_MEM=$(echo "$MEM_PER_POD * $REPLICAS" | bc)
    
    echo -e "${BOLD}New Workload Specification${NC}"
    echo "  CPU per pod: ${CPU_PER_POD} cores"
    echo "  Memory per pod: ${MEM_PER_POD} GB"
    echo "  Replicas: ${REPLICAS}"
    echo "  ${YELLOW}Total CPU: ${TOTAL_CPU} cores${NC}"
    echo "  ${YELLOW}Total Memory: ${TOTAL_MEM} GB${NC}"
    echo ""
    
    # Get current cluster capacity
    CLUSTER_CPU=$(oc get nodes -o json | jq '[.items[].status.allocatable.cpu | rtrimstr("m") | tonumber] | add / 1000' 2>/dev/null)
    CLUSTER_MEM_KB=$(oc get nodes -o json | jq '[.items[].status.allocatable.memory | rtrimstr("Ki") | tonumber] | add' 2>/dev/null)
    CLUSTER_MEM=$(echo "scale=2; $CLUSTER_MEM_KB / 1024 / 1024" | bc)
    
    REQ_CPU=$(oc get pods --all-namespaces -o json | jq '[.items[].spec.containers[]?.resources.requests.cpu // "0" | if type == "string" then (rtrimstr("m") | tonumber / 1000) else . end] | add' 2>/dev/null)
    REQ_MEM_KB=$(oc get pods --all-namespaces -o json | jq '[.items[].spec.containers[]?.resources.requests.memory // "0" | if type == "string" then (rtrimstr("Ki") | tonumber) else (. * 1024 * 1024) end] | add' 2>/dev/null)
    REQ_MEM=$(echo "scale=2; $REQ_MEM_KB / 1024 / 1024" | bc)
    
    CURR_CPU_PCT=$(echo "scale=1; ($REQ_CPU / $CLUSTER_CPU) * 100" | bc)
    CURR_MEM_PCT=$(echo "scale=1; ($REQ_MEM / $CLUSTER_MEM) * 100" | bc)
    
    echo -e "${BOLD}Current Cluster Utilization${NC}"
    echo "  CPU: ${REQ_CPU}/${CLUSTER_CPU} cores (${CURR_CPU_PCT}%)"
    echo "  Memory: ${REQ_MEM}/${CLUSTER_MEM} GB (${CURR_MEM_PCT}%)"
    echo ""
    
    # Calculate projected utilization
    PROJ_CPU=$(echo "$REQ_CPU + $TOTAL_CPU" | bc)
    PROJ_MEM=$(echo "$REQ_MEM + $TOTAL_MEM" | bc)
    PROJ_CPU_PCT=$(echo "scale=1; ($PROJ_CPU / $CLUSTER_CPU) * 100" | bc)
    PROJ_MEM_PCT=$(echo "scale=1; ($PROJ_MEM / $CLUSTER_MEM) * 100" | bc)
    
    CPU_COLOR=$(get_color "$PROJ_CPU_PCT")
    MEM_COLOR=$(get_color "$PROJ_MEM_PCT")
    
    echo -e "${BOLD}Projected Utilization After Deployment${NC}"
    echo -e "  CPU: ${PROJ_CPU}/${CLUSTER_CPU} cores (${CPU_COLOR}${PROJ_CPU_PCT}%${NC})"
    echo -e "  Memory: ${PROJ_MEM}/${CLUSTER_MEM} GB (${MEM_COLOR}${PROJ_MEM_PCT}%${NC})"
    echo ""
    
    # Decision
    DECISION="GO"
    DECISION_COLOR="$GREEN"
    
    if (( $(echo "$PROJ_CPU_PCT >= $CRIT_THRESHOLD" | bc -l) )) || (( $(echo "$PROJ_MEM_PCT >= $CRIT_THRESHOLD" | bc -l) )); then
        DECISION="NO-GO"
        DECISION_COLOR="$RED"
    elif (( $(echo "$PROJ_CPU_PCT >= $WARN_THRESHOLD" | bc -l) )) || (( $(echo "$PROJ_MEM_PCT >= $WARN_THRESHOLD" | bc -l) )); then
        DECISION="CAUTION"
        DECISION_COLOR="$YELLOW"
    fi
    
    echo -e "${BOLD}Deployment Recommendation: ${DECISION_COLOR}${DECISION}${NC}"
    echo ""
    
    case "$DECISION" in
        "GO")
            echo -e "${GREEN}✓ Deployment is safe to proceed${NC}"
            echo "  Projected utilization is within healthy thresholds (<85%)"
            ;;
        "CAUTION")
            echo -e "${YELLOW}⚠ Proceed with caution${NC}"
            echo "  Projected utilization is 85-90% (near capacity)"
            echo "  Recommendations:"
            echo "    - Monitor closely after deployment"
            echo "    - Plan for capacity expansion"
            echo "    - Consider scaling down if issues arise"
            ;;
        "NO-GO")
            echo -e "${RED}✗ Deployment NOT recommended${NC}"
            echo "  Projected utilization exceeds 90% threshold"
            echo ""
            echo "  Options:"
            if (( $(echo "$PROJ_CPU_PCT >= $CRIT_THRESHOLD" | bc -l) )); then
                SAFE_REPLICAS=$(echo "scale=0; ($CLUSTER_CPU * 0.85 - $REQ_CPU) / $CPU_PER_POD" | bc)
                [[ $SAFE_REPLICAS -lt 1 ]] && SAFE_REPLICAS=1
                echo "    1. Reduce replicas to ${SAFE_REPLICAS} (CPU constraint)"
            fi
            if (( $(echo "$PROJ_MEM_PCT >= $CRIT_THRESHOLD" | bc -l) )); then
                SAFE_REPLICAS=$(echo "scale=0; ($CLUSTER_MEM * 0.85 - $REQ_MEM) / $MEM_PER_POD" | bc)
                [[ $SAFE_REPLICAS -lt 1 ]] && SAFE_REPLICAS=1
                echo "    1. Reduce replicas to ${SAFE_REPLICAS} (Memory constraint)"
            fi
            echo "    2. Remove unused workloads: ./top-consumers.sh"
            echo "    3. Defer deployment until capacity cleanup"
            echo "    4. Plan cluster expansion"
            ;;
    esac
    echo ""
    
    echo -e "${BOLD}Next Steps${NC}"
    echo "  Check capacity: ./cluster-capacity.sh"
    echo "  Review top consumers: ./top-consumers.sh"
    echo "  Node breakdown: ./node-utilization.sh"
    echo ""
}

main "$@"
