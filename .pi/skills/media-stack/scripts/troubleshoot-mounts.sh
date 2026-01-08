#!/bin/bash
# troubleshoot-mounts.sh - Deep diagnostic for mount propagation issues
#
# Usage: ./troubleshoot-mounts.sh <pod-name> <namespace>

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_usage() {
    cat << EOF
Deep diagnostic for mount propagation issues

Usage: $0 <pod-name> <namespace>

Arguments:
  pod-name     Pod name (e.g., plex-abc123-xyz)
  namespace    Kubernetes namespace (e.g., media-stack)

Examples:
  # Troubleshoot plex pod
  $0 plex-6d8f9b7c8-xyz123 media-stack

  # Troubleshoot sonarr pod
  $0 sonarr-5b9c7d8-abc456 media-stack

Checks Performed:
  1. Pod status and node placement
  2. Container list and sidecar presence
  3. mountPropagation settings
  4. securityContext privileged flag
  5. /dev/fuse device accessibility
  6. Mount table from pod perspective
  7. Rclone sidecar logs
  8. Volume and secret configurations
  9. Node affinity/selector
  10. SCC binding
EOF
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

check_pod_status() {
    print_header "1. Pod Status"
    
    local status phase node
    status=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    node=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
    
    echo "Pod: $POD"
    echo "Namespace: $NAMESPACE"
    echo "Phase: $status"
    echo "Node: $node"
    
    if [[ "$status" != "Running" ]]; then
        print_warning "Pod not running (phase: $status)"
    else
        print_success "Pod is running"
    fi
}

check_containers() {
    print_header "2. Containers"
    
    local containers
    containers=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')
    
    echo "Containers in pod:"
    for container in $containers; do
        local ready
        ready=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].ready}")
        if [[ "$ready" == "true" ]]; then
            print_success "  - $container (ready)"
        else
            print_warning "  - $container (not ready)"
        fi
    done
    
    # Check for rclone sidecars
    echo ""
    if echo "$containers" | grep -q "rclone-zurg"; then
        print_success "rclone-zurg sidecar present"
    else
        print_warning "rclone-zurg sidecar MISSING"
    fi
    
    if echo "$containers" | grep -q "rclone-torbox"; then
        print_success "rclone-torbox sidecar present"
    else
        print_warning "rclone-torbox sidecar MISSING"
    fi
}

check_mount_propagation() {
    print_header "3. Mount Propagation Settings"
    
    local containers
    containers=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')
    
    for container in $containers; do
        echo ""
        echo "Container: $container"
        
        # Get volumeMounts
        local mounts
        mounts=$(oc get pod "$POD" -n "$NAMESPACE" -o json | \
            jq -r ".spec.containers[] | select(.name==\"$container\") | .volumeMounts[] | select(.mountPath==\"/mnt/media\") | .mountPropagation // \"None\"")
        
        if [[ -z "$mounts" ]]; then
            print_warning "  No /mnt/media mount found"
        else
            echo "  mountPropagation: $mounts"
            
            if [[ "$container" =~ ^rclone- ]]; then
                # Sidecar should have Bidirectional
                if [[ "$mounts" == "Bidirectional" ]]; then
                    print_success "  ✓ Correct (Bidirectional for sidecar)"
                else
                    print_error "  ✗ WRONG (should be Bidirectional for sidecar)"
                fi
            else
                # Main container should have HostToContainer
                if [[ "$mounts" == "HostToContainer" ]]; then
                    print_success "  ✓ Correct (HostToContainer for main app)"
                elif [[ "$mounts" == "None" ]]; then
                    print_error "  ✗ WRONG (should be HostToContainer, not None)"
                else
                    print_info "  ⚠ Unusual ($mounts)"
                fi
            fi
        fi
    done
}

