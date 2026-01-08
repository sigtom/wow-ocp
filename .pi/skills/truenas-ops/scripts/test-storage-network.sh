#!/bin/bash
set -euo pipefail

#############################################################################
# test-storage-network.sh - Test VLAN 160 Storage Network Connectivity
#
# Purpose: Verify storage network from all OpenShift nodes to TrueNAS
# Author: Senior SRE (Gen X Edition)
# Version: 1.0
#############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TRUENAS_IP="172.16.160.100"

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 [--bandwidth]

${BLUE}Description:${NC}
  Test storage network (VLAN 160) connectivity from all cluster nodes
  to TrueNAS.

${BLUE}Options:${NC}
  --bandwidth    Run iperf3 bandwidth test (requires iperf3 on TrueNAS)

${BLUE}Tests:${NC}
  • ICMP ping to TrueNAS
  • TrueNAS API (HTTPS)
  • NFS showmount
  • Per-node VLAN 160 interface configuration
  • Optional: iperf3 bandwidth test

${BLUE}Examples:${NC}
  $0                # Basic connectivity
  $0 --bandwidth    # Include bandwidth test
EOF
    exit 1
}

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

BANDWIDTH_TEST=false
if [[ "${1:-}" == "--bandwidth" ]]; then
    BANDWIDTH_TEST=true
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

if ! command -v oc &> /dev/null; then
    error "oc CLI not found"
    exit 1
fi

echo -e "${BLUE}━━━ Storage Network Test (VLAN 160 → TrueNAS) ━━━${NC}\n"

# Basic connectivity from current host
info "Testing from current host..."

if ping -c 2 -W 2 ${TRUENAS_IP} &> /dev/null; then
    success "ICMP ping: ${TRUENAS_IP} reachable"
else
    warning "ICMP ping: Failed (may be blocked)"
fi

if curl -k -s --connect-timeout 5 https://${TRUENAS_IP}/api/v2.0/system/info &> /dev/null; then
    success "TrueNAS API: Reachable"
    
    VERSION=$(curl -k -s https://${TRUENAS_IP}/api/v2.0/system/info 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    [[ -n "${VERSION}" ]] && info "TrueNAS version: ${VERSION}"
else
    error "TrueNAS API: Unreachable"
fi

if command -v showmount &> /dev/null; then
    if timeout 5 showmount -e ${TRUENAS_IP} &> /dev/null; then
        success "NFS exports: Available"
        showmount -e ${TRUENAS_IP} 2>/dev/null | head -5
    else
        error "NFS exports: Cannot query"
    fi
else
    info "showmount not available (install nfs-utils)"
fi

echo ""

# Per-node testing
info "Testing from each cluster node...\n"

NODES=$(oc get nodes -o name | sed 's|node/||')

for node in ${NODES}; do
    echo -e "${BLUE}━━━ Node: ${node} ━━━${NC}"
    
    # Determine expected interface
    if [[ "${node}" == *"worker-2"* || "${node}" == *"node4"* ]]; then
        EXPECTED_IF="eno2.160"
        NODE_TYPE="2-port (VLAN tagged)"
    else
        EXPECTED_IF="eno2"
        NODE_TYPE="4-port (dedicated)"
    fi
    
    info "Type: ${NODE_TYPE}"
    info "Expected interface: ${EXPECTED_IF}"
    
    # Check interface
    IF_CHECK=$(oc debug node/${node} --quiet -- chroot /host bash -c "ip addr show ${EXPECTED_IF} 2>/dev/null" 2>/dev/null || echo "")
    
    if [[ -n "${IF_CHECK}" ]]; then
        IP_ADDR=$(echo "${IF_CHECK}" | grep "inet 172.16.160" | awk '{print $2}')
        if [[ -n "${IP_ADDR}" ]]; then
            success "Interface ${EXPECTED_IF}: ${IP_ADDR}"
        else
            error "Interface ${EXPECTED_IF}: No 172.16.160.x IP found"
        fi
    else
        error "Interface ${EXPECTED_IF}: Not found"
        
        if [[ "${EXPECTED_IF}" == "eno2.160" ]]; then
            warning "Node 4 requires VLAN 160 tagged on eno2"
            echo "  Fix: oc debug node/${node}"
            echo "       chroot /host"
            echo "       nmcli con add type vlan con-name eno2.160 ifname eno2.160 dev eno2 id 160"
            echo "       nmcli con mod eno2.160 ipv4.addresses 172.16.160.4/24"
            echo "       nmcli con mod eno2.160 ipv4.method manual"
            echo "       nmcli con up eno2.160"
        fi
    fi
    
    # Test connectivity
    PING_TEST=$(oc debug node/${node} --quiet -- chroot /host ping -c 2 -W 2 ${TRUENAS_IP} 2>&1 | grep -c "bytes from" || echo "0")
    
    if [[ "${PING_TEST}" -gt 0 ]]; then
        success "Ping to TrueNAS: Success"
    else
        error "Ping to TrueNAS: Failed"
    fi
    
    # Bandwidth test if requested
    if [[ "${BANDWIDTH_TEST}" == "true" ]]; then
        if command -v iperf3 &> /dev/null; then
            info "Running iperf3 bandwidth test..."
            BANDWIDTH=$(oc debug node/${node} --quiet -- chroot /host iperf3 -c ${TRUENAS_IP} -t 5 -f m 2>/dev/null | grep "sender" | awk '{print $7" "$8}' || echo "Failed")
            if [[ "${BANDWIDTH}" != "Failed" ]]; then
                success "Bandwidth: ${BANDWIDTH}"
            else
                warning "Bandwidth test failed (iperf3 may not be running on TrueNAS)"
            fi
        else
            warning "iperf3 not available on node"
        fi
    fi
    
    echo ""
done

# Summary
echo -e "${BLUE}━━━ Summary ━━━${NC}\n"
echo "Storage Network: 172.16.160.0/24 (VLAN 160)"
echo "TrueNAS IP: ${TRUENAS_IP}"
echo ""
echo "Node Configuration:"
echo "  • Node 2/3 (4-port): Dedicated eno2 for storage (10G)"
echo "  • Node 4 (2-port):   Tagged eno2.160 for storage (1G)"
echo ""
echo "If connectivity fails:"
echo "  1. Check VLAN 160 configuration on switches"
echo "  2. Verify NIC cable connections"
echo "  3. Check TrueNAS NFS service status"
echo "  4. Review firewall rules (iptables)"
