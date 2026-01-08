#!/bin/bash
# Check ArgoCD application sync status

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# Check prerequisites
if ! command -v argocd &> /dev/null; then
    echo -e "${RED}ERROR: 'argocd' CLI not found${NC}" >&2
    echo "Install from: https://argo-cd.readthedocs.io/en/stable/cli_installation/" >&2
    exit 1
fi

# Check if logged in
if ! argocd version --client &>/dev/null; then
    echo -e "${RED}ERROR: Not logged into ArgoCD${NC}" >&2
    echo "Login with: argocd login argocd.apps.wow.sigtomtech.com" >&2
    exit 1
fi

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}${BOLD}                 ArgoCD Application Sync Status                     ${NC}${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get all applications
APPS=$(argocd app list -o name 2>/dev/null)

if [[ -z "$APPS" ]]; then
    echo -e "${YELLOW}No ArgoCD applications found${NC}"
    exit 0
fi

TOTAL=0
SYNCED=0
OUTOFSYNCED=0
HEALTHY=0
DEGRADED=0
PROGRESSING=0

# Check each app
while IFS= read -r app; do
    ((TOTAL++))
    
    # Get app status
    STATUS=$(argocd app get "$app" --show-operation 2>/dev/null)
    SYNC_STATUS=$(echo "$STATUS" | grep "Sync Status:" | awk '{print $3}')
    HEALTH_STATUS=$(echo "$STATUS" | grep "Health Status:" | awk '{print $3}')
    
    # Determine sync color
    case "$SYNC_STATUS" in
        Synced)
            SYNC_COLOR="$GREEN"
            ((SYNCED++))
            ;;
        OutOfSync)
            SYNC_COLOR="$YELLOW"
            ((OUTOFSYNCED++))
            ;;
        *)
            SYNC_COLOR="$RED"
            ;;
    esac
    
    # Determine health color
    case "$HEALTH_STATUS" in
        Healthy)
            HEALTH_COLOR="$GREEN"
            ((HEALTHY++))
            ;;
        Degraded)
            HEALTH_COLOR="$RED"
            ((DEGRADED++))
            ;;
        Progressing|Suspended)
            HEALTH_COLOR="$YELLOW"
            ((PROGRESSING++))
            ;;
        *)
            HEALTH_COLOR="$NC"
            ;;
    esac
    
    # Print status
    printf "%-30s ${SYNC_COLOR}%-12s${NC} ${HEALTH_COLOR}%-12s${NC}\n" \
        "$app" "$SYNC_STATUS" "$HEALTH_STATUS"
done <<< "$APPS"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}Summary:${NC}"
echo "  Total Applications: $TOTAL"
echo -e "  ${GREEN}Synced:${NC} $SYNCED"
echo -e "  ${YELLOW}OutOfSync:${NC} $OUTOFSYNCED"
echo -e "  ${GREEN}Healthy:${NC} $HEALTHY"
echo -e "  ${RED}Degraded:${NC} $DEGRADED"
echo -e "  ${YELLOW}Progressing:${NC} $PROGRESSING"
echo ""

# Recommendations
if [[ $OUTOFSYNCED -gt 0 ]]; then
    echo -e "${YELLOW}⚠ $OUTOFSYNCED application(s) out of sync${NC}"
    echo "  Sync manually: argocd app sync <app-name>"
    echo "  Check diff: argocd app diff <app-name>"
    echo ""
fi

if [[ $DEGRADED -gt 0 ]]; then
    echo -e "${RED}⚠ $DEGRADED application(s) degraded${NC}"
    echo "  Check status: argocd app get <app-name>"
    echo "  View resources: oc get all -n <namespace>"
    echo "  Check logs: oc logs -n <namespace> <pod>"
    echo ""
fi

# Exit code
if [[ $DEGRADED -gt 0 ]]; then
    exit 2
elif [[ $OUTOFSYNCED -gt 0 ]]; then
    exit 1
else
    echo -e "${GREEN}✓ All applications synced and healthy${NC}"
    exit 0
fi
