#!/bin/bash
set -euo pipefail

#############################################################################
# check-storage-health.sh - Verify TrueNAS Storage Stack Health
#
# Purpose: Comprehensive health check for Democratic CSI + TrueNAS
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
  Comprehensive health check for TrueNAS storage stack:
  - Democratic CSI pods
  - VolumeSnapshotClass configuration
  - StorageProfile CDI optimization
  - CSI driver registration
  - Storage network connectivity

${BLUE}Exit Codes:${NC}
  0 - All healthy
  1 - Critical issues found
  2 - Warnings but operational
EOF
    exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

# Preflight
if ! command -v oc &> /dev/null; then
    error "oc CLI not found"
    exit 1
fi

if ! oc whoami &> /dev/null; then
    error "Not logged into OpenShift"
    exit 1
fi

WARNINGS=0
ERRORS=0

section "Democratic CSI Pods"

# Check namespace
if ! oc get namespace democratic-csi &> /dev/null; then
    error "Namespace 'democratic-csi' not found"
    error "Democratic CSI may not be installed"
    exit 1
fi

# Check controller pod
CONTROLLER_POD=$(oc get pods -n democratic-csi -l app.kubernetes.io/name=democratic-csi -o name 2>/dev/null | grep controller | head -1)

if [[ -z "${CONTROLLER_POD}" ]]; then
    error "Controller pod not found"
    ((ERRORS++))
else
    CONTROLLER_STATUS=$(oc get ${CONTROLLER_POD} -n democratic-csi -o jsonpath='{.status.phase}')
    if [[ "${CONTROLLER_STATUS}" == "Running" ]]; then
        success "Controller pod: Running"
        
        # Check container readiness
        READY=$(oc get ${CONTROLLER_POD} -n democratic-csi -o jsonpath='{.status.containerStatuses[0].ready}')
        if [[ "${READY}" == "true" ]]; then
            success "Controller containers: Ready"
        else
            warning "Controller containers not all ready"
            ((WARNINGS++))
        fi
    else
        error "Controller pod: ${CONTROLLER_STATUS}"
        ((ERRORS++))
    fi
fi

# Check node pods
NODE_PODS=$(oc get pods -n democratic-csi -l app.kubernetes.io/name=democratic-csi -o name 2>/dev/null | grep -v controller || true)
if [[ -n "${NODE_PODS}" ]]; then
    NODE_COUNT=$(echo "${NODE_PODS}" | wc -l)
else
    NODE_COUNT=0
fi

if [[ ${NODE_COUNT} -eq 0 ]]; then
    error "No node pods found"
    ((ERRORS++))
else
    RUNNING_COUNT=0
    for pod in ${NODE_PODS}; do
        POD_STATUS=$(oc get ${pod} -n democratic-csi -o jsonpath='{.status.phase}')
        if [[ "${POD_STATUS}" == "Running" ]]; then
            ((RUNNING_COUNT++))
        fi
    done
    
    if [[ ${RUNNING_COUNT} -eq ${NODE_COUNT} ]]; then
        success "Node pods: ${RUNNING_COUNT}/${NODE_COUNT} Running"
    else
        error "Node pods: Only ${RUNNING_COUNT}/${NODE_COUNT} Running"
        ((ERRORS++))
    fi
fi

section "CSI Driver Registration"

# Check CSI driver
if oc get csidriver truenas-nfs &> /dev/null; then
    success "CSI driver 'truenas-nfs' registered"
    
    # Check driver details
    ATTACH_REQUIRED=$(oc get csidriver truenas-nfs -o jsonpath='{.spec.attachRequired}')
    if [[ "${ATTACH_REQUIRED}" == "false" ]]; then
        success "Driver configured for NFS (attachRequired: false)"
    else
        warning "Driver attachRequired: ${ATTACH_REQUIRED} (expected: false for NFS)"
        ((WARNINGS++))
    fi
else
    error "CSI driver 'truenas-nfs' not found"
    ((ERRORS++))
fi

section "StorageClass"

# Check storage class
if oc get sc truenas-nfs &> /dev/null; then
    success "StorageClass 'truenas-nfs' exists"
    
    # Check provisioner
    PROVISIONER=$(oc get sc truenas-nfs -o jsonpath='{.provisioner}')
    if [[ "${PROVISIONER}" == "truenas-nfs" ]]; then
        success "Provisioner: ${PROVISIONER}"
    else
        error "Provisioner mismatch: ${PROVISIONER} (expected: truenas-nfs)"
        ((ERRORS++))
    fi
    
    # Check parameters
    ALLOW_EXPANSION=$(oc get sc truenas-nfs -o jsonpath='{.allowVolumeExpansion}')
    if [[ "${ALLOW_EXPANSION}" == "true" ]]; then
        success "Volume expansion: Enabled"
    else
        info "Volume expansion: ${ALLOW_EXPANSION:-false}"
    fi
else
    error "StorageClass 'truenas-nfs' not found"
    ((ERRORS++))
fi

section "VolumeSnapshotClass"

