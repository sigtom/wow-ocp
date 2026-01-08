#!/bin/bash
# VM/LXC Creation Helper Script
# Generates playbooks and updates inventory for new VMs/LXCs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AUTOMATION_DIR="$REPO_ROOT/automation"
INVENTORY_FILE="$AUTOMATION_DIR/inventory/hosts.yaml"
PLAYBOOKS_DIR="$AUTOMATION_DIR/playbooks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 <platform> <name> <os> <vcpu> <ram_mb> <disk_gb>

Create a new VM or LXC container on specified platform.

Parameters:
  platform   : ocp, proxmox-vm, or proxmox-lxc
  name       : VM/LXC name (hostname)
  os         : rhel9, ubuntu, windows (for OCP); ubuntu (for Proxmox)
  vcpu       : Number of CPU cores
  ram_mb     : RAM in MB (e.g., 2048 for 2GB, 4096 for 4GB)
  disk_gb    : Disk size in GB

Examples:
  # OpenShift RHEL 9 VM
  $0 ocp my-app-vm rhel9 4 8192 50

  # Proxmox Ubuntu VM
  $0 proxmox-vm my-utility-vm ubuntu 2 2048 20

  # Proxmox LXC Container
  $0 proxmox-lxc my-dev-lxc ubuntu 1 512 8

EOF
    exit 1
}

# Check arguments
if [ $# -ne 6 ]; then
    usage
fi

PLATFORM=$1
NAME=$2
OS=$3
VCPU=$4
RAM_MB=$5
DISK_GB=$6

# Validate platform
if [[ ! "$PLATFORM" =~ ^(ocp|proxmox-vm|proxmox-lxc)$ ]]; then
    echo -e "${RED}Error: Platform must be 'ocp', 'proxmox-vm', or 'proxmox-lxc'${NC}"
    usage
fi

# Validate OS
case "$PLATFORM" in
    ocp)
        if [[ ! "$OS" =~ ^(rhel9|ubuntu|windows)$ ]]; then
            echo -e "${RED}Error: For OCP, OS must be 'rhel9', 'ubuntu', or 'windows'${NC}"
            exit 1
        fi
        ;;
    proxmox-vm|proxmox-lxc)
        if [[ "$OS" != "ubuntu" ]]; then
            echo -e "${YELLOW}Warning: Only 'ubuntu' is fully supported for Proxmox. Proceeding anyway...${NC}"
        fi
        ;;
esac

echo -e "${GREEN}Creating $PLATFORM: $NAME${NC}"
echo "  OS: $OS"
echo "  vCPU: $VCPU"
echo "  RAM: ${RAM_MB}MB"
echo "  Disk: ${DISK_GB}GB"
echo ""

###############################################################################
# OpenShift VM Creation
###############################################################################
if [ "$PLATFORM" == "ocp" ]; then
    echo -e "${GREEN}==> Creating OpenShift VM manifest${NC}"
    
    # Choose template based on OS
    case "$OS" in
        rhel9)
            TEMPLATE="$SCRIPT_DIR/../templates/ocp/vm-rhel9.yaml"
            ;;
        windows)
            TEMPLATE="$SCRIPT_DIR/../templates/ocp/vm-windows.yaml"
            ;;
        ubuntu)
            TEMPLATE="$SCRIPT_DIR/../templates/ocp/vm-rhel9.yaml"
            echo -e "${YELLOW}Note: Using RHEL template, adjust registry URL for Ubuntu${NC}"
            ;;
        *)
            echo -e "${RED}Error: Unsupported OS for OCP: $OS${NC}"
            exit 1
            ;;
    esac
    
    # Create namespace name (sanitize)
    NAMESPACE="${NAME}-ns"
    
    # Output file
    OUTPUT_FILE="/tmp/${NAME}-vm.yaml"
    
    # Copy and customize template
    cp "$TEMPLATE" "$OUTPUT_FILE"
    
    # Replace placeholders (basic sed replacements)
    # In production, use proper templating (jinja2, yq, etc.)
    sed -i "s/my-vm-namespace/$NAMESPACE/g" "$OUTPUT_FILE"
    sed -i "s/my-vm-disk/${NAME}-disk/g" "$OUTPUT_FILE"
    sed -i "s/my-vm/$NAME/g" "$OUTPUT_FILE"
    sed -i "s/cores: 2/cores: $VCPU/g" "$OUTPUT_FILE"
    sed -i "s/memory: 4Gi/memory: ${RAM_MB}Mi/g" "$OUTPUT_FILE"
    sed -i "s/storage: 30Gi/storage: ${DISK_GB}Gi/g" "$OUTPUT_FILE"
    sed -i "s/hostname: my-vm.sigtom.dev/hostname: ${NAME}.sigtom.dev/g" "$OUTPUT_FILE"
    sed -i "s/fqdn: my-vm.sigtom.dev/fqdn: ${NAME}.sigtom.dev/g" "$OUTPUT_FILE"
    
    echo -e "${GREEN}==> VM manifest created: $OUTPUT_FILE${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review and customize: vim $OUTPUT_FILE"
    echo "  2. Apply to cluster: oc apply -f $OUTPUT_FILE"
    echo "  3. Monitor: oc get vm,vmi,dv,pvc -n $NAMESPACE"
    echo "  4. Console access: $SCRIPT_DIR/ocp-console.sh $NAME $NAMESPACE"
    echo ""

