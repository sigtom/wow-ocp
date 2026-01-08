#!/bin/bash
set -euo pipefail

#############################################################################
# check-truenas-capacity.sh - Check ZFS Pool and Dataset Capacity
#
# Purpose: SSH to TrueNAS and report storage usage
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
POOL_NAME="wow-ts10TB"

usage() {
    cat >&2 <<EOF
${BLUE}Usage:${NC}
  $0 [--detailed]

${BLUE}Description:${NC}
  Check ZFS pool and dataset capacity on TrueNAS.
  
  Requires SSH access to TrueNAS (172.16.160.100).

${BLUE}Options:${NC}
  --detailed    Show per-dataset breakdown

${BLUE}Examples:${NC}
  $0               # Pool summary
  $0 --detailed    # Detailed dataset usage
EOF
    exit 1
}

DETAILED=false
if [[ "${1:-}" == "--detailed" ]]; then
    DETAILED=true
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

# Check SSH access
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@${TRUENAS_IP} "echo test" &> /dev/null; then
    echo -e "${RED}ERROR: Cannot SSH to TrueNAS at ${TRUENAS_IP}${NC}" >&2
    echo "Ensure SSH key is configured" >&2
    exit 1
fi

echo -e "${BLUE}━━━ TrueNAS Storage Capacity ━━━${NC}\n"

# Get pool info
POOL_INFO=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -o name,used,avail,refer,compressratio -H ${POOL_NAME}" 2>/dev/null)

if [[ -z "${POOL_INFO}" ]]; then
    echo -e "${RED}ERROR: Cannot get pool info${NC}" >&2
    exit 1
fi

# Parse pool info
read -r NAME USED AVAIL REFER COMPRESS <<< "${POOL_INFO}"

# Calculate percentages
TOTAL_BYTES=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs get -Hp available ${POOL_NAME}" 2>/dev/null | awk '{print $3}')
USED_BYTES=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs get -Hp used ${POOL_NAME}" 2>/dev/null | awk '{print $3}')

if [[ -n "${TOTAL_BYTES}" && -n "${USED_BYTES}" ]]; then
    TOTAL_SIZE=$((USED_BYTES + TOTAL_BYTES))
    PERCENT_USED=$((USED_BYTES * 100 / TOTAL_SIZE))
else
    PERCENT_USED=0
fi

# Color based on usage
if [[ ${PERCENT_USED} -ge 90 ]]; then
    USAGE_COLOR="${RED}"
elif [[ ${PERCENT_USED} -ge 80 ]]; then
    USAGE_COLOR="${YELLOW}"
else
    USAGE_COLOR="${GREEN}"
fi

echo -e "${BLUE}Pool Summary:${NC}"
echo "  Name: ${NAME}"
echo "  Used: ${USED}"
echo "  Available: ${AVAIL}"
echo -e "  Usage: ${USAGE_COLOR}${PERCENT_USED}%${NC}"
echo "  Compression Ratio: ${COMPRESS}"
echo ""

# Check if critical
if [[ ${PERCENT_USED} -ge 90 ]]; then
    echo -e "${RED}⚠ CRITICAL: Pool usage >90% - Clean up immediately!${NC}"
    echo ""
elif [[ ${PERCENT_USED} -ge 80 ]]; then
    echo -e "${YELLOW}⚠ WARNING: Pool usage >80% - Plan cleanup soon${NC}"
    echo ""
fi

# Show OCP volumes dataset
echo -e "${BLUE}OpenShift Volumes Dataset:${NC}"
OCP_VOLUMES=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -o name,used,avail,refer -H ${POOL_NAME}/ocp-nfs-volumes 2>/dev/null")

if [[ -n "${OCP_VOLUMES}" ]]; then
    read -r OCP_NAME OCP_USED OCP_AVAIL OCP_REFER <<< "${OCP_VOLUMES}"
    echo "  Dataset: ${OCP_NAME}"
    echo "  Used: ${OCP_USED}"
    echo "  Available: ${OCP_AVAIL}"
    echo ""
else
    echo -e "${YELLOW}  Dataset not found: ${POOL_NAME}/ocp-nfs-volumes${NC}"
    echo ""
fi

# Snapshot overhead
echo -e "${BLUE}Snapshot Overhead:${NC}"
SNAP_USED=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -t snapshot -o used -Hp ${POOL_NAME}/ocp-nfs-volumes 2>/dev/null | awk '{s+=\$1} END {print s}'")

if [[ -n "${SNAP_USED}" && "${SNAP_USED}" != "0" ]]; then
    # Convert bytes to human readable
    SNAP_HUMAN=$(numfmt --to=iec-i --suffix=B ${SNAP_USED} 2>/dev/null || echo "${SNAP_USED} bytes")
    echo "  Total snapshot usage: ${SNAP_HUMAN}"
    
    SNAP_COUNT=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -t snapshot -H ${POOL_NAME}/ocp-nfs-volumes 2>/dev/null | wc -l")
    echo "  Number of snapshots: ${SNAP_COUNT}"
else
    echo "  No snapshots found"
fi
echo ""

# Detailed dataset list
if [[ "${DETAILED}" == "true" ]]; then
    echo -e "${BLUE}━━━ Detailed Dataset Breakdown ━━━${NC}\n"
    
    echo -e "${BLUE}Dynamic Volumes (v):${NC}"
    ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -r -o name,used,refer -H ${POOL_NAME}/ocp-nfs-volumes/v 2>/dev/null" | while read -r line; do
        echo "  ${line}"
    done
    echo ""
    
    echo -e "${BLUE}Snapshots (s):${NC}"
    ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -t snapshot -o name,used,refer -H ${POOL_NAME}/ocp-nfs-volumes/s 2>/dev/null | head -20" | while read -r line; do
        echo "  ${line}"
    done
    
    TOTAL_SNAPS=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -t snapshot -H ${POOL_NAME}/ocp-nfs-volumes/s 2>/dev/null | wc -l")
    if [[ ${TOTAL_SNAPS} -gt 20 ]]; then
        echo "  ... and $(( TOTAL_SNAPS - 20 )) more"
    fi
    echo ""
    
    echo -e "${BLUE}Media Library:${NC}"
    MEDIA=$(ssh -o StrictHostKeyChecking=no root@${TRUENAS_IP} "zfs list -o name,used,avail,refer -H ${POOL_NAME}/media 2>/dev/null")
    if [[ -n "${MEDIA}" ]]; then
        read -r MEDIA_NAME MEDIA_USED MEDIA_AVAIL MEDIA_REFER <<< "${MEDIA}"
        echo "  Dataset: ${MEDIA_NAME}"
        echo "  Used: ${MEDIA_USED}"
        echo "  Available: ${MEDIA_AVAIL}"
        echo "  Referenced: ${MEDIA_REFER}"
    else
        echo "  Media dataset not found"
    fi
    echo ""
fi

# Recommendations
echo -e "${BLUE}━━━ Recommendations ━━━${NC}\n"

if [[ ${PERCENT_USED} -ge 80 ]]; then
    echo "1. Clean up unused PVCs"
    echo "2. Delete old snapshots"
    echo "3. Consider expanding the pool"
elif [[ ${PERCENT_USED} -ge 60 ]]; then
    echo "1. Monitor usage trends"
    echo "2. Plan for expansion"
else
    echo "Storage capacity is healthy"
fi

echo ""
echo -e "${BLUE}To clean up snapshots:${NC}"
echo "  ssh root@${TRUENAS_IP} \"zfs list -t snapshot | grep old\""
echo "  ssh root@${TRUENAS_IP} \"zfs destroy <snapshot-name>\""
