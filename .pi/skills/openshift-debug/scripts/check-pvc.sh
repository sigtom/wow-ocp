#!/bin/bash
set -euo pipefail

#############################################################################
# check-pvc.sh - Diagnose PVC Provisioning Issues
#
# Purpose: Comprehensive PVC troubleshooting for OpenShift homelab
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
    echo -e "${BLUE}→ INFO: $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ SUCCESS: $1${NC}" >&2
}

section() {
    echo -e "\n${BLUE}━━━ $1 ━━━${NC}" >&2
}

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 <pvc-name> <namespace>

${BLUE}Description:${NC}
  Diagnose PVC provisioning issues in OpenShift homelab.
  
  Checks:
    • PVC status and events
    • StorageClass configuration
    • CSI driver pod health
    • CSI provisioner logs
    • Storage network connectivity (VLAN 160)

${BLUE}Examples:${NC}
  $0 plex-config media
  $0 my-pvc default

${BLUE}Prerequisites:${NC}
  • oc CLI configured with cluster access
  • Cluster admin permissions (for CSI logs)
EOF
    exit 1
}

# Argument parsing
if [[ $# -ne 2 ]]; then
    usage
fi

PVC_NAME="$1"
NAMESPACE="$2"

# Preflight checks
if ! command -v oc &> /dev/null; then
    error "oc CLI not found. Install OpenShift CLI tools."
    exit 1
fi

if ! oc whoami &> /dev/null; then
    error "Not logged into OpenShift cluster. Run: oc login"
    exit 1
fi

section "PVC Status Check"

# Check if PVC exists
if ! oc get pvc "${PVC_NAME}" -n "${NAMESPACE}" &> /dev/null; then
    error "PVC '${PVC_NAME}' not found in namespace '${NAMESPACE}'"
    exit 1
fi

# Get PVC status
PVC_STATUS=$(oc get pvc "${PVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}')
info "PVC Status: ${PVC_STATUS}"

if [[ "${PVC_STATUS}" == "Bound" ]]; then
    success "PVC is bound successfully"
    PV_NAME=$(oc get pvc "${PVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.volumeName}')
    info "Bound to PV: ${PV_NAME}"
    exit 0
fi

if [[ "${PVC_STATUS}" != "Pending" ]]; then
    warning "PVC is in unexpected state: ${PVC_STATUS}"
fi

section "PVC Events"

# Get events
EVENTS=$(oc get events -n "${NAMESPACE}" --field-selector involvedObject.name="${PVC_NAME}" --sort-by='.lastTimestamp' 2>/dev/null)

if [[ -z "${EVENTS}" ]]; then
    warning "No events found for PVC (may indicate stale/old PVC)"
else
    echo "${EVENTS}" | tail -10
    
    # Check for common error patterns
    if echo "${EVENTS}" | grep -qi "ProvisioningFailed"; then
        error "Provisioning failed - check CSI driver logs"
    fi
    
    if echo "${EVENTS}" | grep -qi "connection refused\|timeout"; then
        error "Storage backend unreachable - check VLAN 160 connectivity"
    fi
fi

section "StorageClass Configuration"

# Get StorageClass
SC_NAME=$(oc get pvc "${PVC_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.storageClassName}')
info "StorageClass: ${SC_NAME}"

if [[ -z "${SC_NAME}" ]]; then
    error "No StorageClass specified - check PVC manifest"
    exit 1
fi

if ! oc get sc "${SC_NAME}" &> /dev/null; then
    error "StorageClass '${SC_NAME}' does not exist"
    exit 1
fi

# Get provisioner
PROVISIONER=$(oc get sc "${SC_NAME}" -o jsonpath='{.provisioner}')
info "Provisioner: ${PROVISIONER}"

success "StorageClass exists and is valid"

section "CSI Driver Health Check"

# Determine CSI namespace based on provisioner
if [[ "${PROVISIONER}" == *"democratic-csi"* ]]; then
    CSI_NAMESPACE="democratic-csi"
    CSI_LABEL="app=democratic-csi-nfs"
elif [[ "${PROVISIONER}" == *"lvms"* ]]; then
    CSI_NAMESPACE="openshift-storage"
    CSI_LABEL="app=lvms-operator"
else
    warning "Unknown provisioner: ${PROVISIONER}"
    CSI_NAMESPACE="democratic-csi"
    CSI_LABEL="app=democratic-csi-nfs"
fi

info "Checking CSI driver in namespace: ${CSI_NAMESPACE}"

# Check CSI pods
CSI_PODS=$(oc get pods -n "${CSI_NAMESPACE}" -l "${CSI_LABEL}" --no-headers 2>/dev/null)

if [[ -z "${CSI_PODS}" ]]; then
    error "No CSI driver pods found in namespace '${CSI_NAMESPACE}'"
    error "Expected label: ${CSI_LABEL}"
    exit 1
fi

# Check pod status
NOT_RUNNING=$(echo "${CSI_PODS}" | grep -v "Running" || true)
if [[ -n "${NOT_RUNNING}" ]]; then
    error "CSI driver pods not running:"
    echo "${NOT_RUNNING}"
    exit 1
else
    success "CSI driver pods are running"
fi

section "CSI Provisioner Logs (Last 20 lines)"

# Get recent logs from controller/provisioner
CONTROLLER_POD=$(oc get pods -n "${CSI_NAMESPACE}" -l "${CSI_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -n "${CONTROLLER_POD}" ]]; then
    info "Fetching logs from: ${CONTROLLER_POD}"
    
    LOGS=$(oc logs -n "${CSI_NAMESPACE}" "${CONTROLLER_POD}" --tail=20 2>/dev/null)
    echo "${LOGS}"
    
    # Check for common errors
    if echo "${LOGS}" | grep -qi "error\|failed\|refused\|timeout"; then
        error "Errors found in CSI logs - investigate above"
        
        if echo "${LOGS}" | grep -qi "172.16.160.100"; then
            error "Storage backend (172.16.160.100) unreachable"
            warning "Check VLAN 160 connectivity - run: ./check-storage-network.sh"
        fi
        
        if echo "${LOGS}" | grep -qi "unsupported\|404\|api"; then
            error "API compatibility issue detected"
            warning "For TrueNAS 25.10, ensure democratic-csi uses 'next' tag"
            warning "Run: ./check-democratic-csi.sh"
        fi
    else
        success "No obvious errors in recent logs"
    fi
else
    warning "Could not find controller pod for log retrieval"
fi

section "Storage Network Connectivity"

info "Testing connectivity to TrueNAS (172.16.160.100)..."

# Try to reach TrueNAS API
if curl -k -s --connect-timeout 3 https://172.16.160.100/api/v2.0/system/info &> /dev/null; then
    success "TrueNAS API is reachable from cluster"
else
    error "Cannot reach TrueNAS API at 172.16.160.100"
    warning "Storage network (VLAN 160) may be down or misconfigured"
    warning "Run: ./check-storage-network.sh for detailed network diagnostics"
fi

section "Summary"

info "PVC: ${PVC_NAME}"
info "Namespace: ${NAMESPACE}"
info "Status: ${PVC_STATUS}"
info "StorageClass: ${SC_NAME}"
info "Provisioner: ${PROVISIONER}"

if [[ "${PVC_STATUS}" == "Pending" ]]; then
    echo -e "\n${YELLOW}Recommendations:${NC}"
    echo "1. Review CSI logs above for specific errors"
    echo "2. Check storage network: ./check-storage-network.sh"
    echo "3. Verify TrueNAS NFS exports: showmount -e 172.16.160.100"
    echo "4. Check democratic-csi config: ./check-democratic-csi.sh"
    echo "5. Review PVC events: oc describe pvc ${PVC_NAME} -n ${NAMESPACE}"
fi

exit 0
