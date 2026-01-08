#!/bin/bash
set -euo pipefail

#############################################################################
# sync-app.sh - Sync ArgoCD Application and Wait for Healthy
#
# Purpose: Sync app and wait for it to reach healthy state
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
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}" >&2
}

info() {
    echo -e "${BLUE}→ $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ SUCCESS: $1${NC}" >&2
}

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 <app-name> [options]

${BLUE}Description:${NC}
  Sync an ArgoCD application and wait for it to become healthy.

${BLUE}Options:${NC}
  --prune        Delete resources not in Git
  --force        Force sync even if already synced
  --timeout N    Wait timeout in seconds (default: 300)
  --no-wait      Don't wait for healthy, just sync
  --help         Show this help

${BLUE}Examples:${NC}
  $0 plex                          # Sync plex app
  $0 plex --prune                  # Sync and prune deleted resources
  $0 plex --force --timeout 600    # Force sync with 10min timeout

${BLUE}Exit Codes:${NC}
  0 - Synced and healthy
  1 - Sync failed or timed out
  2 - Synced but unhealthy
EOF
    exit 1
}

# Preflight checks
if ! command -v argocd &> /dev/null; then
    error "argocd CLI not found"
    echo "Install: brew install argocd (macOS) or https://argo-cd.readthedocs.io/en/stable/cli_installation/" >&2
    exit 1
fi

if ! argocd app list &> /dev/null; then
    error "Not logged into ArgoCD"
    echo "Run: argocd login <server-url>" >&2
    exit 1
fi

# Parse arguments
if [[ $# -lt 1 ]]; then
    usage
fi

APP_NAME="$1"
shift

PRUNE=false
FORCE=false
TIMEOUT=300
WAIT=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --prune)
            PRUNE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --no-wait)
            WAIT=false
            shift
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
    echo "Available apps:" >&2
    argocd app list -o name >&2
    exit 1
fi

info "Syncing application: ${APP_NAME}"

# Get current status before sync
CURRENT_SYNC=$(argocd app get "${APP_NAME}" -o json | jq -r '.status.sync.status // "Unknown"')
CURRENT_HEALTH=$(argocd app get "${APP_NAME}" -o json | jq -r '.status.health.status // "Unknown"')
info "Current state: Sync=${CURRENT_SYNC}, Health=${CURRENT_HEALTH}"

# Build sync command
SYNC_CMD="argocd app sync ${APP_NAME}"

if [[ "${PRUNE}" == "true" ]]; then
    SYNC_CMD="${SYNC_CMD} --prune"
    info "Prune enabled: Will delete resources not in Git"
fi

if [[ "${FORCE}" == "true" ]]; then
    SYNC_CMD="${SYNC_CMD} --force"
    info "Force enabled: Will sync even if already synced"
fi

# Add timeout to sync operation
SYNC_CMD="${SYNC_CMD} --timeout ${TIMEOUT}"

# Execute sync
info "Executing: ${SYNC_CMD}"
if eval "${SYNC_CMD}" 2>&1 | tee /tmp/argocd-sync-$$.log; then
    success "Sync command completed"
else
    SYNC_EXIT=$?
    error "Sync command failed with exit code ${SYNC_EXIT}"
    cat /tmp/argocd-sync-$$.log >&2
    rm -f /tmp/argocd-sync-$$.log
    exit 1
fi

rm -f /tmp/argocd-sync-$$.log

# If no-wait, exit here
if [[ "${WAIT}" == "false" ]]; then
    info "Not waiting for health (--no-wait specified)"
    exit 0
fi

# Wait for healthy state
info "Waiting for application to become healthy (timeout: ${TIMEOUT}s)..."

START_TIME=$(date +%s)
POLL_INTERVAL=5

while true; do
    # Get current status
    APP_JSON=$(argocd app get "${APP_NAME}" -o json 2>/dev/null)
    
    SYNC_STATUS=$(echo "${APP_JSON}" | jq -r '.status.sync.status // "Unknown"')
    HEALTH_STATUS=$(echo "${APP_JSON}" | jq -r '.status.health.status // "Unknown"')
    
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    info "[${ELAPSED}s] Sync: ${SYNC_STATUS}, Health: ${HEALTH_STATUS}"
    
    # Check if healthy
    if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
        success "Application is synced and healthy!"
        
        # Show resources
        echo ""
        info "Application resources:"
        argocd app resources "${APP_NAME}" 2>/dev/null | grep -E "NAME|GROUP" | head -20
        
        exit 0
    fi
    
    # Check if degraded
    if [[ "${HEALTH_STATUS}" == "Degraded" ]]; then
        error "Application is degraded"
        warning "Check resources for issues:"
        argocd app resources "${APP_NAME}" 2>/dev/null | grep -v Healthy | head -20
        exit 2
    fi
    
    # Check timeout
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        error "Timeout waiting for healthy state (${TIMEOUT}s)"
        warning "Current status: Sync=${SYNC_STATUS}, Health=${HEALTH_STATUS}"
        echo ""
        info "Resources that may be unhealthy:"
        argocd app resources "${APP_NAME}" 2>/dev/null | grep -v Healthy | head -20
        exit 1
    fi
    
    # Sleep before next poll
    sleep ${POLL_INTERVAL}
done
