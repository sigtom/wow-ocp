#!/bin/bash
set -euo pipefail

#############################################################################
# watch-sync.sh - Watch ArgoCD Application Sync Progress
#
# Purpose: Continuously watch app until synced and healthy
# Author: Senior SRE (Gen X Edition)
# Version: 1.0
#############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}" >&2
}

info() {
    echo -e "${BLUE}→ $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ $1${NC}" >&2
}

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 <app-name> [options]

${BLUE}Description:${NC}
  Watch ArgoCD application sync progress until it reaches healthy state.
  
  Updates every 5 seconds with current sync and health status.

${BLUE}Options:${NC}
  --timeout N    Timeout in seconds (default: 600)
  --interval N   Poll interval in seconds (default: 5)
  --help         Show this help

${BLUE}Examples:${NC}
  $0 plex                        # Watch plex app
  $0 plex --timeout 1200         # Watch with 20min timeout
  $0 plex --interval 2           # Update every 2 seconds

${BLUE}Exit Codes:${NC}
  0 - Synced and healthy
  1 - Timeout or app not found
  2 - Synced but degraded
EOF
    exit 1
}

# Preflight checks
if ! command -v argocd &> /dev/null; then
    error "argocd CLI not found"
    exit 1
fi

if ! argocd app list &> /dev/null; then
    error "Not logged into ArgoCD"
    exit 1
fi

# Parse arguments
if [[ $# -lt 1 ]]; then
    usage
fi

APP_NAME="$1"
shift

TIMEOUT=600
INTERVAL=5

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if app exists
if ! argocd app get "${APP_NAME}" &> /dev/null; then
    error "Application '${APP_NAME}' not found"
    exit 1
fi

info "Watching application: ${APP_NAME}"
info "Timeout: ${TIMEOUT}s, Poll Interval: ${INTERVAL}s"
info "Press Ctrl+C to stop watching"
echo ""

START_TIME=$(date +%s)
PREV_SYNC=""
PREV_HEALTH=""
PREV_RESOURCES=""

# Function to format status with color
format_status() {
    local type="$1"
    local status="$2"
    
    if [[ "${type}" == "sync" ]]; then
        case "${status}" in
            Synced)
                echo -e "${GREEN}${status}${NC}"
                ;;
            OutOfSync)
                echo -e "${YELLOW}${status}${NC}"
                ;;
            *)
                echo -e "${RED}${status}${NC}"
                ;;
        esac
    elif [[ "${type}" == "health" ]]; then
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
            *)
                echo -e "${status}"
                ;;
        esac
    fi
}

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    # Get app status
    APP_JSON=$(argocd app get "${APP_NAME}" -o json 2>/dev/null)
    
    SYNC_STATUS=$(echo "${APP_JSON}" | jq -r '.status.sync.status // "Unknown"')
    HEALTH_STATUS=$(echo "${APP_JSON}" | jq -r '.status.health.status // "Unknown"')
    REVISION=$(echo "${APP_JSON}" | jq -r '.status.sync.revision // "Unknown"' | cut -c1-8)
    
    # Get resource summary (argocd app resources doesn't support -o json, use text parsing)
    RESOURCES_OUTPUT=$(argocd app resources "${APP_NAME}" 2>/dev/null || echo "")
    TOTAL_RESOURCES=$(echo "${RESOURCES_OUTPUT}" | grep -v "GROUP\|NAME\|^$" | wc -l)
    HEALTHY_RESOURCES=$(echo "${RESOURCES_OUTPUT}" | grep "Healthy" | wc -l)
    
    # Build status line
    SYNC_FORMATTED=$(format_status "sync" "${SYNC_STATUS}")
    HEALTH_FORMATTED=$(format_status "health" "${HEALTH_STATUS}")
    
    # Print update if status changed
    CURRENT_STATE="${SYNC_STATUS}|${HEALTH_STATUS}|${HEALTHY_RESOURCES}"
    PREV_STATE="${PREV_SYNC}|${PREV_HEALTH}|${PREV_RESOURCES}"
    
    if [[ "${CURRENT_STATE}" != "${PREV_STATE}" || $((ELAPSED % 30)) -eq 0 ]]; then
        printf "[%3ds] Sync: %-15s Health: %-15s Resources: %d/%d Healthy | Rev: %s\n" \
            "${ELAPSED}" \
            "${SYNC_FORMATTED}" \
            "${HEALTH_FORMATTED}" \
            "${HEALTHY_RESOURCES}" \
            "${TOTAL_RESOURCES}" \
            "${REVISION}"
    fi
    
    PREV_SYNC="${SYNC_STATUS}"
    PREV_HEALTH="${HEALTH_STATUS}"
    PREV_RESOURCES="${HEALTHY_RESOURCES}"
    
    # Check if healthy
    if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
        echo ""
        success "Application is synced and healthy!"
        success "Total time: ${ELAPSED}s"
        
        # Show resource summary
        echo ""
        info "Resources:"
        argocd app resources "${APP_NAME}" 2>/dev/null | grep -E "NAME|GROUP|HEALTH|STATUS" | head -15
        
        exit 0
    fi
    
    # Check if degraded
    if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Degraded" ]]; then
        echo ""
        error "Application is degraded"
        warning "Unhealthy resources:"
        argocd app resources "${APP_NAME}" 2>/dev/null | grep -v Healthy | head -15
        exit 2
    fi
    
    # Check timeout
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        echo ""
        error "Timeout after ${TIMEOUT}s"
        warning "Current state: Sync=${SYNC_STATUS}, Health=${HEALTH_STATUS}"
        
        # Show last known status
        echo ""
        info "Last known resource status:"
        argocd app resources "${APP_NAME}" 2>/dev/null | head -15
        
        exit 1
    fi
    
    sleep ${INTERVAL}
done
