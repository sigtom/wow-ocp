#!/bin/bash
set -euo pipefail

#############################################################################
# seal-secret.sh - Interactive Sealed Secret Creator for OpenShift Homelab
#
# Purpose: Create sealed secrets following the "Never Commit Raw Secrets" rule
# Author: Senior SRE (Gen X Edition)
# Version: 1.0
#
# Usage:
#   ./seal-secret.sh                    # Interactive mode
#   cat secret.yaml | ./seal-secret.sh --stdin   # Pipe mode
#   ./seal-secret.sh > sealed-secret.yaml        # Output to file
#############################################################################

# Colors for output (because we're not animals)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
CERT_PATH="${PROJECT_ROOT}/pub-sealed-secrets.pem"

# Error handling
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" >&2
}

info() {
    echo -e "${BLUE}INFO: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}" >&2
}

# Preflight checks
preflight_checks() {
    # Check for kubeseal
    if ! command -v kubeseal &> /dev/null; then
        error "kubeseal not found. Install it with: brew install kubeseal (macOS) or download from https://github.com/bitnami-labs/sealed-secrets/releases"
    fi

    # Check for kubectl/oc
    if ! command -v kubectl &> /dev/null && ! command -v oc &> /dev/null; then
        error "kubectl or oc not found. Install OpenShift CLI tools."
    fi

    # Check for certificate
    if [[ ! -f "${CERT_PATH}" ]]; then
        error "Public certificate not found at: ${CERT_PATH}\nRun from project root or specify --cert /path/to/cert"
    fi

    info "Preflight checks passed ✓"
}

# Validate Kubernetes name (RFC 1123 DNS subdomain)
validate_k8s_name() {
    local name="$1"
    if [[ ! "${name}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
        error "Invalid Kubernetes name: ${name}\nMust be lowercase alphanumeric with hyphens, start/end with alphanumeric"
    fi
}

# Interactive mode
interactive_mode() {
    info "=== Sealed Secret Creator ==="
    echo >&2

    # Get secret name
    read -rp "Secret name: " SECRET_NAME
    validate_k8s_name "${SECRET_NAME}"

    # Get namespace
    read -rp "Namespace: " NAMESPACE
    validate_k8s_name "${NAMESPACE}"

    # Get secret type
    echo -e "\nSecret type:" >&2
    echo "  1) Opaque (default - generic key-value)" >&2
    echo "  2) kubernetes.io/dockerconfigjson (Docker registry)" >&2
    echo "  3) kubernetes.io/tls (TLS cert/key)" >&2
    echo "  4) kubernetes.io/basic-auth (username/password)" >&2
    echo "  5) kubernetes.io/ssh-auth (SSH private key)" >&2
    read -rp "Select type [1]: " TYPE_CHOICE
    TYPE_CHOICE="${TYPE_CHOICE:-1}"

    case "${TYPE_CHOICE}" in
        1) SECRET_TYPE="Opaque" ;;
        2) SECRET_TYPE="kubernetes.io/dockerconfigjson" ;;
        3) SECRET_TYPE="kubernetes.io/tls" ;;
        4) SECRET_TYPE="kubernetes.io/basic-auth" ;;
        5) SECRET_TYPE="kubernetes.io/ssh-auth" ;;
        *) error "Invalid choice: ${TYPE_CHOICE}" ;;
    esac

    # Collect key-value pairs
    echo -e "\n${BLUE}Enter key-value pairs (press Enter with blank key to finish):${NC}" >&2
    declare -a KEYS
    declare -a VALUES

    while true; do
        read -rp "Key (or blank to finish): " KEY
        [[ -z "${KEY}" ]] && break

        # Validate key name
        if [[ ! "${KEY}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            warning "Invalid key name: ${KEY} (must be alphanumeric with ._- only). Try again."
            continue
        fi

        # Read value (hide input for sensitive data)
        read -rsp "Value for '${KEY}': " VALUE
        echo >&2

        if [[ -z "${VALUE}" ]]; then
            warning "Empty value for key '${KEY}'. Skipping."
            continue
        fi

        KEYS+=("${KEY}")
        VALUES+=("${VALUE}")
    done

    # Check if we have at least one key-value pair
    if [[ ${#KEYS[@]} -eq 0 ]]; then
        error "No key-value pairs provided. Aborting."
    fi

    info "Creating secret with ${#KEYS[@]} key(s)..."

    # Generate raw secret YAML
    generate_and_seal_secret "${SECRET_NAME}" "${NAMESPACE}" "${SECRET_TYPE}" KEYS VALUES
}

# Generate raw secret and seal it
generate_and_seal_secret() {
    local name="$1"
    local namespace="$2"
    local type="$3"
    local -n keys="$4"
    local -n values="$5"

    # Build stringData section
    local string_data=""
    for i in "${!keys[@]}"; do
        # Escape special characters in values for YAML
        local escaped_value="${values[$i]}"
        escaped_value="${escaped_value//\\/\\\\}"  # Escape backslashes
        escaped_value="${escaped_value//\"/\\\"}"  # Escape quotes
        string_data+="  ${keys[$i]}: \"${escaped_value}\"\n"
    done

    # Generate raw secret YAML (in memory, never written to disk)
    local raw_secret
    raw_secret=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${name}
  namespace: ${namespace}
type: ${type}
stringData:
$(echo -e "${string_data}")
EOF
)

    # Seal it with kubeseal
    info "Sealing secret with kubeseal..."
    local sealed_secret
    if ! sealed_secret=$(echo "${raw_secret}" | kubeseal --cert "${CERT_PATH}" --format yaml 2>&1); then
        error "kubeseal failed:\n${sealed_secret}"
    fi

    # Output sealed secret to stdout
    echo "${sealed_secret}"
    success "Sealed secret created successfully! Safe to commit to Git." >&2
}

# Stdin mode (pipe a raw secret manifest)
stdin_mode() {
    info "Reading raw secret from stdin..."

    # Read from stdin
    local raw_secret
    raw_secret=$(cat)

    if [[ -z "${raw_secret}" ]]; then
        error "No input received from stdin"
    fi

    # Seal it
    info "Sealing secret with kubeseal..."
    local sealed_secret
    if ! sealed_secret=$(echo "${raw_secret}" | kubeseal --cert "${CERT_PATH}" --format yaml 2>&1); then
        error "kubeseal failed:\n${sealed_secret}"
    fi

    # Output sealed secret to stdout
    echo "${sealed_secret}"
    success "Sealed secret created successfully! Safe to commit to Git." >&2
}

# Main
main() {
    # Parse arguments
    if [[ $# -eq 1 && "$1" == "--stdin" ]]; then
        preflight_checks
        stdin_mode
    elif [[ $# -eq 2 && "$1" == "--cert" ]]; then
        CERT_PATH="$2"
        preflight_checks
        interactive_mode
    elif [[ $# -eq 0 ]]; then
        preflight_checks
        interactive_mode
    else
        cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0                          # Interactive mode
  $0 --stdin                  # Pipe mode (cat secret.yaml | $0 --stdin)
  $0 --cert /path/to/cert.pem # Use custom certificate

${BLUE}Examples:${NC}
  # Interactive creation
  $0 > apps/myapp/overlays/prod/sealed-secret.yaml

  # Pipe existing secret
  cat raw-secret.yaml | $0 --stdin > sealed-secret.yaml

  # Use custom cert
  $0 --cert /path/to/pub-sealed-secrets.pem

${YELLOW}Remember: NEVER commit raw secrets to Git!${NC}
EOF
        exit 1
    fi
}

main "$@"
