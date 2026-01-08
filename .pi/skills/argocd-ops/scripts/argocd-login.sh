#!/bin/bash
set -euo pipefail

#############################################################################
# argocd-login.sh - Helper to login to ArgoCD via port-forward
#
# Purpose: Simplify ArgoCD CLI login since gRPC ingress is disabled
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
  $0 [--keep-alive]

${BLUE}Description:${NC}
  Login to ArgoCD CLI using port-forward.
  
  Required because OpenShift ArgoCD doesn't expose gRPC via route.

${BLUE}Options:${NC}
  --keep-alive   Keep port-forward running after login (background)

${BLUE}Examples:${NC}
  $0                 # Login and exit (port-forward stops)
  $0 --keep-alive    # Login and keep port-forward alive

${BLUE}What it does:${NC}
  1. Starts port-forward to ArgoCD server
  2. Gets admin password from secret
  3. Logs in to argocd CLI
  4. Optionally keeps port-forward running

${BLUE}Note:${NC}
  If you close the terminal, port-forward will stop.
  Run scripts in the same terminal session.
EOF
    exit 1
}

# Check prerequisites
if ! command -v argocd &> /dev/null; then
    error "argocd CLI not found"
    echo "Install: brew install argocd (macOS)" >&2
    exit 1
fi

if ! command -v oc &> /dev/null; then
    error "oc CLI not found"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    error "Not logged into OpenShift. Run: oc login"
    exit 1
fi

# Parse arguments
KEEP_ALIVE=false
if [[ $# -gt 0 ]]; then
    case $1 in
        --keep-alive) KEEP_ALIVE=true ;;
        --help|-h) usage ;;
        *) error "Unknown option: $1"; usage ;;
    esac
fi

# Check if port-forward already running
if lsof -Pi :8443 -sTCP:LISTEN -t >/dev/null 2>&1; then
    info "Port 8443 already in use (port-forward may be running)"
    info "Attempting login..."
else
    info "Starting port-forward to ArgoCD server..."
    oc port-forward -n openshift-gitops svc/openshift-gitops-server 8443:443 >/dev/null 2>&1 &
    PF_PID=$!
    
    # Wait for port-forward to be ready
    sleep 3
    
    if ! kill -0 $PF_PID 2>/dev/null; then
        error "Port-forward failed to start"
        exit 1
    fi
    
    success "Port-forward started (PID: $PF_PID)"
fi

# Get password
info "Retrieving admin password..."
PASSWORD=$(oc get secret -n openshift-gitops openshift-gitops-cluster -o jsonpath='{.data.admin\.password}' | base64 -d 2>/dev/null)

if [[ -z "${PASSWORD}" ]]; then
    error "Could not retrieve password"
    exit 1
fi

# Login
info "Logging in to ArgoCD..."
LOGIN_OUTPUT=$(argocd login localhost:8443 --username admin --password "${PASSWORD}" --insecure 2>&1)
if echo "${LOGIN_OUTPUT}" | grep -qi "logged in\|updated"; then
    success "Successfully logged in to ArgoCD!"
    
    # Test connection
    if argocd app list >/dev/null 2>&1; then
        success "ArgoCD CLI is working"
        
        # Show app count
        APP_COUNT=$(argocd app list -o name 2>/dev/null | wc -l)
        info "Found ${APP_COUNT} applications"
    else
        error "Login succeeded but cannot list apps"
    fi
else
    error "Login failed"
    exit 1
fi

# Handle keep-alive
if [[ "${KEEP_ALIVE}" == "true" ]]; then
    success "Port-forward running in background"
    info "To stop: kill $(pgrep -f 'port-forward.*openshift-gitops-server')"
    info "Scripts in this terminal session will work"
else
    if [[ -n "${PF_PID:-}" ]]; then
        info "Stopping port-forward..."
        kill $PF_PID 2>/dev/null || true
        info "Port-forward stopped. Run with --keep-alive to keep it running."
    fi
fi

echo ""
info "You can now use ArgoCD scripts:"
echo "  ./scripts/sync-status.sh"
echo "  ./scripts/sync-app.sh <app-name>"
echo "  ./scripts/diff-app.sh <app-name>"
