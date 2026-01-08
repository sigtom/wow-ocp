#!/bin/bash
set -euo pipefail

#############################################################################
# rollback-app.sh - Rollback ArgoCD Application
#
# Purpose: Rollback app to previous working revision
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
    echo -e "${GREEN}✓ $1${NC}" >&2
}

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 <app-name> [revision] [options]

${BLUE}Description:${NC}
  Rollback ArgoCD application to a previous revision.
  
  If no revision is specified, shows history for selection.

${BLUE}Options:${NC}
  --yes          Skip confirmation prompt
  --no-wait      Don't wait for healthy after rollback
  --help         Show this help

${BLUE}Examples:${NC}
  $0 plex                    # Show history and prompt for revision
  $0 plex 42                 # Rollback to revision 42
  $0 plex 42 --yes           # Rollback without confirmation

${BLUE}How to Find Revisions:${NC}
  argocd app history <app-name>
  
  Look for revision with "Succeeded" status.

${BLUE}Exit Codes:${NC}
  0 - Rollback successful and healthy
  1 - Rollback failed or app not found
  2 - Rollback succeeded but app unhealthy
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

REVISION=""
SKIP_CONFIRM=false
WAIT=true

# Check if second arg is a number (revision) or option
if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    REVISION="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --yes)
            SKIP_CONFIRM=true
            shift
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
    exit 1
fi

# Show current status
info "Current application status:"
CURRENT_REVISION=$(argocd app get "${APP_NAME}" -o json | jq -r '.status.sync.revision // "Unknown"' | cut -c1-8)
CURRENT_HEALTH=$(argocd app get "${APP_NAME}" -o json | jq -r '.status.health.status // "Unknown"')
info "  Revision: ${CURRENT_REVISION}"
info "  Health: ${CURRENT_HEALTH}"
echo ""

# Show history
info "Application history:"
argocd app history "${APP_NAME}"
echo ""

# If no revision specified, prompt for it
if [[ -z "${REVISION}" ]]; then
    echo -e "${BLUE}Enter revision number to rollback to:${NC} "
    read -r REVISION
    
    if [[ ! "${REVISION}" =~ ^[0-9]+$ ]]; then
        error "Invalid revision number: ${REVISION}"
        exit 1
    fi
fi

# Verify revision exists
if ! argocd app history "${APP_NAME}" | grep -q "^${REVISION} "; then
    error "Revision ${REVISION} not found in history"
    exit 1
fi

# Get revision details
REVISION_INFO=$(argocd app history "${APP_NAME}" | grep "^${REVISION} " || echo "")
info "Rolling back to:"
echo "${REVISION_INFO}"
echo ""

# Confirmation prompt
if [[ "${SKIP_CONFIRM}" == "false" ]]; then
    warning "This will rollback application '${APP_NAME}' to revision ${REVISION}"
    echo -e "${YELLOW}Are you sure? (yes/no):${NC} "
    read -r CONFIRM
    
    if [[ "${CONFIRM}" != "yes" ]]; then
        info "Rollback cancelled"
        exit 0
    fi
fi

# Perform rollback
info "Rolling back application: ${APP_NAME} to revision ${REVISION}"

if argocd app rollback "${APP_NAME}" "${REVISION}" 2>&1 | tee /tmp/argocd-rollback-$$.log; then
    success "Rollback command completed"
else
    ROLLBACK_EXIT=$?
    error "Rollback failed with exit code ${ROLLBACK_EXIT}"
    cat /tmp/argocd-rollback-$$.log >&2
    rm -f /tmp/argocd-rollback-$$.log
    exit 1
fi

rm -f /tmp/argocd-rollback-$$.log

# If no-wait, exit here
if [[ "${WAIT}" == "false" ]]; then
    info "Not waiting for health (--no-wait specified)"
    exit 0
fi

# Wait for sync and health
info "Waiting for application to sync and become healthy..."
TIMEOUT=300
START_TIME=$(date +%s)
POLL_INTERVAL=5

while true; do
    APP_JSON=$(argocd app get "${APP_NAME}" -o json 2>/dev/null)
    
    SYNC_STATUS=$(echo "${APP_JSON}" | jq -r '.status.sync.status // "Unknown"')
    HEALTH_STATUS=$(echo "${APP_JSON}" | jq -r '.status.health.status // "Unknown"')
    
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    info "[${ELAPSED}s] Sync: ${SYNC_STATUS}, Health: ${HEALTH_STATUS}"
    
    # Check if healthy
    if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
        success "Rollback successful - application is healthy!"
        
        # Show new status
        NEW_REVISION=$(argocd app get "${APP_NAME}" -o json | jq -r '.status.sync.revision // "Unknown"' | cut -c1-8)
        info "New revision: ${NEW_REVISION}"
        
        exit 0
    fi
    
    # Check if degraded
    if [[ "${HEALTH_STATUS}" == "Degraded" ]]; then
        error "Rollback completed but application is degraded"
        warning "Check resources for issues:"
        argocd app resources "${APP_NAME}" 2>/dev/null | grep -v Healthy | head -20
        exit 2
    fi
    
    # Check timeout
    if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
        error "Timeout waiting for healthy state (${TIMEOUT}s)"
        warning "Rollback may have succeeded but app not healthy yet"
        warning "Current status: Sync=${SYNC_STATUS}, Health=${HEALTH_STATUS}"
        exit 2
    fi
    
    sleep ${POLL_INTERVAL}
done
