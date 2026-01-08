#!/bin/bash
set -euo pipefail

#############################################################################
# sync-status.sh - Show ArgoCD Application Status
#
# Purpose: Display all ArgoCD applications with sync and health status
# Author: Senior SRE (Gen X Edition)
# Version: 1.0
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
  Display all ArgoCD applications with sync and health status in table format.

${BLUE}Options:${NC}
  --unhealthy    Show only unhealthy or out-of-sync apps
  --namespace    Filter by application namespace
  --help         Show this help

${BLUE}Examples:${NC}
  $0                    # Show all apps
  $0 --unhealthy        # Show only problematic apps
  $0 --namespace media  # Show apps in media namespace

${BLUE}Output:${NC}
  Table with columns: NAME, SYNC, HEALTH, NAMESPACE, AGE
  
  Colors:
    Green  = Synced + Healthy
    Yellow = OutOfSync or Progressing
    Red    = Degraded or Failed
EOF
    exit 1
}

# Preflight checks
if ! command -v argocd &> /dev/null; then
    echo -e "${RED}ERROR: argocd CLI not found${NC}" >&2
    echo "Install: brew install argocd (macOS) or https://argo-cd.readthedocs.io/en/stable/cli_installation/" >&2
    exit 1
fi

# Check if logged in
if ! argocd app list &> /dev/null; then
    echo -e "${RED}ERROR: Not logged into ArgoCD${NC}" >&2
    echo "Run: argocd login <server-url>" >&2
    exit 1
fi

# Parse arguments
SHOW_UNHEALTHY_ONLY=false
FILTER_NAMESPACE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --unhealthy)
            SHOW_UNHEALTHY_ONLY=true
            shift
            ;;
        --namespace)
            FILTER_NAMESPACE="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            usage
            ;;
    esac
done

# Get apps in JSON format for easier parsing
APPS_JSON=$(argocd app list -o json 2>/dev/null)

if [[ -z "${APPS_JSON}" || "${APPS_JSON}" == "[]" ]]; then
    echo -e "${YELLOW}No ArgoCD applications found${NC}" >&2
    exit 0
fi

# Function to colorize status
colorize_sync() {
    local status="$1"
    case "${status}" in
        Synced)
            echo -e "${GREEN}${status}${NC}"
            ;;
        OutOfSync)
            echo -e "${YELLOW}${status}${NC}"
            ;;
        Unknown)
            echo -e "${CYAN}${status}${NC}"
            ;;
        *)
            echo -e "${RED}${status}${NC}"
            ;;
    esac
}

colorize_health() {
    local status="$1"
    case "${status}" in
        Healthy)
            echo -e "${GREEN}${status}${NC}"
            ;;
        Progressing|Suspended)
            echo -e "${YELLOW}${status}${NC}"
            ;;
        Degraded|Missing)
            echo -e "${RED}${status}${NC}"
            ;;
        Unknown)
            echo -e "${CYAN}${status}${NC}"
            ;;
        *)
            echo "${status}"
            ;;
    esac
}

# Print header
printf "${BLUE}%-30s %-12s %-12s %-20s %s${NC}\n" "NAME" "SYNC" "HEALTH" "NAMESPACE" "AGE"
printf "%.s─" {1..90}
echo

# Parse and display apps
echo "${APPS_JSON}" | jq -r '.[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")|\(.spec.destination.namespace // "N/A")|\(.metadata.creationTimestamp)"' | \
while IFS='|' read -r name sync health namespace created; do
    # Apply namespace filter
    if [[ -n "${FILTER_NAMESPACE}" && "${namespace}" != "${FILTER_NAMESPACE}" ]]; then
        continue
    fi
    
    # Apply unhealthy filter
    if [[ "${SHOW_UNHEALTHY_ONLY}" == "true" ]]; then
        if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
            continue
        fi
    fi
    
    # Calculate age
    if [[ -n "${created}" && "${created}" != "null" ]]; then
        created_epoch=$(date -d "${created}" +%s 2>/dev/null || echo "0")
        now_epoch=$(date +%s)
        age_seconds=$((now_epoch - created_epoch))
        
        if [[ ${age_seconds} -lt 3600 ]]; then
            age="$((age_seconds / 60))m"
        elif [[ ${age_seconds} -lt 86400 ]]; then
            age="$((age_seconds / 3600))h"
        else
            age="$((age_seconds / 86400))d"
        fi
    else
        age="N/A"
    fi
    
    # Colorize status
    sync_colored=$(colorize_sync "${sync}")
    health_colored=$(colorize_health "${health}")
    
    # Print row
    printf "%-30s %-20s %-20s %-20s %s\n" "${name}" "${sync_colored}" "${health_colored}" "${namespace}" "${age}"
done

# Summary
echo
TOTAL=$(echo "${APPS_JSON}" | jq '. | length')
SYNCED=$(echo "${APPS_JSON}" | jq '[.[] | select(.status.sync.status == "Synced")] | length')
HEALTHY=$(echo "${APPS_JSON}" | jq '[.[] | select(.status.health.status == "Healthy")] | length')
OUTOF_SYNC=$(echo "${APPS_JSON}" | jq '[.[] | select(.status.sync.status == "OutOfSync")] | length')
DEGRADED=$(echo "${APPS_JSON}" | jq '[.[] | select(.status.health.status == "Degraded")] | length')

echo -e "${BLUE}Summary:${NC}"
echo -e "  Total Applications: ${TOTAL}"
echo -e "  ${GREEN}Synced:${NC} ${SYNCED}/${TOTAL}"
echo -e "  ${GREEN}Healthy:${NC} ${HEALTHY}/${TOTAL}"

if [[ ${OUTOF_SYNC} -gt 0 ]]; then
    echo -e "  ${YELLOW}OutOfSync:${NC} ${OUTOF_SYNC}"
fi

if [[ ${DEGRADED} -gt 0 ]]; then
    echo -e "  ${RED}Degraded:${NC} ${DEGRADED}"
fi

# Exit code based on health
if [[ ${DEGRADED} -gt 0 ]]; then
    exit 1
elif [[ ${OUTOF_SYNC} -gt 0 ]]; then
    exit 2
else
    exit 0
fi
