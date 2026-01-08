#!/bin/bash
set -euo pipefail

#############################################################################
# check-storage-network.sh - Test VLAN 160 Storage Network Connectivity
#
# Purpose: Diagnose storage network issues (VLAN 160 to TrueNAS)
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
  Test storage network (VLAN 160) connectivity from all OpenShift nodes
  to TrueNAS backend (172.16.160.100).
  
  Tests:
    • ICMP ping to TrueNAS
    • HTTPS API connectivity
    • NFS showmount availability
    • VLAN 160 interface configuration per node
    • Node 4 hybrid NIC configuration

${BLUE}Prerequisites:${NC}
  • oc CLI configured with cluster access
  • Cluster admin permissions (for node debugging)
  • SSH access to nodes (for detailed debugging)

${BLUE}Network Layout:${NC}
  Node 2/3 (4-port): eno2 dedicated 10G storage (172.16.160.x)
  Node 4 (2-port):   eno2 hybrid 1G - VLAN 160 tagged (172.16.160.x)
  TrueNAS:           172.16.160.100
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

TRUENAS_IP="172.16.160.100"
STORAGE_NETWORK="172.16.160.0/24"

section "Storage Network Overview"

info "TrueNAS IP: ${TRUENAS_IP}"
info "Storage Network: ${STORAGE_NETWORK} (VLAN 160)"
info "Expected Node IPs: 172.16.160.2, 172.16.160.3, 172.16.160.4"

section "Checking Cluster Nodes"

# Get all nodes
NODES=$(oc get nodes -o jsonpath='{.items[*].metadata.name}')

if [[ -z "${NODES}" ]]; then
    error "No nodes found in cluster"
    exit 1
fi

info "Found nodes: ${NODES}"

section "Testing TrueNAS Connectivity from Control Plane"

# Test from where we are running (assumes we can reach it if nodes can)
info "Testing ICMP ping to ${TRUENAS_IP}..."
if ping -c 2 -W 2 "${TRUENAS_IP}" &> /dev/null; then
    success "ICMP ping successful"
else
    warning "ICMP ping failed (may be blocked by firewall)"
fi

info "Testing HTTPS API connectivity..."
if curl -k -s --connect-timeout 5 "https://${TRUENAS_IP}/api/v2.0/system/info" &> /dev/null; then
    success "TrueNAS API reachable"
    
    # Get TrueNAS version
    VERSION=$(curl -k -s --connect-timeout 5 "https://${TRUENAS_IP}/api/v2.0/system/info" 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "${VERSION}" ]]; then
        info "TrueNAS Version: ${VERSION}"
        
        if [[ "${VERSION}" == *"25.10"* ]]; then
            info "TrueNAS 25.10 (Fangtooth) detected"
            warning "Ensure democratic-csi uses 'next' image tag for API compatibility"
        fi
    fi
else
    error "Cannot reach TrueNAS API at https://${TRUENAS_IP}"
    warning "Storage network may be down or misconfigured"
fi

info "Testing NFS showmount..."
if command -v showmount &> /dev/null; then
    if timeout 5 showmount -e "${TRUENAS_IP}" &> /dev/null; then
        success "NFS exports available"
        showmount -e "${TRUENAS_IP}" 2>/dev/null | head -5
    else
        error "Cannot query NFS exports from ${TRUENAS_IP}"
    fi
else
    warning "showmount not available (install nfs-utils for testing)"
fi

section "Per-Node Storage Network Configuration"