###############################################################################
# Proxmox VM Creation
###############################################################################
elif [ "$PLATFORM" == "proxmox-vm" ]; then
    echo -e "${GREEN}==> Creating Proxmox VM playbook${NC}"
    
    # Prompt for IP and VMID
    echo -n "Enter IP address (172.16.110.XXX): "
    read IP_ADDRESS
    
    echo -n "Enter VMID (unique, e.g., 250): "
    read VMID
    
    # Validate IP format
    if ! [[ "$IP_ADDRESS" =~ ^172\.16\.110\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}Error: Invalid IP format. Must be 172.16.110.XXX${NC}"
        exit 1
    fi
    
    # Check if VMID already exists in inventory
    if grep -q "vmid: $VMID" "$INVENTORY_FILE" 2>/dev/null; then
        echo -e "${RED}Error: VMID $VMID already exists in inventory${NC}"
        exit 1
    fi
    
    # Add to inventory
    echo -e "${YELLOW}==> Adding $NAME to inventory${NC}"
    cat >> "$INVENTORY_FILE" <<EOF
    $NAME:
      ansible_host: $IP_ADDRESS
      vmid: $VMID
      proxmox_node: wow-prox1
EOF
    
    # Create playbook from template
    OUTPUT_FILE="$PLAYBOOKS_DIR/deploy-${NAME}.yaml"
    cp "$SCRIPT_DIR/../templates/proxmox/deploy-vm.yaml" "$OUTPUT_FILE"
    
    # Replace host references
    sed -i "s/hosts: my-vm/hosts: $NAME/g" "$OUTPUT_FILE"
    
    # Add resource overrides if different from defaults
    if [ "$VCPU" != "1" ] || [ "$RAM_MB" != "1024" ]; then
        sed -i "/gather_facts: no/a\\
  vars:\\
    vm_cores: $VCPU\\
    vm_memory: $RAM_MB" "$OUTPUT_FILE"
    fi
    
    echo -e "${GREEN}==> Playbook created: $OUTPUT_FILE${NC}"
    echo -e "${GREEN}==> Inventory updated: $INVENTORY_FILE${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify inventory: cat $INVENTORY_FILE | grep -A3 $NAME"
    echo "  2. Review playbook: vim $OUTPUT_FILE"
    echo "  3. Set API token: export PROXMOX_SRE_BOT_API_TOKEN='...'"
    echo "  4. Run playbook: cd $AUTOMATION_DIR && ansible-playbook -i inventory/hosts.yaml playbooks/deploy-${NAME}.yaml"
    echo "  5. Access VM: ssh -i ~/.ssh/id_pfsense_sre ubuntu@$IP_ADDRESS"
    echo ""

###############################################################################
# Proxmox LXC Creation
###############################################################################
elif [ "$PLATFORM" == "proxmox-lxc" ]; then
    echo -e "${GREEN}==> Creating Proxmox LXC playbook${NC}"
    
    # Prompt for IP and VMID
    echo -n "Enter IP address (172.16.110.XXX): "
    read IP_ADDRESS
    
    echo -n "Enter VMID (unique, e.g., 350): "
    read VMID
    
    # Validate IP format
    if ! [[ "$IP_ADDRESS" =~ ^172\.16\.110\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}Error: Invalid IP format. Must be 172.16.110.XXX${NC}"
        exit 1
    fi
    
    # Check if VMID already exists in inventory
    if grep -q "vmid: $VMID" "$INVENTORY_FILE" 2>/dev/null; then
        echo -e "${RED}Error: VMID $VMID already exists in inventory${NC}"
        exit 1
    fi
    
    # Add to inventory
    echo -e "${YELLOW}==> Adding $NAME to inventory${NC}"
    cat >> "$INVENTORY_FILE" <<EOF
    $NAME:
      ansible_host: $IP_ADDRESS
      vmid: $VMID
      proxmox_node: wow-prox1
EOF
    
    # Create playbook from template
    OUTPUT_FILE="$PLAYBOOKS_DIR/deploy-${NAME}.yaml"
    cp "$SCRIPT_DIR/../templates/proxmox/deploy-lxc.yaml" "$OUTPUT_FILE"
    
    # Replace host references
    sed -i "s/hosts: my-lxc/hosts: $NAME/g" "$OUTPUT_FILE"
    
    # Add resource overrides if different from defaults
    if [ "$VCPU" != "1" ] || [ "$RAM_MB" != "512" ] || [ "$DISK_GB" != "8" ]; then
        sed -i "/gather_facts: no/a\\
  vars:\\
    lxc_cores: $VCPU\\
    lxc_memory: $RAM_MB\\
    lxc_rootfs_size: $DISK_GB" "$OUTPUT_FILE"
    fi
    
    echo -e "${GREEN}==> Playbook created: $OUTPUT_FILE${NC}"
    echo -e "${GREEN}==> Inventory updated: $INVENTORY_FILE${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify inventory: cat $INVENTORY_FILE | grep -A3 $NAME"
    echo "  2. Review playbook: vim $OUTPUT_FILE"
    echo "  3. Set API token: export PROXMOX_SRE_BOT_API_TOKEN='...'"
    echo "  4. Install collection: ansible-galaxy collection install community.general"
    echo "  5. Run playbook: cd $AUTOMATION_DIR && ansible-playbook -i inventory/hosts.yaml playbooks/deploy-${NAME}.yaml"
    echo "  6. Access LXC: ssh -i ~/.ssh/id_pfsense_sre root@$IP_ADDRESS"
    echo ""
fi

echo -e "${GREEN}Done!${NC}"
