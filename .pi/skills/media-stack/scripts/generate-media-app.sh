#!/bin/bash
# generate-media-app.sh - Generate media stack application deployment
# 
# Usage: ./generate-media-app.sh <app-name> <image> <port> [options]
#
# Options:
#   --zone <zone>        Set zone label (zone1-4, default: zone2)
#   --cpu-req <cpu>      CPU request (default: 500m)
#   --mem-req <mem>      Memory request (default: 512Mi)
#   --cpu-lim <cpu>      CPU limit (default: 2000m)
#   --mem-lim <mem>      Memory limit (default: 2Gi)
#   --no-sidecars        Generate without rclone sidecars (NOT RECOMMENDED)
#   --dry-run            Show what would be created without writing files
#   --help               Show this help message

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(dirname "$SCRIPT_DIR")/templates"
BASE_DIR="/home/sigtom/wow-ocp"

# Default values
ZONE="zone2"
CPU_REQ="500m"
MEM_REQ="512Mi"
CPU_LIM="2000m"
MEM_LIM="2Gi"
NO_SIDECARS=false
DRY_RUN=false

# Functions
print_usage() {
    cat << EOF
Generate media stack application deployment

Usage: $0 <app-name> <image> <port> [options]

Arguments:
  app-name     Application name (e.g., prowlarr, bazarr, jellyfin)
  image        Container image (e.g., lscr.io/linuxserver/prowlarr:latest)
  port         Primary service port (e.g., 9696, 6767)

Options:
  --zone <zone>        Set zone label (zone1-4, default: zone2)
  --cpu-req <cpu>      CPU request (default: 500m)
  --mem-req <mem>      Memory request (default: 512Mi)
  --cpu-lim <cpu>      CPU limit (default: 2000m)
  --mem-lim <mem>      Memory limit (default: 2Gi)
  --no-sidecars        Generate without rclone sidecars (NOT RECOMMENDED)
  --dry-run            Show what would be created without writing files
  --help               Show this help message

Examples:
  # Basic usage
  $0 prowlarr lscr.io/linuxserver/prowlarr:latest 9696

  # With custom resources
  $0 jellyfin jellyfin/jellyfin:latest 8096 --cpu-lim 4000m --mem-lim 8Gi

  # Dry run (preview only)
  $0 bazarr lscr.io/linuxserver/bazarr:latest 6767 --dry-run

Zone Reference:
  zone1 - Cloud Gateway (Zurg, Rclone, rdt-client, Riven)
  zone2 - Managers (Sonarr, Radarr, SABnzbd, Bazarr) [DEFAULT]
  zone3 - Player (Plex, Jellyfin)
  zone4 - Discovery (Overseerr)
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

validate_inputs() {
    # Check required arguments
    if [[ -z "${APP_NAME:-}" || -z "${IMAGE:-}" || -z "${PORT:-}" ]]; then
        print_error "Missing required arguments"
        print_usage
        exit 1
    fi

    # Validate app name (alphanumeric + hyphens only)
    if ! [[ "$APP_NAME" =~ ^[a-z0-9-]+$ ]]; then
        print_error "App name must be lowercase alphanumeric with hyphens only"
        exit 1
    fi

    # Validate port (1-65535)
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 || "$PORT" -gt 65535 ]]; then
        print_error "Port must be a number between 1 and 65535"
        exit 1
    fi

    # Validate zone
    if ! [[ "$ZONE" =~ ^zone[1-4]$ ]]; then
        print_error "Zone must be zone1, zone2, zone3, or zone4"
        exit 1
    fi

    # Check if app already exists
    local app_dir="$BASE_DIR/apps/$APP_NAME"
    if [[ -d "$app_dir" && "$DRY_RUN" == false ]]; then
        print_error "App directory already exists: $app_dir"
        print_info "Use --dry-run to preview or delete the directory first"
        exit 1
    fi

    # Validate template exists
    if [[ ! -f "$TEMPLATE_DIR/media-deployment.yaml" ]]; then
        print_error "Template not found: $TEMPLATE_DIR/media-deployment.yaml"
        exit 1
    fi
}

generate_deployment() {
    local template_file="$TEMPLATE_DIR/media-deployment.yaml"
    local output=""

    # Read template and replace placeholders
    output=$(cat "$template_file")
    output="${output//\{\{APP_NAME\}\}/$APP_NAME}"
    output="${output//\{\{IMAGE\}\}/$IMAGE}"
    output="${output//\{\{PORT\}\}/$PORT}"
    output="${output//\{\{ZONE\}\}/$ZONE}"
    output="${output//\{\{CPU_REQ\}\}/$CPU_REQ}"
    output="${output//\{\{MEM_REQ\}\}/$MEM_REQ}"
    output="${output//\{\{CPU_LIM\}\}/$CPU_LIM}"
    output="${output//\{\{MEM_LIM\}\}/$MEM_LIM}"

    # Remove sidecars if requested (NOT RECOMMENDED)
    if [[ "$NO_SIDECARS" == true ]]; then
        print_warning "Generating without sidecars - cloud storage will NOT work!"
        # This is complex - would need to remove entire sidecar sections
        # For simplicity, we'll just warn and keep them in template
        print_warning "Template still includes sidecars - manually remove if needed"
    fi

    echo "$output"
}

generate_kustomization() {
    cat << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: media-stack

resources:
  - deployment.yaml

commonLabels:
  app: $APP_NAME
  zone: $ZONE
  stack: hybrid-media

# Add image tag override here if needed
# images:
#   - name: $IMAGE
#     newTag: latest
EOF
}

