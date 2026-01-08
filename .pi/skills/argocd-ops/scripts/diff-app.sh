#!/bin/bash
set -euo pipefail

#############################################################################
# diff-app.sh - Show ArgoCD Application Diff
#
# Purpose: Show what would change if app is synced (Git vs Cluster)
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
  Show differences between Git (desired state) and cluster (current state).
  
  This is a "dry-run" of what would change if you sync the application.

${BLUE}Options:${NC}
  --local PATH   Diff against local path instead of Git
  --revision REV Diff against specific Git revision
  --help         Show this help

${BLUE}Examples:${NC}
  $0 plex                           # Show diff for plex app
  $0 plex --local apps/plex/        # Diff against local changes
  $0 plex --revision HEAD~1         # Diff against previous commit

${BLUE}Output:${NC}
  Empty output = No changes (cluster matches Git)
  Unified diff format with:
    - Lines in red (deletions)
    + Lines in green (additions)
    
${BLUE}Exit Codes:${NC}
  0 - No diff (in sync)
  1 - Error or app not found
  2 - Has diff (out of sync)
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

LOCAL_PATH=""
REVISION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_PATH="$2"
            shift 2
            ;;
        --revision)
            REVISION="$2"
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

info "Fetching diff for application: ${APP_NAME}"

# Get current sync status
SYNC_STATUS=$(argocd app get "${APP_NAME}" -o json | jq -r '.status.sync.status // "Unknown"')
info "Current sync status: ${SYNC_STATUS}"

# Build diff command
DIFF_CMD="argocd app diff ${APP_NAME}"

if [[ -n "${LOCAL_PATH}" ]]; then
    DIFF_CMD="${DIFF_CMD} --local ${LOCAL_PATH}"
    info "Using local path: ${LOCAL_PATH}"
fi

if [[ -n "${REVISION}" ]]; then
    DIFF_CMD="${DIFF_CMD} --revision ${REVISION}"
    info "Using revision: ${REVISION}"
fi

# Execute diff
echo ""
info "Differences between Git (desired) and Cluster (current):"
echo ""

DIFF_OUTPUT=$(eval "${DIFF_CMD}" 2>&1 || true)

# Check if there's a diff
if [[ -z "${DIFF_OUTPUT}" ]]; then
    success "No differences - cluster matches Git"
    success "Application is in sync"
    exit 0
fi

# Colorize diff output
echo "${DIFF_OUTPUT}" | while IFS= read -r line; do
    if [[ "${line}" =~ ^- ]]; then
        echo -e "${RED}${line}${NC}"
    elif [[ "${line}" =~ ^\+ ]]; then
        echo -e "${GREEN}${line}${NC}"
    elif [[ "${line}" =~ ^@@ ]]; then
        echo -e "${BLUE}${line}${NC}"
    else
        echo "${line}"
    fi
done

echo ""
info "To apply these changes, run:"
echo "  ./sync-app.sh ${APP_NAME}"

exit 2
