#!/bin/bash
# Quick capacity summary - shows just the key metrics

set -euo pipefail

echo "========================================"
echo " OpenShift Cluster Capacity Summary"
echo "========================================"
echo ""

# Get actual resource metrics using oc adm top
NODES=$(oc get nodes --no-headers 2>/dev/null | wc -l)
TOTAL_CPU=$(oc get nodes -o json | jq '[.items[].status.allocatable.cpu | if type == "string" and endswith("m") then (rtrimstr("m") | tonumber / 1000) else tonumber end] | add' 2>/dev/null || echo "0")
TOTAL_MEM_KB=$(oc get nodes -o json | jq '[.items[].status.allocatable.memory | rtrimstr("Ki") | tonumber] | add' 2>/dev/null || echo "0")
TOTAL_MEM_GB=$(echo "scale=0; $TOTAL_MEM_KB / 1024 / 1024" | bc)

# Get actual usage from oc adm top
CPU_USAGE_M=$(oc adm top nodes --no-headers 2>/dev/null | awk '{sum+=$2} END {gsub(/m/,"",sum); print sum}' || echo "0")
MEM_USAGE_MI=$(oc adm top nodes --no-headers 2>/dev/null | awk '{sum+=$4} END {gsub(/Mi/,"",sum); print sum}' || echo "0")

CPU_USAGE_CORES=$(echo "scale=1; $CPU_USAGE_M / 1000" | bc)
MEM_USAGE_GB=$(echo "scale=1; $MEM_USAGE_MI / 1024" | bc)

CPU_PERCENT=$(echo "scale=1; ($CPU_USAGE_CORES / $TOTAL_CPU) * 100" | bc)
MEM_PERCENT=$(echo "scale=1; ($MEM_USAGE_GB / $TOTAL_MEM_GB) * 100" | bc)

TOTAL_PODS=$(oc get pods --all-namespaces --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(oc get pods --all-namespaces --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

# Determine status
if (( $(echo "$CPU_PERCENT >= 90" | bc -l) )) || (( $(echo "$MEM_PERCENT >= 90" | bc -l) )); then
    STATUS="🔴 CRITICAL"
elif (( $(echo "$CPU_PERCENT >= 85" | bc -l) )) || (( $(echo "$MEM_PERCENT >= 85" | bc -l) )); then
    STATUS="🟡 WARNING"
else
    STATUS="🟢 HEALTHY"
fi

echo "Status: $STATUS"
echo ""
echo "Nodes:   $NODES"
echo "CPU:     ${CPU_USAGE_CORES}/${TOTAL_CPU} cores (${CPU_PERCENT}%)"
echo "Memory:  ${MEM_USAGE_GB}/${TOTAL_MEM_GB} GB (${MEM_PERCENT}%)"
echo "Pods:    ${RUNNING_PODS}/${TOTAL_PODS} running"
echo ""

# Storage summary
echo "Storage:"
ssh root@172.16.160.100 "zpool list -H wow-ts10TB" 2>/dev/null | \
    awk '{printf "  TrueNAS: %s used / %s total (%.1f%%)\n", $3, $2, ($3/$2)*100}' || \
    echo "  TrueNAS: Unable to check"

echo ""
echo "For full report:"
echo "  cat $(dirname "$0")/../../reports/latest.md"
echo ""
echo "Generate new report:"
echo "  $(dirname "$0")/generate-report.sh"
echo ""
