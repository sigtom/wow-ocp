#!/bin/bash
set -euo pipefail

#############################################################################
# check-democratic-csi.sh - Check Democratic-CSI Driver Status and Config
#
# Purpose: Diagnose democratic-csi driver issues for TrueNAS storage
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
    echo -e "${RED}✗ $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}" >&2
}

info() {
    echo -e "${BLUE}→ $1${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ $1${NC}" >&2
}

section() {
    echo -e "\n${BLUE}━━━ $1 ━━━${NC}" >&2
}

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0

${BLUE}Description:${NC}
  Check democratic-csi driver status, logs, and configuration for
  TrueNAS storage backend integration.
  
  Checks:
    • Controller and node driver pod status
    • Image tag (must be 'next' for TrueNAS 25.10)
    • Recent provisioner logs
    • CSI driver registration
    • StorageClass configuration

${BLUE}Prerequisites:${NC}
  • oc CLI configured with cluster access
  • Democratic-csi installed in cluster

${BLUE}Common Issues:${NC}
  • Image tag must be 'next' for TrueNAS 25.10 (Fangtooth) API compatibility
  • Storage network (VLAN 160) must be reachable from all nodes
  • TrueNAS NFS service must be running
EOF
    exit 1
}

# Argument parsing
if [[ "$#" -gt 0 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
    usage
fi

# Preflight checks
if ! command -v oc &> /dev/null; then
    error "oc CLI not found. Install OpenShift CLI tools."
    exit 1
fi

if ! oc whoami &> /dev/null; then
    error "Not logged into OpenShift cluster. Run: oc login"
    exit 1
fi

CSI_NAMESPACE="democratic-csi"
TRUENAS_IP="172.16.160.100"

section "Democratic-CSI Deployment Check"

# Check if namespace exists
if ! oc get namespace "${CSI_NAMESPACE}" &> /dev/null; then
    error "Namespace '${CSI_NAMESPACE}' not found"
    error "Democratic-csi may not be installed"
    exit 1
fi

success "Namespace '${CSI_NAMESPACE}' exists"

section "CSI Driver Pods Status"

# Get all pods
PODS=$(oc get pods -n "${CSI_NAMESPACE}" --no-headers 2>/dev/null)

if [[ -z "${PODS}" ]]; then
    error "No pods found in namespace '${CSI_NAMESPACE}'"
    error "Democratic-csi may not be deployed"
    exit 1
fi

info "Pods in ${CSI_NAMESPACE}:"
echo "${PODS}"

# Check controller pod
CONTROLLER_POD=$(oc get pods -n "${CSI_NAMESPACE}" -l app=democratic-csi-nfs -o jsonpath='{.items[?(@.metadata.name=~"controller")].metadata.name}' 2>/dev/null | head -1)

if [[ -z "${CONTROLLER_POD}" ]]; then
    error "No controller pod found"
else
    CONTROLLER_STATUS=$(oc get pod "${CONTROLLER_POD}" -n "${CSI_NAMESPACE}" -o jsonpath='{.status.phase}')
    if [[ "${CONTROLLER_STATUS}" == "Running" ]]; then
        success "Controller pod is Running"
    else
        error "Controller pod is ${CONTROLLER_STATUS}"
    fi
fi

# Check node pods
NODE_PODS=$(oc get pods -n "${CSI_NAMESPACE}" -l app=democratic-csi-nfs -o jsonpath='{.items[?(@.metadata.name=~"node")].metadata.name}')

if [[ -z "${NODE_PODS}" ]]; then
    warning "No node pods found (may be DaemonSet issue)"
else
    NODE_COUNT=$(echo "${NODE_PODS}" | wc -w)
    RUNNING_COUNT=$(oc get pods -n "${CSI_NAMESPACE}" -l app=democratic-csi-nfs -o jsonpath='{.items[?(@.metadata.name=~"node")].status.phase}' | grep -c "Running" || echo "0")
    
    if [[ "${RUNNING_COUNT}" == "${NODE_COUNT}" ]]; then
        success "All ${NODE_COUNT} node pods are Running"
    else
        error "${RUNNING_COUNT}/${NODE_COUNT} node pods are Running"
    fi
fi

section "Image Tag Check"

# Get image from controller pod
if [[ -n "${CONTROLLER_POD}" ]]; then
    IMAGE=$(oc get pod "${CONTROLLER_POD}" -n "${CSI_NAMESPACE}" -o jsonpath='{.spec.containers[0].image}')
    info "Controller image: ${IMAGE}"
    
    # Check tag
    if echo "${IMAGE}" | grep -q ":next"; then
        success "Using 'next' tag (required for TrueNAS 25.10)"
    elif echo "${IMAGE}" | grep -q ":latest"; then
        error "Using 'latest' tag - NOT compatible with TrueNAS 25.10"
        error "Update to 'next' tag for Fangtooth API compatibility"
        echo ""
        warning "To fix:"
        echo "  oc patch deployment -n ${CSI_NAMESPACE} democratic-csi-controller \\"
        echo "    --type='json' -p='[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/image\", \"value\":\"democraticcsi/democratic-csi:next\"}]'"
    else
        warning "Using versioned tag: ${IMAGE}"
        warning "For TrueNAS 25.10, 'next' tag is recommended"
    fi
    
    # Check node pods image
    if [[ -n "${NODE_PODS}" ]]; then
        NODE_IMAGE=$(oc get pods -n "${CSI_NAMESPACE}" -l app=democratic-csi-nfs -o jsonpath='{.items[?(@.metadata.name=~"node")].spec.containers[0].image}' | head -1)
        
        if [[ "${IMAGE}" != "${NODE_IMAGE}" ]]; then
            error "Image mismatch between controller and node pods"
            echo "  Controller: ${IMAGE}"
            echo "  Node: ${NODE_IMAGE}"
        fi
    fi
fi

section "CSI Driver Registration"

# Check CSIDriver object
CSIDRIVER=$(oc get csidriver | grep democratic-csi || echo "")

if [[ -n "${CSIDRIVER}" ]]; then
    success "CSI driver is registered"
    echo "${CSIDRIVER}"
else
    error "CSI driver not registered with Kubernetes"
fi

section "StorageClass Configuration"

# Get StorageClasses using democratic-csi
STORAGE_CLASSES=$(oc get sc -o jsonpath='{range .items[?(@.provisioner=~"democratic-csi")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [[ -z "${STORAGE_CLASSES}" ]]; then
    error "No StorageClasses found using democratic-csi provisioner"
else
    success "StorageClasses using democratic-csi:"
    for sc in ${STORAGE_CLASSES}; do
        info "  - ${sc}"
        
        # Check if it's the default
        IS_DEFAULT=$(oc get sc "${sc}" -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
        if [[ "${IS_DEFAULT}" == "true" ]]; then
            info "    (default)"
        fi
        
        # Get provisioner
        PROVISIONER=$(oc get sc "${sc}" -o jsonpath='{.provisioner}')
        info "    Provisioner: ${PROVISIONER}"
    done
fi

section "Controller Logs (Last 30 lines)"

if [[ -n "${CONTROLLER_POD}" ]]; then
    info "Fetching logs from: ${CONTROLLER_POD}"
    
    LOGS=$(oc logs -n "${CSI_NAMESPACE}" "${CONTROLLER_POD}" --tail=30 2>&1)
    
    # Check for errors
    if echo "${LOGS}" | grep -qi "error\|fail\|refused\|timeout"; then
        error "Errors found in recent logs:"
        echo "${LOGS}" | grep -i "error\|fail\|refused\|timeout" | tail -10
        echo ""
        info "Full logs:"
        echo "${LOGS}"
        
        # Specific error patterns
        if echo "${LOGS}" | grep -qi "connection refused.*${TRUENAS_IP}"; then
            error "Cannot connect to TrueNAS at ${TRUENAS_IP}"
            warning "Check storage network: ./check-storage-network.sh"
        fi
        
        if echo "${LOGS}" | grep -qi "unsupported\|404\|not found"; then
            error "API compatibility issue detected"
            warning "Ensure image tag is 'next' for TrueNAS 25.10"
        fi
        
        if echo "${LOGS}" | grep -qi "authentication\|unauthorized\|401"; then
            error "Authentication failed to TrueNAS API"
            warning "Check API key in democratic-csi-driver-config secret"
        fi
    else
        success "No obvious errors in recent logs"
        info "Last few log entries:"
        echo "${LOGS}" | tail -5
    fi
else
    warning "No controller pod found - cannot retrieve logs"
fi

section "Driver Configuration Check"

# Check if config secret exists
CONFIG_SECRET="democratic-csi-driver-config"

if oc get secret "${CONFIG_SECRET}" -n "${CSI_NAMESPACE}" &> /dev/null; then
    success "Driver config secret exists: ${CONFIG_SECRET}"
    
    # Get config (without showing API key)
    info "Config overview (sanitized):"
    CONFIG=$(oc get secret "${CONFIG_SECRET}" -n "${CSI_NAMESPACE}" -o jsonpath='{.data.driver-config-file\.yaml}' | base64 -d 2>/dev/null)
    
    if [[ -n "${CONFIG}" ]]; then
        # Show non-sensitive parts
        echo "${CONFIG}" | grep -E "^\s*(driver|httpConnection|host|port|protocol|zfs)" | head -20
        
        # Check for TrueNAS IP
        if echo "${CONFIG}" | grep -q "${TRUENAS_IP}"; then
            success "Config references TrueNAS at ${TRUENAS_IP}"
        else
            warning "Config does not reference ${TRUENAS_IP}"
        fi
        
        # Check protocol
        if echo "${CONFIG}" | grep -q "protocol.*https"; then
            success "Using HTTPS for API"
        elif echo "${CONFIG}" | grep -q "protocol.*http"; then
            warning "Using HTTP for API (not recommended)"
        fi
    else
        error "Could not decode config secret"
    fi
else
    error "Driver config secret '${CONFIG_SECRET}' not found"
    error "Democratic-csi may not be properly configured"
fi

section "Recent PVC Provisions"

# Get recent PVC events
info "Checking recent PVC provisioning activity..."

RECENT_PVCS=$(oc get pvc -A -o jsonpath='{range .items[?(@.spec.storageClassName=="truenas-nfs")]}{.metadata.namespace}{"/"}{.metadata.name}{" - "}{.status.phase}{"\n"}{end}' 2>/dev/null | tail -5)

if [[ -n "${RECENT_PVCS}" ]]; then
    info "Recent PVCs using truenas-nfs StorageClass:"
    echo "${RECENT_PVCS}"
    
    # Count pending
    PENDING_COUNT=$(echo "${RECENT_PVCS}" | grep -c "Pending" || echo "0")
    if [[ "${PENDING_COUNT}" -gt 0 ]]; then
        error "${PENDING_COUNT} PVC(s) stuck in Pending state"
        warning "Run: ./check-pvc.sh <pvc-name> <namespace> for details"
    fi
else
    info "No recent PVCs found using democratic-csi"
fi

section "TrueNAS Connectivity Test"

info "Testing connectivity to TrueNAS API..."

if curl -k -s --connect-timeout 5 "https://${TRUENAS_IP}/api/v2.0/system/info" &> /dev/null; then
    success "TrueNAS API is reachable from this location"
    
    # Get version
    VERSION=$(curl -k -s --connect-timeout 5 "https://${TRUENAS_IP}/api/v2.0/system/info" 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "${VERSION}" ]]; then
        info "TrueNAS Version: ${VERSION}"
        
        if [[ "${VERSION}" == *"25.10"* ]]; then
            success "TrueNAS 25.10 (Fangtooth) confirmed"
            
            # Verify image tag again
            if [[ -n "${IMAGE}" ]] && ! echo "${IMAGE}" | grep -q ":next"; then
                error "TrueNAS 25.10 requires democratic-csi:next tag"
                error "Current image: ${IMAGE}"
            fi
        fi
    fi
else
    error "Cannot reach TrueNAS API at https://${TRUENAS_IP}"
    warning "Storage network (VLAN 160) may be misconfigured"
    warning "Run: ./check-storage-network.sh for network diagnostics"
fi

section "Summary & Recommendations"

info "Democratic-CSI Status Summary"

echo -e "\n${BLUE}Key Findings:${NC}"
if [[ -n "${CONTROLLER_POD}" && "${CONTROLLER_STATUS}" == "Running" ]]; then
    echo "  ✓ Controller pod: Running"
else
    echo "  ✗ Controller pod: ${CONTROLLER_STATUS:-Not Found}"
fi

if [[ -n "${NODE_PODS}" ]]; then
    echo "  ✓ Node pods: ${RUNNING_COUNT}/${NODE_COUNT} Running"
else
    echo "  ✗ Node pods: Not Found"
fi

if [[ -n "${IMAGE}" ]]; then
    if echo "${IMAGE}" | grep -q ":next"; then
        echo "  ✓ Image tag: next (correct for TrueNAS 25.10)"
    else
        echo "  ✗ Image tag: ${IMAGE##*:} (should be 'next' for TrueNAS 25.10)"
    fi
fi

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. If controller is not running: oc describe pod ${CONTROLLER_POD} -n ${CSI_NAMESPACE}"
echo "2. If image tag is wrong: Patch deployment to use 'next' tag (see output above)"
echo "3. If API errors persist: Check driver config secret and TrueNAS credentials"
echo "4. If connectivity fails: Run ./check-storage-network.sh"
echo "5. For PVC issues: Run ./check-pvc.sh <pvc-name> <namespace>"

echo -e "\n${BLUE}Useful Commands:${NC}"
echo "• View full logs: oc logs -n ${CSI_NAMESPACE} ${CONTROLLER_POD} --tail=100"
echo "• Check config: oc get secret -n ${CSI_NAMESPACE} ${CONFIG_SECRET} -o yaml"
echo "• Restart driver: oc delete pod -n ${CSI_NAMESPACE} ${CONTROLLER_POD}"
echo "• List PVCs: oc get pvc -A --sort-by=.metadata.creationTimestamp"

exit 0