# Check snapshot class
if oc get volumesnapshotclass truenas-nfs-snap &> /dev/null; then
    success "VolumeSnapshotClass 'truenas-nfs-snap' exists"
    
    # Check driver match
    SNAP_DRIVER=$(oc get volumesnapshotclass truenas-nfs-snap -o jsonpath='{.driver}')
    if [[ "${SNAP_DRIVER}" == "truenas-nfs" ]]; then
        success "Snapshot driver: ${SNAP_DRIVER} (matches CSI driver)"
    else
        error "Snapshot driver mismatch: ${SNAP_DRIVER}"
        error "Must match CSI driver name 'truenas-nfs'"
        error "This will cause snapshots to hang!"
        ((ERRORS++))
    fi
    
    # Check if default
    IS_DEFAULT=$(oc get volumesnapshotclass truenas-nfs-snap -o jsonpath='{.metadata.annotations.snapshot\.storage\.kubernetes\.io/is-default-class}')
    if [[ "${IS_DEFAULT}" == "true" ]]; then
        success "Default snapshot class: Yes"
    else
        warning "Not set as default snapshot class"
        ((WARNINGS++))
    fi
else
    error "VolumeSnapshotClass 'truenas-nfs-snap' not found"
    error "Snapshots will not work!"
    ((ERRORS++))
fi

section "StorageProfile (CDI Optimization)"

# Check if CDI is installed
if oc get crd storageprofiles.cdi.kubevirt.io &> /dev/null; then
    # Check storage profile
    if oc get storageprofile truenas-nfs &> /dev/null; then
        success "StorageProfile 'truenas-nfs' exists"
        
        # Check clone strategy
        CLONE_STRATEGY=$(oc get storageprofile truenas-nfs -o jsonpath='{.spec.cloneStrategy}' 2>/dev/null)
        if [[ "${CLONE_STRATEGY}" == "csi-clone" ]]; then
            success "Clone strategy: csi-clone (instant VM cloning enabled)"
        elif [[ "${CLONE_STRATEGY}" == "snapshot" ]]; then
            warning "Clone strategy: snapshot (slower than csi-clone)"
            warning "Consider patching to 'csi-clone' for instant cloning"
            ((WARNINGS++))
        else
            warning "Clone strategy: ${CLONE_STRATEGY:-not-set}"
            warning "VM cloning will be slow (network copy)"
            ((WARNINGS++))
        fi
        
        # Check snapshot class in profile
        PROFILE_SNAP=$(oc get storageprofile truenas-nfs -o jsonpath='{.status.snapshotClass}' 2>/dev/null)
        if [[ "${PROFILE_SNAP}" == "truenas-nfs-snap" ]]; then
            success "Profile snapshot class: ${PROFILE_SNAP}"
        elif [[ -n "${PROFILE_SNAP}" ]]; then
            warning "Profile snapshot class: ${PROFILE_SNAP} (expected: truenas-nfs-snap)"
            ((WARNINGS++))
        fi
    else
        warning "StorageProfile 'truenas-nfs' not found"
        warning "VM cloning will use slow network copy"
        ((WARNINGS++))
    fi
else
    info "CDI not installed (StorageProfile check skipped)"
fi

section "Storage Network Connectivity"

info "Testing connectivity to TrueNAS (172.16.160.100)..."

# Test ping
if ping -c 2 -W 2 172.16.160.100 &> /dev/null; then
    success "ICMP ping: Reachable"
else
    warning "ICMP ping: Failed (may be blocked by firewall)"
    ((WARNINGS++))
fi

# Test API
if curl -k -s --connect-timeout 5 https://172.16.160.100/api/v2.0/system/info &> /dev/null; then
    success "TrueNAS API: Reachable"
    
    # Get version
    VERSION=$(curl -k -s --connect-timeout 5 https://172.16.160.100/api/v2.0/system/info 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "${VERSION}" ]]; then
        info "TrueNAS version: ${VERSION}"
        
        if [[ "${VERSION}" == *"25.10"* ]]; then
            success "TrueNAS 25.10 detected (Fangtooth)"
            
            # Check if using correct image tag
            if [[ -n "${CONTROLLER_POD}" ]]; then
                IMAGE=$(oc get ${CONTROLLER_POD} -n democratic-csi -o jsonpath='{.spec.containers[0].image}')
                if echo "${IMAGE}" | grep -q ":next"; then
                    success "CSI driver using 'next' tag (correct for 25.10)"
                else
                    error "CSI driver NOT using 'next' tag: ${IMAGE}"
                    error "TrueNAS 25.10 requires 'next' tag for API compatibility"
                    ((ERRORS++))
                fi
            fi
        fi
    fi
else
    error "TrueNAS API: Unreachable"
    error "Check VLAN 160 connectivity"
    ((ERRORS++))
fi

# Test NFS
if command -v showmount &> /dev/null; then
    if timeout 5 showmount -e 172.16.160.100 &> /dev/null; then
        success "NFS exports: Available"
    else
        error "NFS exports: Cannot query"
        ((ERRORS++))
    fi
else
    info "showmount not available (NFS check skipped)"
fi

section "Summary"

echo ""
info "Health Check Results:"
echo "  Total Checks: $(( $(grep -c "success\|error\|warning" <<< "$(declare -F)") ))"
echo "  ${GREEN}Passed: $(grep -c "success \"" "$0" 2>/dev/null || echo "N/A")${NC}"

if [[ ${ERRORS} -gt 0 ]]; then
    echo "  ${RED}Errors: ${ERRORS}${NC}"
fi

if [[ ${WARNINGS} -gt 0 ]]; then
    echo "  ${YELLOW}Warnings: ${WARNINGS}${NC}"
fi

echo ""

if [[ ${ERRORS} -gt 0 ]]; then
    error "Critical issues found - storage may not be operational"
    exit 1
elif [[ ${WARNINGS} -gt 0 ]]; then
    warning "Some warnings detected - storage operational but not optimal"
    exit 2
else
    success "All checks passed - storage stack is healthy!"
    exit 0
fi
