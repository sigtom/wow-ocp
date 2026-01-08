#!/bin/bash
# Quick access to OpenShift VM console via virtctl

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 <vm-name> <namespace>

Access OpenShift VM console using virtctl.

Parameters:
  vm-name    : Name of the VirtualMachine resource
  namespace  : Namespace where VM is deployed

Examples:
  $0 my-vm my-namespace
  $0 technitium-vm technitium-dns

EOF
    exit 1
}

# Check arguments
if [ $# -ne 2 ]; then
    usage
fi

VM_NAME=$1
NAMESPACE=$2

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: 'oc' command not found. Install OpenShift CLI.${NC}"
    exit 1
fi

# Check if virtctl is available
if ! command -v virtctl &> /dev/null; then
    echo -e "${YELLOW}Warning: 'virtctl' command not found.${NC}"
    echo "Install with: oc krew install virt"
    echo "Or download from: https://github.com/kubevirt/kubevirt/releases"
    echo ""
    echo "Attempting to use 'oc' plugin method..."
    echo ""
fi

# Check if logged into OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster.${NC}"
    echo "Run: oc login"
    exit 1
fi

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist.${NC}"
    exit 1
fi

# Check if VM exists
if ! oc get vm "$VM_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo -e "${RED}Error: VirtualMachine '$VM_NAME' not found in namespace '$NAMESPACE'.${NC}"
    echo ""
    echo "Available VMs in namespace $NAMESPACE:"
    oc get vm -n "$NAMESPACE" 2>/dev/null || echo "  No VMs found"
    exit 1
fi

# Check VM status
echo -e "${GREEN}==> Checking VM status...${NC}"
VM_STATUS=$(oc get vm "$VM_NAME" -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}' 2>/dev/null || echo "Unknown")
echo "VM: $VM_NAME"
echo "Namespace: $NAMESPACE"
echo "Status: $VM_STATUS"
echo ""

if [ "$VM_STATUS" != "Running" ]; then
    echo -e "${YELLOW}Warning: VM is not in 'Running' state.${NC}"
    echo "Current state: $VM_STATUS"
    echo ""
    read -p "Do you want to start the VM? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Starting VM..."
        if command -v virtctl &> /dev/null; then
            virtctl start "$VM_NAME" -n "$NAMESPACE"
        else
            # Try using oc virt plugin
            oc virt start "$VM_NAME" -n "$NAMESPACE" 2>/dev/null || {
                echo -e "${RED}Error: Cannot start VM. Install virtctl.${NC}"
                exit 1
            }
        fi
        echo "Waiting for VM to start..."
        sleep 10
    else
        echo "VM must be running to access console. Exiting."
        exit 1
    fi
fi

# Access console
echo -e "${GREEN}==> Connecting to VM console...${NC}"
echo "Press Ctrl+] to exit console"
echo ""

if command -v virtctl &> /dev/null; then
    virtctl console "$VM_NAME" -n "$NAMESPACE"
else
    # Try using oc virt plugin
    oc virt console "$VM_NAME" -n "$NAMESPACE" 2>/dev/null || {
        echo -e "${RED}Error: Cannot access console. Install virtctl:${NC}"
        echo "  oc krew install virt"
        echo "  OR download from: https://github.com/kubevirt/kubevirt/releases"
        exit 1
    }
fi