check_security_context() {
    print_header "4. Security Context"
    
    local containers
    containers=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')
    
    for container in $containers; do
        echo ""
        echo "Container: $container"
        
        local privileged
        privileged=$(oc get pod "$POD" -n "$NAMESPACE" -o json | \
            jq -r ".spec.containers[] | select(.name==\"$container\") | .securityContext.privileged // false")
        
        echo "  privileged: $privileged"
        
        if [[ "$container" =~ ^rclone- ]]; then
            # Sidecar should be privileged
            if [[ "$privileged" == "true" ]]; then
                print_success "  ✓ Correct (privileged required for FUSE)"
            else
                print_error "  ✗ WRONG (rclone sidecar MUST be privileged for /dev/fuse access)"
            fi
        else
            # Main container doesn't need privileged
            if [[ "$privileged" == "true" ]]; then
                print_warning "  ⚠ Unnecessary (main app doesn't need privileged)"
            else
                print_success "  ✓ Good (principle of least privilege)"
            fi
        fi
    done
}

check_fuse_device() {
    print_header "5. FUSE Device Access"
    
    local containers
    containers=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')
    
    for container in $containers; do
        if [[ "$container" =~ ^rclone- ]]; then
            echo ""
            echo "Container: $container"
            
            local result
            result=$(oc exec -n "$NAMESPACE" "$POD" -c "$container" -- \
                sh -c "ls -l /dev/fuse 2>&1 || echo 'NOT FOUND'")
            
            if echo "$result" | grep -q "crw"; then
                print_success "  /dev/fuse accessible"
                echo "  $result"
            else
                print_error "  /dev/fuse NOT accessible"
                echo "  $result"
            fi
        fi
    done
}

check_mount_table() {
    print_header "6. Mount Table"
    
    # Get main container (first non-init container)
    local main_container
    main_container=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].name}')
    
    echo "Checking mounts from main container: $main_container"
    echo ""
    
    local mounts
    mounts=$(oc exec -n "$NAMESPACE" "$POD" -c "$main_container" -- \
        sh -c "mount | grep '/mnt/media' || echo 'No /mnt/media mounts found'")
    
    echo "$mounts"
    echo ""
    
    # Check if FUSE mounts present
    if echo "$mounts" | grep -q "fuse"; then
        print_success "FUSE mounts visible in main container"
    else
        print_warning "No FUSE mounts visible in main container"
        print_info "This indicates mount propagation issue"
    fi
}

check_sidecar_logs() {
    print_header "7. Rclone Sidecar Logs"
    
    # Check rclone-zurg logs
    echo ""
    echo "=== rclone-zurg logs (last 20 lines) ==="
    if oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' | grep -q "rclone-zurg"; then
        oc logs -n "$NAMESPACE" "$POD" -c rclone-zurg --tail=20 2>&1 || print_warning "Could not fetch logs"
    else
        print_warning "rclone-zurg container not found"
    fi
    
    # Check rclone-torbox logs
    echo ""
    echo "=== rclone-torbox logs (last 20 lines) ==="
    if oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' | grep -q "rclone-torbox"; then
        oc logs -n "$NAMESPACE" "$POD" -c rclone-torbox --tail=20 2>&1 || print_warning "Could not fetch logs"
    else
        print_warning "rclone-torbox container not found"
    fi
}

check_volumes() {
    print_header "8. Volumes and Secrets"
    
    echo "Volumes in pod:"
    oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[*].name}' | tr ' ' '\n' | while read -r vol; do
        echo "  - $vol"
    done
    
    echo ""
    
    # Check for required secrets
    local has_zurg has_torbox
    has_zurg=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[?(@.name=="rclone-zurg-config")].name}')
    has_torbox=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[?(@.name=="rclone-config")].name}')
    
    if [[ -n "$has_zurg" ]]; then
        print_success "rclone-zurg-config volume present"
    else
        print_warning "rclone-zurg-config volume MISSING"
    fi
    
    if [[ -n "$has_torbox" ]]; then
        print_success "rclone-config volume present"
    else
        print_warning "rclone-config volume MISSING"
    fi
}

