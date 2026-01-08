#!/bin/bash
# check-media-mounts.sh - Verify media mount status across all pods
#
# Usage: ./check-media-mounts.sh <namespace> [options]
#
# Options:
#   --verbose    Show detailed mount information
#   --json       Output in JSON format for automation
#   --help       Show this help message

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Options
VERBOSE=false
JSON_OUTPUT=false

# Functions
print_usage() {
    cat << EOF
Verify media mount status across all pods in namespace

Usage: $0 <namespace> [options]

Arguments:
  namespace    Kubernetes namespace (e.g., media-stack)

Options:
  --verbose    Show detailed mount information
  --json       Output in JSON format for automation
  --help       Show this help message

Examples:
  # Check all media-stack pods
  $0 media-stack

  # Verbose output
  $0 media-stack --verbose

  # JSON output for automation
  $0 media-stack --json

Mount Checks:
  1. /mnt/media/zurg/__all__ presence and readability
  2. /mnt/media/torbox/torrents presence and readability
  3. File count in each mount (healthy = >100 files)
  4. Node placement for debugging

Status Codes:
  OK     - Mount healthy (1000+ files visible)
  WARN   - Mount exists but few files (<100)
  FAIL   - Mount missing or not accessible
  SKIP   - Pod not running or no rclone sidecars
EOF
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

check_prerequisites() {
    if ! command -v oc &> /dev/null; then
        print_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi

    # Check if namespace exists
    if ! oc get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace not found: $NAMESPACE"
        exit 1
    fi
}

check_mount() {
    local pod="$1"
    local container="$2"
    local mount_path="$3"
    local expected_subdir="${4:-}"

    local full_path="$mount_path"
    if [[ -n "$expected_subdir" ]]; then
        full_path="$mount_path/$expected_subdir"
    fi

    # Check if mount exists and count files
    local result
    result=$(oc exec -n "$NAMESPACE" "$pod" -c "$container" -- \
        sh -c "if [ -d '$full_path' ]; then ls -A '$full_path' 2>/dev/null | wc -l; else echo 'NOTFOUND'; fi" 2>/dev/null || echo "ERROR")

    echo "$result"
}

check_pod_mounts() {
    local pod="$1"
    local main_container="$2"
    local node="$3"
    
    # Check zurg mount
    local zurg_status="SKIP"
    local zurg_files=0
    local zurg_check
    zurg_check=$(check_mount "$pod" "$main_container" "/mnt/media/zurg" "__all__")
    
    if [[ "$zurg_check" == "ERROR" || "$zurg_check" == "NOTFOUND" ]]; then
        zurg_status="FAIL"
    elif [[ "$zurg_check" =~ ^[0-9]+$ ]]; then
        zurg_files=$zurg_check
        if [[ $zurg_files -gt 1000 ]]; then
            zurg_status="OK"
        elif [[ $zurg_files -gt 100 ]]; then
            zurg_status="WARN"
        else
            zurg_status="FAIL"
        fi
    fi

    # Check torbox mount
    local torbox_status="SKIP"
    local torbox_files=0
    local torbox_check
    torbox_check=$(check_mount "$pod" "$main_container" "/mnt/media/torbox" "torrents")
    
    if [[ "$torbox_check" == "ERROR" || "$torbox_check" == "NOTFOUND" ]]; then
        torbox_status="FAIL"
    elif [[ "$torbox_check" =~ ^[0-9]+$ ]]; then
        torbox_files=$torbox_check
        if [[ $torbox_files -gt 10 ]]; then
            torbox_status="OK"
        elif [[ $torbox_files -gt 0 ]]; then
            torbox_status="WARN"
        else
            torbox_status="FAIL"
        fi
    fi

    # Verbose output
    if [[ "$VERBOSE" == true ]]; then
        echo "---"
        echo "Pod: $pod"
        echo "Container: $main_container"
        echo "Node: $node"
        echo "Zurg: $zurg_status ($zurg_files files in __all__)"
        echo "TorBox: $torbox_status ($torbox_files files in torrents)"
        
        # Check for rclone sidecars
        local sidecars
        sidecars=$(oc get pod -n "$NAMESPACE" "$pod" -o jsonpath='{.spec.containers[*].name}' | grep -o "rclone-[a-z]*" || echo "none")
        echo "Sidecars: $sidecars"
        echo ""
    fi

    # JSON output
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
{
  "pod": "$pod",
  "container": "$main_container",
  "node": "$node",
  "zurg": {
    "status": "$zurg_status",
    "files": $zurg_files,
    "path": "/mnt/media/zurg/__all__"
  },
  "torbox": {
    "status": "$torbox_status",
    "files": $torbox_files,
    "path": "/mnt/media/torbox/torrents"
  }
}
EOF
        return 0
    fi

    # Table output
    local zurg_display="$zurg_status"
    local torbox_display="$torbox_status"

    # Color code status
    case "$zurg_status" in
        OK)
            zurg_display="${GREEN}OK${NC} ($zurg_files files)"
            ;;
        WARN)
            zurg_display="${YELLOW}WARN${NC} ($zurg_files files)"
            ;;
        FAIL)
            zurg_display="${RED}FAIL${NC}"
            ;;
        SKIP)
            zurg_display="${CYAN}SKIP${NC}"
            ;;
    esac

    case "$torbox_status" in
        OK)
            torbox_display="${GREEN}OK${NC} ($torbox_files files)"
            ;;
        WARN)
            torbox_display="${YELLOW}WARN${NC} ($torbox_files files)"
            ;;
        FAIL)
            torbox_display="${RED}FAIL${NC}"
            ;;
        SKIP)
            torbox_display="${CYAN}SKIP${NC}"
            ;;
    esac

    printf "%-30s %-20s %-30s %-30s\n" "$pod" "$node" "$zurg_display" "$torbox_display"
}

