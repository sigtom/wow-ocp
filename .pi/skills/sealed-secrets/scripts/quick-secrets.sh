#!/bin/bash
set -euo pipefail

#############################################################################
# quick-secrets.sh - Quick Secret Generators for Common Use Cases
#
# Purpose: Generate common secret types quickly without manual YAML writing
# Author: Senior SRE (Gen X Edition)
# Version: 1.0
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEAL_SCRIPT="${SCRIPT_DIR}/seal-secret.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}$1${NC}" >&2
}

success() {
    echo -e "${GREEN}$1${NC}" >&2
}

error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Docker Hub credentials secret
docker_secret() {
    local name="${1:-dockerhub-creds}"
    local namespace="${2:-default}"
    
    info "Creating Docker Hub credentials secret"
    read -rp "Docker Hub Username: " username
    read -rsp "Docker Hub Password: " password
    echo >&2
    read -rp "Email (optional): " email
    
    # Generate docker config JSON
    local auth=$(echo -n "${username}:${password}" | base64 -w 0 2>/dev/null || echo -n "${username}:${password}" | base64)
    local dockerconfig=$(cat <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "username": "${username}",
      "password": "${password}",
      "email": "${email:-}",
      "auth": "${auth}"
    }
  }
}
EOF
)
    
    # Create and seal
    kubectl create secret docker-registry "${name}" \
        --docker-server=https://index.docker.io/v1/ \
        --docker-username="${username}" \
        --docker-password="${password}" \
        --docker-email="${email:-}" \
        --namespace="${namespace}" \
        --dry-run=client -o yaml | \
        "${SEAL_SCRIPT}" --stdin
    
    success "Docker secret sealed successfully!"
}

# TLS certificate secret
tls_secret() {
    local name="${1:-tls-cert}"
    local namespace="${2:-default}"
    
    info "Creating TLS certificate secret"
    read -rp "Path to certificate file (tls.crt): " cert_path
    read -rp "Path to private key file (tls.key): " key_path
    
    if [[ ! -f "${cert_path}" ]]; then
        error "Certificate file not found: ${cert_path}"
    fi
    
    if [[ ! -f "${key_path}" ]]; then
        error "Key file not found: ${key_path}"
    fi
    
    kubectl create secret tls "${name}" \
        --cert="${cert_path}" \
        --key="${key_path}" \
        --namespace="${namespace}" \
        --dry-run=client -o yaml | \
        "${SEAL_SCRIPT}" --stdin
    
    success "TLS secret sealed successfully!"
}

# Basic auth secret
basicauth_secret() {
    local name="${1:-basic-auth}"
    local namespace="${2:-default}"
    
    info "Creating basic auth secret"
    read -rp "Username: " username
    read -rsp "Password: " password
    echo >&2
    
    kubectl create secret generic "${name}" \
        --from-literal=username="${username}" \
        --from-literal=password="${password}" \
        --namespace="${namespace}" \
        --dry-run=client -o yaml | \
        "${SEAL_SCRIPT}" --stdin
    
    success "Basic auth secret sealed successfully!"
}

# SSH key secret
ssh_secret() {
    local name="${1:-ssh-key}"
    local namespace="${2:-default}"
    
    info "Creating SSH key secret"
    read -rp "Path to SSH private key: " key_path
    
    if [[ ! -f "${key_path}" ]]; then
        error "SSH key file not found: ${key_path}"
    fi
    
    kubectl create secret generic "${name}" \
        --from-file=ssh-privatekey="${key_path}" \
        --namespace="${namespace}" \
        --type=kubernetes.io/ssh-auth \
        --dry-run=client -o yaml | \
        "${SEAL_SCRIPT}" --stdin
    
    success "SSH key secret sealed successfully!"
}

# Generic secret from file
file_secret() {
    local name="${1:-file-secret}"
    local namespace="${2:-default}"
    
    info "Creating secret from file(s)"
    read -rp "Path to file (or directory): " file_path
    
    if [[ ! -e "${file_path}" ]]; then
        error "File or directory not found: ${file_path}"
    fi
    
    if [[ -d "${file_path}" ]]; then
        kubectl create secret generic "${name}" \
            --from-file="${file_path}" \
            --namespace="${namespace}" \
            --dry-run=client -o yaml | \
            "${SEAL_SCRIPT}" --stdin
    else
        read -rp "Key name (default: filename): " key_name
        key_name="${key_name:-$(basename "${file_path}")}"
        
        kubectl create secret generic "${name}" \
            --from-file="${key_name}=${file_path}" \
            --namespace="${namespace}" \
            --dry-run=client -o yaml | \
            "${SEAL_SCRIPT}" --stdin
    fi
    
    success "File secret sealed successfully!"
}

# Usage
usage() {
    cat >&2 <<EOF
${BLUE}Quick Secret Generators${NC}

Usage: $0 <type> [name] [namespace]

Types:
  docker      - Docker Hub registry credentials
  tls         - TLS certificate and key
  basicauth   - Username and password
  ssh         - SSH private key
  file        - Secret from file(s)

Examples:
  $0 docker dockerhub-creds media
  $0 tls my-tls-cert default
  $0 basicauth admin-creds default
  $0 ssh github-key ci-cd
  $0 file app-config myapp

Output is sealed and safe to commit to Git.
Redirect to a file: $0 docker > sealed-dockerhub.yaml
EOF
    exit 1
}

# Main
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi
    
    local type="$1"
    local name="${2:-}"
    local namespace="${3:-}"
    
    case "${type}" in
        docker)
            docker_secret "${name}" "${namespace}"
            ;;
        tls)
            tls_secret "${name}" "${namespace}"
            ;;
        basicauth)
            basicauth_secret "${name}" "${namespace}"
            ;;
        ssh)
            ssh_secret "${name}" "${namespace}"
            ;;
        file)
            file_secret "${name}" "${namespace}"
            ;;
        *)
            error "Unknown secret type: ${type}"
            usage
            ;;
    esac
}

main "$@"