for node in ${NODES}; do
    echo ""
    info "Checking node: ${node}"
    
    # Determine node type from name
    NODE_TYPE="unknown"
    if [[ "${node}" == *"node2"* || "${node}" == *"worker-0"* ]]; then
        NODE_TYPE="4-port (Node 2)"
        EXPECTED_IF="eno2"
        EXPECTED_IP="172.16.160.2"
    elif [[ "${node}" == *"node3"* || "${node}" == *"worker-1"* ]]; then
        NODE_TYPE="4-port (Node 3)"
        EXPECTED_IF="eno2"
        EXPECTED_IP="172.16.160.3"
    elif [[ "${node}" == *"node4"* || "${node}" == *"worker-2"* ]]; then
        NODE_TYPE="2-port hybrid (Node 4)"
        EXPECTED_IF="eno2.160"
        EXPECTED_IP="172.16.160.4"
    fi
    
    info "Node type: ${NODE_TYPE}"
    
    # Check if node is ready
    NODE_READY=$(oc get node "${node}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [[ "${NODE_READY}" != "True" ]]; then
        error "Node ${node} is not Ready - skipping network check"
        continue
    fi
    
    # Get node IP addresses
    NODE_IPS=$(oc get node "${node}" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    info "Node IPs: ${NODE_IPS}"
    
    # Check if storage network IP is assigned
    if echo "${NODE_IPS}" | grep -q "${EXPECTED_IP}"; then
        success "Storage network IP ${EXPECTED_IP} is assigned"
    else
        warning "Expected storage IP ${EXPECTED_IP} not found in node addresses"
        warning "VLAN 160 interface may not be configured"
    fi
    
    # Try to debug node and check interface (requires cluster-admin)
    info "Checking network interfaces on ${node}..."
    
    DEBUG_OUTPUT=$(oc debug node/"${node}" --quiet -- chroot /host bash -c "ip addr show | grep -A 3 '${EXPECTED_IF}'" 2>/dev/null || echo "")
    
    if [[ -n "${DEBUG_OUTPUT}" ]]; then
        if echo "${DEBUG_OUTPUT}" | grep -q "inet ${EXPECTED_IP}"; then
            success "Interface ${EXPECTED_IF} configured correctly"
            echo "${DEBUG_OUTPUT}"
        else
            error "Interface ${EXPECTED_IF} found but IP mismatch"
            echo "${DEBUG_OUTPUT}"
        fi
    else
        warning "Could not check interface (requires cluster-admin and debug permissions)"
        info "Manual check: oc debug node/${node} -- chroot /host ip addr show"
    fi
    
    # Test connectivity from node
    info "Testing TrueNAS connectivity from ${node}..."
    
    PING_TEST=$(oc debug node/"${node}" --quiet -- chroot /host ping -c 2 -W 2 "${TRUENAS_IP}" 2>&1 | grep -c "bytes from" || echo "0")
    
    if [[ "${PING_TEST}" -gt 0 ]]; then
        success "Node can ping TrueNAS"
    else
        error "Node cannot ping TrueNAS at ${TRUENAS_IP}"
        error "VLAN 160 routing issue on ${node}"
        
        if [[ "${NODE_TYPE}" == "2-port hybrid (Node 4)" ]]; then
            error "Node 4 requires VLAN 160 tagged on eno2 - check configuration"
            echo ""
            warning "To fix Node 4 VLAN configuration:"
            echo "  oc debug node/${node}"
            echo "  chroot /host"
            echo "  nmcli con add type vlan con-name eno2.160 ifname eno2.160 dev eno2 id 160"
            echo "  nmcli con mod eno2.160 ipv4.addresses ${EXPECTED_IP}/24"
            echo "  nmcli con mod eno2.160 ipv4.method manual"
            echo "  nmcli con up eno2.160"
        fi
    fi
done

section "NFS Mount Test"

info "Attempting to list NFS exports from TrueNAS..."

if command -v showmount &> /dev/null; then
    EXPORTS=$(timeout 10 showmount -e "${TRUENAS_IP}" 2>&1)
    
    if echo "${EXPORTS}" | grep -q "/mnt"; then
        success "NFS exports available:"
        echo "${EXPORTS}"
    else
        error "No NFS exports found or showmount failed"
        echo "${EXPORTS}"
    fi
else
    warning "Install nfs-utils for NFS export testing: yum install nfs-utils"
fi

section "Democratic-CSI Pod Network Check"

info "Checking if democratic-csi pods can reach storage network..."

# Get democratic-csi pods
CSI_PODS=$(oc get pods -n democratic-csi -l app=democratic-csi-nfs -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [[ -n "${CSI_PODS}" ]]; then
    for pod in ${CSI_PODS}; do
        info "Testing from CSI pod: ${pod}"
        
        # Try curl to TrueNAS API
        POD_TEST=$(oc exec -n democratic-csi "${pod}" -- curl -k -s --connect-timeout 3 "https://${TRUENAS_IP}/api/v2.0/system/info" 2>&1)
        
        if echo "${POD_TEST}" | grep -q "version"; then
            success "CSI pod can reach TrueNAS API"
        else
            error "CSI pod cannot reach TrueNAS API"
            echo "Error: ${POD_TEST}"
        fi
    done
else
    warning "No democratic-csi pods found - may not be installed"
fi

section "Summary & Recommendations"

echo -e "\n${BLUE}Storage Network Status:${NC}"
echo "  TrueNAS IP: ${TRUENAS_IP}"
echo "  Network: ${STORAGE_NETWORK} (VLAN 160)"

echo -e "\n${YELLOW}Common Issues:${NC}"
echo "1. Node 4 (2-port) requires VLAN 160 tagged on eno2"
echo "   - Check: oc debug node/<node4> -- chroot /host ip addr show eno2.160"
echo "   - Fix: Create VLAN interface with nmcli (see output above)"
echo ""
echo "2. Switch VLAN trunk not configured"
echo "   - Verify switch port has VLAN 160 tagged"
echo "   - Check switch configuration for trunk mode"
echo ""
echo "3. TrueNAS NFS service not running"
echo "   - Login to TrueNAS: https://172.16.160.100"
echo "   - Check: Services → NFS → Running"
echo "   - Verify NFS exports exist"
echo ""
echo "4. Firewall blocking storage traffic"
echo "   - Check node firewall: oc debug node/<node> -- chroot /host iptables -L"
echo "   - Verify no DROP rules for 172.16.160.0/24"

echo -e "\n${BLUE}Next Steps:${NC}"
echo "• Check democratic-csi logs: ./check-democratic-csi.sh"
echo "• Review CSI driver config: oc get secret -n democratic-csi democratic-csi-driver-config -o yaml"
echo "• Test manual NFS mount from node: oc debug node/<node> -- chroot /host mount -t nfs ${TRUENAS_IP}:/mnt/tank/test /mnt"

exit 0
