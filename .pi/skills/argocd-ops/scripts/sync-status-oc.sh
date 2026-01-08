#!/bin/bash
set -euo pipefail

#############################################################################
# sync-status-oc.sh - Show ArgoCD Application Status (Using oc)
#
# Purpose: Alternative to sync-status.sh that uses oc instead of argocd CLI
# Use when: argocd CLI has connectivity issues but oc works
#############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 [options]

${BLUE}Description:${NC}
  Display all ArgoCD applications using oc CLI (alternative to argocd CLI).

${BLUE}Options:${NC}
  --unhealthy    Show only unhealthy or out-of-sync apps
  --namespace NS Filter by application namespace
  --help         Show this help

${BLUE}Examples:${NC}
  $0                    # Show all apps
  $0 --unhealthy        # Show only problematic apps
EOF
    exit 1
}

if ! command -v oc &> /dev/null; then
    echo -e "${RED}ERROR: oc CLI not found${NC}" >&2
    exit 1
fi

SHOW_UNHEALTHY_ONLY=false
FILTER_NAMESPACE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --unhealthy) SHOW_UNHEALTHY_ONLY=true; shift ;;
        --namespace) FILTER_NAMESPACE="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo -e "${RED}Unknown option: $1${NC}" >&2; usage ;;
    esac
done

# Function to colorize status
colorize_sync() {
    case "$1" in
        Synced) echo -e "${GREEN}$1${NC}" ;;
        OutOfSync) echo -e "${YELLOW}$1${NC}" ;;
        *) echo -e "${RED}$1${NC}" ;;
    esac
}

colorize_health() {
    case "$1" in
        Healthy) echo -e "${GREEN}$1${NC}" ;;
        Progressing|Suspended) echo -e "${YELLOW}$1${NC}" ;;
        Degraded|Missing) echo -e "${RED}$1${NC}" ;;
        *) echo "$1" ;;
    esac
}

# Print header
printf "${BLUE}%-30s %-12s %-12s %-20s${NC}\n" "NAME" "SYNC" "HEALTH" "NAMESPACE"
printf "%.s─" {1..80}
echo

# Get apps
if [[ -n "${FILTER_NAMESPACE}" ]]; then
    APPS=$(oc get applications -A --no-headers 2>/dev/null | grep " ${FILTER_NAMESPACE} ")
else
    APPS=$(oc get applications -A --no-headers 2>/dev/null)
fi

if [[ -z "${APPS}" ]]; then
    echo -e "${YELLOW}No ArgoCD applications found${NC}" >&2
    exit 0
fi

TOTAL=0
SYNCED=0
HEALTHY=0
OUTOF_SYNC=0
DEGRADED=0

while IFS= read -r line; do
    APP_NS=$(echo "$line" | awk '{print $1}')
    NAME=$(echo "$line" | awk '{print $2}')
    SYNC=$(echo "$line" | awk '{print $3}')
    HEALTH=$(echo "$line" | awk '{print $4}')
    
    # Apply unhealthy filter
    if [[ "${SHOW_UNHEALTHY_ONLY}" == "true" ]]; then
        if [[ "${SYNC}" == "Synced" && "${HEALTH}" == "Healthy" ]]; then
            continue
        fi
    fi
    
    # Count stats
    ((TOTAL++)) || true
    [[ "${SYNC}" == "Synced" ]] && ((SYNCED++)) || true
    [[ "${HEALTH}" == "Healthy" ]] && ((HEALTHY++)) || true
    [[ "${SYNC}" == "OutOfSync" ]] && ((OUTOF_SYNC++)) || true
    [[ "${HEALTH}" == "Degraded" ]] && ((DEGRADED++)) || true
    
    # Colorize
    SYNC_COLORED=$(colorize_sync "${SYNC}")
    HEALTH_COLORED=$(colorize_health "${HEALTH}")
    
    # Print row
    printf "%-30s %-20s %-20s %-20s\n" "${NAME}" "${SYNC_COLORED}" "${HEALTH_COLORED}" "${APP_NS}"
done <<< "${APPS}"

# Summary
echo
echo -e "${BLUE}Summary:${NC}"
echo -e "  Total Applications: ${TOTAL}"
echo -e "  ${GREEN}Synced:${NC} ${SYNCED}/${TOTAL}"
echo -e "  ${GREEN}Healthy:${NC} ${HEALTHY}/${TOTAL}"

[[ ${OUTOF_SYNC} -gt 0 ]] && echo -e "  ${YELLOW}OutOfSync:${NC} ${OUTOF_SYNC}"
[[ ${DEGRADED} -gt 0 ]] && echo -e "  ${RED}Degraded:${NC} ${DEGRADED}"

# Exit code
[[ ${DEGRADED} -gt 0 ]] && exit 1
[[ ${OUTOF_SYNC} -gt 0 ]] && exit 2
exit 0
