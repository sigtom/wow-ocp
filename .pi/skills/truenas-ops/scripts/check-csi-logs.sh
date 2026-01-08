#!/bin/bash
set -euo pipefail

#############################################################################
# check-csi-logs.sh - Tail Democratic CSI Logs
#
# Purpose: View CSI driver logs with error filtering
# Author: Senior SRE (Gen X Edition)
# Version: 1.0
#############################################################################

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 [--controller|--node] [--errors-only] [--tail N]

${BLUE}Description:${NC}
  Tail logs from Democratic CSI driver pods.

${BLUE}Options:${NC}
  --controller    Show only controller logs
  --node          Show only node driver logs
  --errors-only   Filter for error/warning messages
  --tail N        Number of lines to show (default: 50)

${BLUE}Examples:${NC}
  $0                          # All pods, last 50 lines
  $0 --controller             # Controller only
  $0 --errors-only            # Errors from all pods
  $0 --controller --tail 100  # Controller, last 100 lines
EOF
    exit 1
}

if ! command -v oc &> /dev/null; then
    echo -e "${RED}ERROR: oc CLI not found${NC}" >&2
    exit 1
fi

MODE="all"
ERRORS_ONLY=false
TAIL_LINES=50

while [[ $# -gt 0 ]]; do
    case $1 in
        --controller) MODE="controller"; shift ;;
        --node) MODE="node"; shift ;;
        --errors-only) ERRORS_ONLY=true; shift ;;
        --tail) TAIL_LINES="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo -e "${RED}Unknown option: $1${NC}" >&2; usage ;;
    esac
done

# Get pods
if [[ "${MODE}" == "controller" || "${MODE}" == "all" ]]; then
    CONTROLLER_POD=$(oc get pods -n democratic-csi -l app.kubernetes.io/name=democratic-csi -o name 2>/dev/null | grep controller | head -1)
fi

if [[ "${MODE}" == "node" || "${MODE}" == "all" ]]; then
    NODE_PODS=$(oc get pods -n democratic-csi -l app.kubernetes.io/name=democratic-csi -o name 2>/dev/null | grep -v controller)
fi

if [[ -z "${CONTROLLER_POD:-}" && -z "${NODE_PODS:-}" ]]; then
    echo -e "${RED}ERROR: No CSI pods found in namespace democratic-csi${NC}" >&2
    exit 1
fi

# Filter function
filter_logs() {
    if [[ "${ERRORS_ONLY}" == "true" ]]; then
        grep -i -E "error|warn|fail|fatal" || echo "No errors found"
    else
        cat
    fi
}

# Show controller logs
if [[ -n "${CONTROLLER_POD:-}" ]]; then
    echo -e "${BLUE}━━━ Controller Logs (${CONTROLLER_POD}) ━━━${NC}"
    echo ""
    
    oc logs -n democratic-csi ${CONTROLLER_POD} -c democratic-csi-driver --tail=${TAIL_LINES} 2>&1 | filter_logs
    
    echo ""
fi

# Show node logs
if [[ -n "${NODE_PODS:-}" ]]; then
    for pod in ${NODE_PODS}; do
        NODE_NAME=$(oc get ${pod} -n democratic-csi -o jsonpath='{.spec.nodeName}' 2>/dev/null)
        echo -e "${BLUE}━━━ Node Logs (${pod} on ${NODE_NAME}) ━━━${NC}"
        echo ""
        
        oc logs -n democratic-csi ${pod} -c democratic-csi-driver --tail=${TAIL_LINES} 2>&1 | filter_logs
        
        echo ""
    done
fi

# Summary
echo -e "${BLUE}━━━ Common Issues to Look For ━━━${NC}"
echo "  • 'connection refused' → Storage network (VLAN 160) issue"
echo "  • 'unsupported API' → Wrong image tag (need 'next' for TrueNAS 25.10)"
echo "  • 'authentication failed' → Invalid API key"
echo "  • 'quota exceeded' → ZFS pool full"
echo "  • 'mount failed' → NFS export or permissions issue"
