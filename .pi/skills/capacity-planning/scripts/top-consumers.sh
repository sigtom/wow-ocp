#!/bin/bash
# Top Consumers - List top resource consumers

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

check_prerequisites() {
    if ! command -v oc &> /dev/null || ! oc whoami &> /dev/null; then
        echo -e "${RED}ERROR: Not logged into OpenShift${NC}" >&2; exit 1
    fi
}

main() {
    check_prerequisites
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                    Top Resource Consumers                          ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BOLD}Top 10 Namespaces by CPU Usage${NC}"
    oc adm top pods --all-namespaces --no-headers 2>/dev/null | awk '{cpu[$1]+=$2} END {for (ns in cpu) print cpu[ns], ns}' | sort -rn | head -10 | nl | while read num usage ns; do
        echo "  $num. ${BLUE}${ns}${NC}: ${usage}m"
    done
    echo ""
    
    echo -e "${BOLD}Top 10 Namespaces by Memory Usage${NC}"
    oc adm top pods --all-namespaces --no-headers 2>/dev/null | awk '{gsub("Mi","",$3); mem[$1]+=$3} END {for (ns in mem) print mem[ns], ns}' | sort -rn | head -10 | nl | while read num usage ns; do
        echo "  $num. ${BLUE}${ns}${NC}: ${usage}Mi"
    done
    echo ""
    
    echo -e "${BOLD}Top 10 Pods by CPU Usage${NC}"
    oc adm top pods --all-namespaces --no-headers 2>/dev/null | sort -k2 -rn | head -10 | nl | while read num ns name cpu mem; do
        echo "  $num. ${ns}/${YELLOW}${name}${NC}: ${cpu}"
    done
    echo ""
    
    echo -e "${BOLD}Top 10 Pods by Memory Usage${NC}"
    oc adm top pods --all-namespaces --no-headers 2>/dev/null | sort -k3 -rn | head -10 | nl | while read num ns name cpu mem; do
        echo "  $num. ${ns}/${YELLOW}${name}${NC}: ${mem}"
    done
    echo ""
    
    echo -e "${BOLD}Top 10 PVCs by Size${NC}"
    oc get pvc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.resources.requests.storage)"' | sort -t' ' -k3 -hr | head -10 | nl | while read num ns name size; do
        echo "  $num. ${ns}/${GREEN}${name}${NC}: ${size}"
    done
    echo ""
    
    echo -e "${BOLD}Analysis Tips${NC}"
    echo "  Review specific namespace: oc adm top pods -n <namespace> --sort-by=cpu"
    echo "  Check resource requests: oc describe pod <pod> -n <ns> | grep -A5 Requests"
    echo "  Unused PVCs: ./storage-capacity.sh --show-unused"
    echo ""
}

main "$@"
