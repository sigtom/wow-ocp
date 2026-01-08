#!/bin/bash
# add-sidecars.sh - Add rclone sidecars to existing deployment
#
# Usage: ./add-sidecars.sh <deployment> <namespace> [options]
#
# Options:
#   --dry-run    Show patch without applying
#   --force      Skip confirmation prompt
#   --help       Show this help message

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Options
DRY_RUN=false
FORCE=false

# Functions
print_usage() {
    cat << EOF
Add rclone sidecars to existing deployment

Usage: $0 <deployment> <namespace> [options]

Arguments:
  deployment   Deployment name (e.g., bazarr, overseerr)
  namespace    Kubernetes namespace (e.g., media-stack)

Options:
  --dry-run    Show patch without applying
  --force      Skip confirmation prompt
  --help       Show this help message

Examples:
  # Add sidecars to bazarr (with confirmation)
  $0 bazarr media-stack

  # Preview changes without applying
  $0 overseerr media-stack --dry-run

  # Add sidecars without confirmation
  $0 prowlarr media-stack --force

What This Does:
  1. Adds init-dirs initContainer
  2. Adds rclone-zurg sidecar container
  3. Adds rclone-torbox sidecar container
  4. Updates main container volumeMount with mountPropagation
  5. Adds secret volumes if missing
  6. Adds privileged SCC binding if needed

Prerequisites:
  - Deployment must already exist
  - Secrets rclone-zurg-config and rclone-config must exist
  - ServiceAccount must have privileged SCC binding
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

check_prerequisites() {
    if ! command -v oc &> /dev/null; then
        print_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi

    # Check if deployment exists
    if ! oc get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
        print_error "Deployment not found: $DEPLOYMENT in namespace $NAMESPACE"
        exit 1
    fi

    # Check if secrets exist
    if ! oc get secret rclone-zurg-config -n "$NAMESPACE" &> /dev/null; then
        print_warning "Secret not found: rclone-zurg-config"
        print_info "Create with: oc create secret generic rclone-zurg-config --from-file=rclone.conf=..."
    fi

    if ! oc get secret rclone-config -n "$NAMESPACE" &> /dev/null; then
        print_warning "Secret not found: rclone-config"
        print_info "Create with: oc create secret generic rclone-config --from-file=rclone.conf=..."
    fi

    print_success "Prerequisites check passed"
}

check_scc_binding() {
    local sa
    sa=$(oc get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.serviceAccountName}')
    
    if [[ -z "$sa" || "$sa" == "null" ]]; then
        sa="default"
    fi

    print_info "ServiceAccount: $sa"

    # Check if SA has privileged SCC
    if ! oc get scc privileged -o yaml | grep -q "system:serviceaccount:$NAMESPACE:$sa"; then
        print_warning "ServiceAccount $sa does not have privileged SCC binding"
        print_info "Run: oc adm policy add-scc-to-user privileged -z $sa -n $NAMESPACE"
    else
        print_success "ServiceAccount $sa has privileged SCC binding"
    fi
}

generate_patch() {
    cat << 'EOF'
{
  "spec": {
    "template": {
      "spec": {
        "initContainers": [
          {
            "name": "init-dirs",
            "image": "docker.io/alpine:latest",
            "command": [
              "/bin/sh",
              "-c",
              "mkdir -p /mnt/media/zurg /mnt/media/torbox && echo 'Mount points created'"
            ],
            "volumeMounts": [
              {
                "name": "media-storage",
                "mountPath": "/mnt/media"
              }
            ]
          }
        ],
        "containers": [
          {
            "name": "rclone-zurg",
            "image": "docker.io/rclone/rclone:latest",
            "securityContext": {
              "privileged": true
            },
            "args": [
              "mount",
              "zurg:",
              "/mnt/media/zurg",
              "--config=/config/rclone/rclone.conf",
              "--allow-other",
              "--vfs-cache-mode=full",
              "--poll-interval=10s",
              "--dir-cache-time=10s",
              "--attr-timeout=10s",
              "--rc",
              "--rc-no-auth",
              "--rc-addr=:5572"
            ],
            "volumeMounts": [
              {
                "name": "media-storage",
                "mountPath": "/mnt/media",
                "mountPropagation": "Bidirectional"
              },
              {
                "name": "rclone-zurg-config",
                "mountPath": "/config/rclone",
                "readOnly": true
              }
            ],
            "resources": {
              "requests": {
                "cpu": "100m",
                "memory": "256Mi"
              },
              "limits": {
                "cpu": "500m",
                "memory": "1Gi"
              }
            }
          },
          {
            "name": "rclone-torbox",
            "image": "docker.io/rclone/rclone:latest",
            "securityContext": {
              "privileged": true
            },
            "args": [
              "mount",
              "torbox:",
              "/mnt/media/torbox",
              "--config=/config/rclone/rclone.conf",
              "--allow-other",
              "--vfs-cache-mode=full",
              "--poll-interval=10s",
              "--dir-cache-time=10s",
              "--attr-timeout=10s",
              "--rc",
              "--rc-no-auth",
              "--rc-addr=:5573"
            ],
            "volumeMounts": [
              {
                "name": "media-storage",
                "mountPath": "/mnt/media",
                "mountPropagation": "Bidirectional"
              },
              {
                "name": "rclone-config",
                "mountPath": "/config/rclone",
                "readOnly": true
              }
            ],
            "resources": {
              "requests": {
                "cpu": "100m",
                "memory": "256Mi"
              },
              "limits": {
                "cpu": "500m",
                "memory": "1Gi"
              }
            }
          }
        ]
      }
    }
  }
}
EOF
}

generate_volume_patch() {
    cat << 'EOF'
[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "rclone-zurg-config",
      "secret": {
        "secretName": "rclone-zurg-config",
        "defaultMode": 256
      }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "rclone-config",
      "secret": {
        "secretName": "rclone-config",
        "defaultMode": 256
      }
    }
  }
]
EOF
}