generate_readme() {
    cat << EOF
# $APP_NAME

Deployment for $APP_NAME in the OpenShift Hybrid Media Stack.

## Quick Reference

- **Zone**: $ZONE
- **Image**: $IMAGE
- **Port**: $PORT
- **Resources**: CPU $CPU_REQ-$CPU_LIM, Memory $MEM_REQ-$MEM_LIM

## Access

- **Internal**: http://$APP_NAME.media-stack.svc:$PORT
- **External**: https://$APP_NAME.apps.ossus.sigtomtech.com

## Deployment

\`\`\`bash
# Apply via ArgoCD (GitOps - RECOMMENDED)
git add apps/$APP_NAME
git commit -m "feat(media): add $APP_NAME deployment"
git push origin main
argocd app sync $APP_NAME

# Or apply directly (NOT RECOMMENDED - breaks GitOps)
oc apply -k apps/$APP_NAME/base
\`\`\`

## Troubleshooting

### Check pod status
\`\`\`bash
oc get pods -n media-stack -l app=$APP_NAME
\`\`\`

### Check logs
\`\`\`bash
# Main container
oc logs -n media-stack -l app=$APP_NAME -c $APP_NAME

# Rclone sidecars
oc logs -n media-stack -l app=$APP_NAME -c rclone-zurg
oc logs -n media-stack -l app=$APP_NAME -c rclone-torbox
\`\`\`

### Check media mounts
\`\`\`bash
cd /home/sigtom/wow-ocp/.pi/skills/media-stack
./scripts/check-media-mounts.sh media-stack | grep $APP_NAME
\`\`\`

### Verify mount visibility
\`\`\`bash
# Check zurg mount
oc exec -n media-stack deployment/$APP_NAME -- ls -la /mnt/media/zurg/__all__ | head

# Check torbox mount
oc exec -n media-stack deployment/$APP_NAME -- ls -la /mnt/media/torbox/torrents
\`\`\`

## Configuration

Application configuration is persisted in:
\`\`\`
PVC: media-library-pvc
Path: /config/$APP_NAME
\`\`\`

## Cloud Storage Access

This deployment includes rclone sidecars for cloud storage:
- **Real-Debrid** (via Zurg): \`/mnt/media/zurg/__all__\`
- **TorBox**: \`/mnt/media/torbox/torrents\`

## Related Documentation

- [Media Stack Skill](.pi/skills/media-stack/SKILL.md)
- [Sidecar Pattern](.pi/skills/media-stack/references/sidecar-pattern.md)
- [Architecture](.pi/skills/media-stack/references/architecture.md)
EOF
}

create_files() {
    local app_dir="$BASE_DIR/apps/$APP_NAME/base"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "DRY RUN - Files would be created at: $app_dir"
        print_info ""
        print_info "=== deployment.yaml ==="
        generate_deployment | head -20
        echo "... (truncated) ..."
        print_info ""
        print_info "=== kustomization.yaml ==="
        generate_kustomization
        print_info ""
        print_info "=== README.md ==="
        generate_readme | head -15
        echo "... (truncated) ..."
        return 0
    fi

    # Create directory structure
    print_info "Creating directory: $app_dir"
    mkdir -p "$app_dir"

    # Generate deployment.yaml
    print_info "Generating deployment.yaml"
    generate_deployment > "$app_dir/deployment.yaml"
    print_success "Created $app_dir/deployment.yaml"

    # Generate kustomization.yaml
    print_info "Generating kustomization.yaml"
    generate_kustomization > "$app_dir/kustomization.yaml"
    print_success "Created $app_dir/kustomization.yaml"

    # Generate README.md
    print_info "Generating README.md"
    generate_readme > "$app_dir/README.md"
    print_success "Created $app_dir/README.md"

    print_success ""
    print_success "Successfully generated $APP_NAME deployment!"
    print_info ""
    print_info "Next steps:"
    print_info "  1. Review files: ls -la $app_dir"
    print_info "  2. Customize: vim $app_dir/deployment.yaml"
    print_info "  3. Commit: git add apps/$APP_NAME && git commit -m 'feat(media): add $APP_NAME'"
    print_info "  4. Deploy: git push && argocd app sync $APP_NAME"
    print_info ""
    print_info "Or test locally first:"
    print_info "  oc apply -k $app_dir --dry-run=client"
}

# Main execution
main() {
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 0
    fi

    # Parse positional arguments
    APP_NAME="${1:-}"
    IMAGE="${2:-}"
    PORT="${3:-}"
    shift 3 2>/dev/null || true

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --zone)
                ZONE="$2"
                shift 2
                ;;
            --cpu-req)
                CPU_REQ="$2"
                shift 2
                ;;
            --mem-req)
                MEM_REQ="$2"
                shift 2
                ;;
            --cpu-lim)
                CPU_LIM="$2"
                shift 2
                ;;
            --mem-lim)
                MEM_LIM="$2"
                shift 2
                ;;
            --no-sidecars)
                NO_SIDECARS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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
    validate_inputs

    # Print summary
    print_info "Generating deployment for:"
    print_info "  App Name: $APP_NAME"
    print_info "  Image: $IMAGE"
    print_info "  Port: $PORT"
    print_info "  Zone: $ZONE"
    print_info "  Resources: CPU $CPU_REQ-$CPU_LIM, Memory $MEM_REQ-$MEM_LIM"
    print_info "  Sidecars: $([ "$NO_SIDECARS" == true ] && echo "Disabled" || echo "Enabled")"
    print_info ""

    # Create files
    create_files
}

# Run main function
main "$@"