check_node_affinity() {
    print_header "9. Node Affinity/Selector"
    
    local deployment
    deployment=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app}')
    
    if [[ -z "$deployment" ]]; then
        print_warning "Could not determine deployment from pod labels"
        return
    fi
    
    # Check nodeSelector
    local node_selector
    node_selector=$(oc get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.nodeSelector}')
    
    if [[ -n "$node_selector" && "$node_selector" != "{}" ]]; then
        print_warning "Hard nodeSelector found (consider using nodeAffinity instead)"
        echo "$node_selector"
    else
        print_success "No hard nodeSelector (good)"
    fi
    
    # Check nodeAffinity
    echo ""
    local affinity
    affinity=$(oc get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.affinity.nodeAffinity}')
    
    if [[ -n "$affinity" && "$affinity" != "{}" ]]; then
        echo "NodeAffinity:"
        echo "$affinity" | jq '.' 2>/dev/null || echo "$affinity"
    else
        print_info "No nodeAffinity set"
    fi
}

check_scc() {
    print_header "10. SCC Binding"
    
    local sa
    sa=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.serviceAccountName}')
    
    if [[ -z "$sa" || "$sa" == "null" ]]; then
        sa="default"
    fi
    
    echo "ServiceAccount: $sa"
    echo ""
    
    # Check if SA has privileged SCC
    if oc get scc privileged -o yaml | grep -q "system:serviceaccount:$NAMESPACE:$sa"; then
        print_success "ServiceAccount has privileged SCC binding"
    else
        print_error "ServiceAccount MISSING privileged SCC binding"
        print_info "Run: oc adm policy add-scc-to-user privileged -z $sa -n $NAMESPACE"
    fi
}

generate_summary() {
    print_header "SUMMARY & RECOMMENDATIONS"
    
    echo "Common Issues & Fixes:"
    echo ""
    echo "1. Mounts not visible in main container:"
    echo "   → Add mountPropagation: Bidirectional to sidecars"
    echo "   → Add mountPropagation: HostToContainer to main container"
    echo ""
    echo "2. Rclone sidecar crashes:"
    echo "   → Add privileged: true to sidecar securityContext"
    echo "   → Ensure ServiceAccount has privileged SCC binding"
    echo ""
    echo "3. /dev/fuse not accessible:"
    echo "   → Add privileged: true to sidecar securityContext"
    echo "   → Verify SCC binding"
    echo ""
    echo "4. Pod scheduled on wrong node:"
    echo "   → Add nodeAffinity with preferredDuringSchedulingIgnoredDuringExecution"
    echo "   → Avoid hard nodeSelector"
    echo ""
    echo "Next Steps:"
    echo "  1. Review output above for issues marked with ✗ or ⚠"
    echo "  2. Update deployment manifest in Git"
    echo "  3. Commit and sync via ArgoCD"
    echo "  4. Verify with: .pi/skills/media-stack/scripts/check-media-mounts.sh $NAMESPACE"
}

# Main execution
main() {
    if [[ $# -ne 2 ]]; then
        print_usage
        exit 1
    fi

    POD="$1"
    NAMESPACE="$2"

    # Check prerequisites
    if ! command -v oc &> /dev/null; then
        print_error "oc CLI not found"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        print_error "jq not found (required for JSON parsing)"
        exit 1
    fi

    # Check if pod exists
    if ! oc get pod "$POD" -n "$NAMESPACE" &> /dev/null; then
        print_error "Pod not found: $POD in namespace $NAMESPACE"
        exit 1
    fi

    # Run all checks
    check_pod_status
    check_containers
    check_mount_propagation
    check_security_context
    check_fuse_device
    check_mount_table
    check_sidecar_logs
    check_volumes
    check_node_affinity
    check_scc
    generate_summary
}

main "$@"