check_all_pods() {
    local pods
    pods=$(oc get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.spec.nodeName}{" "}{.spec.containers[0].name}{"\n"}{end}')

    if [[ -z "$pods" ]]; then
        print_warning "No pods found in namespace: $NAMESPACE"
        exit 0
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "["
    else
        print_header "Media Mount Status Check - Namespace: $NAMESPACE"
        print_header "$(date)"
        echo ""
        printf "%-30s %-20s %-30s %-30s\n" "POD" "NODE" "ZURG MOUNT" "TORBOX MOUNT"
        printf "%-30s %-20s %-30s %-30s\n" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..20})" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..30})"
    fi

    local first=true
    while IFS= read -r line; do
        local pod phase node container
        read -r pod phase node container <<< "$line"

        # Skip non-running pods
        if [[ "$phase" != "Running" ]]; then
            continue
        fi

        # Skip if no node assigned
        if [[ -z "$node" || "$node" == "<none>" ]]; then
            continue
        fi

        if [[ "$JSON_OUTPUT" == true ]]; then
            [[ "$first" == false ]] && echo ","
            first=false
        fi

        check_pod_mounts "$pod" "$container" "$node"
    done <<< "$pods"

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo ""
        echo "]"
    else
        echo ""
        print_info "Legend:"
        print_info "  ${GREEN}OK${NC}   - Mount healthy (>1000 files for zurg, >10 for torbox)"
        print_info "  ${YELLOW}WARN${NC} - Mount exists but few files visible"
        print_info "  ${RED}FAIL${NC} - Mount missing or inaccessible"
        print_info "  ${CYAN}SKIP${NC} - Pod not applicable (no rclone sidecars)"
    fi
}

# Main execution
main() {
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 0
    fi

    # Check for help first
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        print_usage
        exit 0
    fi

    NAMESPACE="${1:-}"
    shift 2>/dev/null || true

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
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

    # Check prerequisites
    check_prerequisites

    # Check all pods
    check_all_pods
}

# Run main function
main "$@"