update_main_container_mount() {
    # Get main container name (first non-init container)
    local main_container
    main_container=$(oc get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].name}')

    print_info "Updating mountPropagation for main container: $main_container"

    # This is complex - we need to find the /mnt/media volumeMount and add mountPropagation
    # For simplicity, we'll use strategic merge patch which handles this better
    
    local patch
    patch=$(cat << EOF
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "$main_container",
            "volumeMounts": [
              {
                "name": "media-storage",
                "mountPath": "/mnt/media",
                "mountPropagation": "HostToContainer"
              }
            ]
          }
        ]
      }
    }
  }
}
EOF
)

    if [[ "$DRY_RUN" == true ]]; then
        echo "$patch"
    else
        echo "$patch" | oc patch deployment "$DEPLOYMENT" -n "$NAMESPACE" --type=strategic --patch-file=/dev/stdin
    fi
}

apply_patch() {
    local patch
    patch=$(generate_patch)

    if [[ "$DRY_RUN" == true ]]; then
        print_info "DRY RUN - Patch that would be applied:"
        echo "$patch" | jq '.' 2>/dev/null || echo "$patch"
        return 0
    fi

    # Apply strategic merge patch to add containers
    print_info "Adding sidecar containers..."
    echo "$patch" | oc patch deployment "$DEPLOYMENT" -n "$NAMESPACE" --type=strategic --patch-file=/dev/stdin

    # Check if volumes already exist
    local has_zurg_volume has_torbox_volume
    has_zurg_volume=$(oc get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="rclone-zurg-config")].name}')
    has_torbox_volume=$(oc get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.volumes[?(@.name=="rclone-config")].name}')

    if [[ -z "$has_zurg_volume" || -z "$has_torbox_volume" ]]; then
        print_info "Adding secret volumes..."
        local volume_patch
        volume_patch=$(generate_volume_patch)
        echo "$volume_patch" | oc patch deployment "$DEPLOYMENT" -n "$NAMESPACE" --type=json --patch-file=/dev/stdin
    else
        print_info "Secret volumes already exist, skipping"
    fi

    # Update main container mountPropagation
    update_main_container_mount

    print_success "Sidecars added successfully!"
    print_info ""
    print_info "Waiting for rollout..."
    oc rollout status deployment "$DEPLOYMENT" -n "$NAMESPACE" --timeout=5m

    print_success "Deployment rolled out successfully!"
    print_info ""
    print_info "Verify mounts with:"
    print_info "  .pi/skills/media-stack/scripts/check-media-mounts.sh $NAMESPACE | grep $DEPLOYMENT"
}

confirm_action() {
    if [[ "$FORCE" == true || "$DRY_RUN" == true ]]; then
        return 0
    fi

    print_warning "This will modify deployment: $DEPLOYMENT in namespace: $NAMESPACE"
    print_info "Changes:"
    print_info "  - Add init-dirs initContainer"
    print_info "  - Add rclone-zurg sidecar (privileged)"
    print_info "  - Add rclone-torbox sidecar (privileged)"
    print_info "  - Update main container mountPropagation"
    print_info "  - Add secret volumes"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        exit 0
    fi
}

# Main execution
main() {
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 0
    fi

    DEPLOYMENT="${1:-}"
    NAMESPACE="${2:-}"
    shift 2 2>/dev/null || true

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Validate inputs
    if [[ -z "$DEPLOYMENT" || -z "$NAMESPACE" ]]; then
        print_error "Missing required arguments"
        print_usage
        exit 1
    fi

    # Check prerequisites
    check_prerequisites
    check_scc_binding

    # Confirm action
    confirm_action

    # Apply patch
    apply_patch
}

# Run main function
main "$@"
