#!/bin/bash
# Generate comprehensive capacity planning report in Markdown format

set -euo pipefail

# Ignore SIGPIPE (exit code 141) - happens with head/tail/etc
trap '' PIPE

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
REPORTS_DIR="$REPO_ROOT/reports"

# Create reports directory if it doesn't exist
mkdir -p "$REPORTS_DIR"

# Generate timestamp
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
DATE_HUMAN=$(date '+%B %d, %Y at %I:%M %p %Z')
REPORT_FILE="$REPORTS_DIR/capacity-report-${TIMESTAMP}.md"

echo "Generating capacity planning report..."
echo "Output: $REPORT_FILE"

# Function to strip ANSI color codes
strip_colors() {
    # Remove ANSI color codes and escape sequences
    sed -r 's/\x1b\[[0-9;]*[mGKHF]//g' | \
    sed -r 's/\\033\[[0-9;]*[mGKHF]//g' | \
    # Remove all Unicode box-drawing and block characters (U+2500-U+257F, U+2580-U+259F)
    LC_ALL=C sed 's/[│┤┐└┴┬├─┼║╔╗╚╝═╠╣╦╩╬█░▓▒▀▄▌▐■]//g' | \
    # Remove any remaining control characters except newline and tab
    tr -cd '\11\12\15\40-\176' | \
    # Clean up multiple spaces
    sed 's/  \+/ /g'
}

# Start building the report
cat > "$REPORT_FILE" << 'HEADER'
# OpenShift Cluster Capacity Report

**Generated:** DATE_PLACEHOLDER

---

## Executive Summary

HEADER

# Replace placeholder with actual date
sed -i "s/DATE_PLACEHOLDER/$DATE_HUMAN/g" "$REPORT_FILE"

# Get cluster status for executive summary
echo "Collecting cluster overview..."
CLUSTER_STATUS=$("$SCRIPT_DIR/cluster-capacity.sh" 2>&1 | strip_colors || echo "Error collecting data")

# Extract key metrics for executive summary
TOTAL_NODES=$(oc get nodes --no-headers 2>/dev/null | wc -l)
TOTAL_PODS=$(oc get pods --all-namespaces --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(oc get pods --all-namespaces --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

# Get actual resource metrics
TOTAL_CPU=$(oc get nodes -o json | jq '[.items[].status.allocatable.cpu | tonumber] | add' 2>/dev/null || echo "0")
TOTAL_MEM_KB=$(oc get nodes -o json | jq '[.items[].status.allocatable.memory | rtrimstr("Ki") | tonumber] | add' 2>/dev/null || echo "0")
TOTAL_MEM_GB=$(echo "scale=0; $TOTAL_MEM_KB / 1024 / 1024" | bc)

# Calculate actual usage from oc adm top
CPU_USAGE=$(oc adm top nodes --no-headers 2>/dev/null | awk '{sum+=$2} END {print sum}' | sed 's/m$//' || echo "0")
MEM_USAGE_MB=$(oc adm top nodes --no-headers 2>/dev/null | awk '{sum+=$4} END {print sum}' | sed 's/Mi$//' || echo "0")
MEM_USAGE_GB=$(echo "scale=1; $MEM_USAGE_MB / 1024" | bc)

CPU_USAGE_CORES=$(echo "scale=1; $CPU_USAGE / 1000" | bc)
CPU_PERCENT=$(echo "scale=1; ($CPU_USAGE_CORES / $TOTAL_CPU) * 100" | bc)
MEM_PERCENT=$(echo "scale=1; ($MEM_USAGE_GB / $TOTAL_MEM_GB) * 100" | bc)

# Determine status
if (( $(echo "$CPU_PERCENT >= 90" | bc -l) )) || (( $(echo "$MEM_PERCENT >= 90" | bc -l) )); then
    STATUS="🔴 **CRITICAL**"
    STATUS_MSG="Immediate action required - cluster at capacity limits"
elif (( $(echo "$CPU_PERCENT >= 85" | bc -l) )) || (( $(echo "$MEM_PERCENT >= 85" | bc -l) )); then
    STATUS="🟡 **WARNING**"
    STATUS_MSG="Approaching capacity limits - defer non-critical workloads"
else
    STATUS="🟢 **HEALTHY**"
    STATUS_MSG="Cluster has adequate capacity headroom"
fi

# Write executive summary
cat >> "$REPORT_FILE" << EOF

**Cluster Status:** $STATUS

$STATUS_MSG

### Key Metrics

| Metric | Value | Utilization |
|--------|-------|-------------|
| **Nodes** | $TOTAL_NODES | - |
| **CPU Cores** | ${CPU_USAGE_CORES}/${TOTAL_CPU} cores | ${CPU_PERCENT}% |
| **Memory** | ${MEM_USAGE_GB}/${TOTAL_MEM_GB} GB | ${MEM_PERCENT}% |
| **Pods** | ${RUNNING_PODS}/${TOTAL_PODS} running | - |

### Capacity Visualization

EOF

# Generate Markdown-friendly progress bars
generate_progress_bar() {
    local percent=$1
    local label=$2
    local width=25  # Number of blocks
    local filled=$(echo "scale=0; ($percent * $width) / 100" | bc)
    local empty=$((width - filled))
    
    # Determine color indicator
    local indicator="🟢"
    if (( $(echo "$percent >= 90" | bc -l) )); then
        indicator="🔴"
    elif (( $(echo "$percent >= 85" | bc -l) )); then
        indicator="🟡"
    fi
    
    # Build bar with █ for filled and ░ for empty
    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
    
    echo "| $label | \`$bar\` | ${percent}% | $indicator |"
}

cat >> "$REPORT_FILE" << 'EOF'
| Resource | Usage Bar (0% ░░░░░ 100%) | Percent | Status |
|----------|---------------------------|---------|--------|
EOF

generate_progress_bar "$CPU_PERCENT" "CPU" >> "$REPORT_FILE"
generate_progress_bar "$MEM_PERCENT" "Memory" >> "$REPORT_FILE"

# Calculate pod percentage
POD_PERCENT=$(echo "scale=1; ($RUNNING_PODS / $TOTAL_PODS) * 100" | bc 2>/dev/null || echo "0")
generate_progress_bar "$POD_PERCENT" "Pods" >> "$REPORT_FILE"

cat >> "$REPORT_FILE" << 'EOF'

---

## 📊 Cluster Capacity Details

EOF

# Add cluster capacity details
echo "Collecting detailed cluster capacity..."
echo '```' >> "$REPORT_FILE"
"$SCRIPT_DIR/cluster-capacity.sh" 2>&1 | strip_colors >> "$REPORT_FILE" || echo "Error collecting cluster capacity" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Add node utilization
echo "Collecting per-node utilization..."
cat >> "$REPORT_FILE" << 'EOF'
---

## 🖥️ Per-Node Utilization

EOF

echo '```' >> "$REPORT_FILE"
"$SCRIPT_DIR/node-utilization.sh" 2>&1 | strip_colors >> "$REPORT_FILE" || echo "Error collecting node utilization" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Add node metrics table
echo "Creating node metrics table..."
cat >> "$REPORT_FILE" << 'EOF'

### Node Metrics Summary

| Node | CPU Usage | Memory Usage | Pods | Status |
|------|-----------|--------------|------|--------|
EOF

# Use temp file to avoid SIGPIPE
TEMP_NODES=$(mktemp)
oc adm top nodes --no-headers 2>/dev/null > "$TEMP_NODES" || true
while read node cpu cpu_pct mem mem_pct; do
    cpu_clean=$(echo $cpu | sed 's/m$//')
    mem_clean=$(echo $mem | sed 's/Mi$//')
    pod_count=$(oc get pods --all-namespaces --field-selector spec.nodeName=$node --no-headers 2>/dev/null | wc -l)
    
    # Determine status
    cpu_pct_num=$(echo $cpu_pct | sed 's/%$//')
    if (( $(echo "$cpu_pct_num >= 80" | bc -l) )); then
        status="🔴 HOT"
    elif (( $(echo "$cpu_pct_num >= 60" | bc -l) )); then
        status="🟡 WARM"
    else
        status="🟢 OK"
    fi
    
    echo "| $node | $cpu ($cpu_pct) | $mem ($mem_pct) | $pod_count | $status |" >> "$REPORT_FILE"
done < "$TEMP_NODES"
rm -f "$TEMP_NODES"

echo "" >> "$REPORT_FILE"

# Add storage capacity
echo "Collecting storage capacity..."
cat >> "$REPORT_FILE" << 'EOF'
---

## 💾 Storage Capacity

EOF

echo '```' >> "$REPORT_FILE"
"$SCRIPT_DIR/storage-capacity.sh" 2>&1 | strip_colors >> "$REPORT_FILE" || echo "Error collecting storage capacity" >> "$REPORT_FILE"
echo '```' >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Add top consumers
echo "Identifying top resource consumers..."
cat >> "$REPORT_FILE" << 'EOF'
---

## 🔝 Top Resource Consumers

### Top Namespaces by CPU

| Namespace | CPU Usage |
|-----------|-----------|
EOF

# Use temp file to avoid SIGPIPE
TEMP_CPU=$(mktemp)
TEMP_SORTED=$(mktemp)
oc adm top pods --all-namespaces --no-headers 2>/dev/null > "$TEMP_CPU" || true
awk '{ns[$1]+=$2} END {for (n in ns) print ns[n], n}' "$TEMP_CPU" | sort -rn > "$TEMP_SORTED"
head -10 "$TEMP_SORTED" | \
    while read cpu ns; do
        echo "| $ns | ${cpu}m |" >> "$REPORT_FILE"
    done
rm -f "$TEMP_CPU" "$TEMP_SORTED"

cat >> "$REPORT_FILE" << 'EOF'

### Top Namespaces by Memory

| Namespace | Memory Usage |
|-----------|--------------|
EOF

# Use temp file to avoid SIGPIPE
TEMP_MEM=$(mktemp)
TEMP_MEM_SORTED=$(mktemp)
oc adm top pods --all-namespaces --no-headers 2>/dev/null > "$TEMP_MEM" || true
awk '{ns[$1]+=$3} END {for (n in ns) print ns[n], n}' "$TEMP_MEM" | sort -rn > "$TEMP_MEM_SORTED"
head -10 "$TEMP_MEM_SORTED" | \
    while read mem ns; do
        echo "| $ns | ${mem}Mi |" >> "$REPORT_FILE"
    done
rm -f "$TEMP_MEM" "$TEMP_MEM_SORTED"

cat >> "$REPORT_FILE" << 'EOF'

### Top Pods by CPU

| Namespace | Pod | CPU Usage |
|-----------|-----|-----------|
EOF

# Use temp file to avoid SIGPIPE
TEMP_POD_CPU=$(mktemp)
TEMP_POD_CPU_SORTED=$(mktemp)
oc adm top pods --all-namespaces --no-headers 2>/dev/null > "$TEMP_POD_CPU" || true
sort -k2 -rn "$TEMP_POD_CPU" > "$TEMP_POD_CPU_SORTED"
head -10 "$TEMP_POD_CPU_SORTED" | \
    while read ns pod cpu mem; do
        echo "| $ns | $pod | $cpu |" >> "$REPORT_FILE"
    done
rm -f "$TEMP_POD_CPU" "$TEMP_POD_CPU_SORTED"

cat >> "$REPORT_FILE" << 'EOF'

### Top Pods by Memory

| Namespace | Pod | Memory Usage |
|-----------|-----|--------------|
EOF

# Use temp file to avoid SIGPIPE
TEMP_POD_MEM=$(mktemp)
TEMP_POD_MEM_SORTED=$(mktemp)
oc adm top pods --all-namespaces --no-headers 2>/dev/null > "$TEMP_POD_MEM" || true
# Sort by memory (field 4), handling Mi suffix
sort -k4 -rh "$TEMP_POD_MEM" > "$TEMP_POD_MEM_SORTED"
head -10 "$TEMP_POD_MEM_SORTED" | \
    while read ns pod cpu mem; do
        echo "| $ns | $pod | $mem |" >> "$REPORT_FILE"
    done
rm -f "$TEMP_POD_MEM" "$TEMP_POD_MEM_SORTED"

echo "" >> "$REPORT_FILE"

# Add PVC summary
cat >> "$REPORT_FILE" << 'EOF'

### Top PVCs by Size

| Namespace | PVC | Size | Storage Class |
|-----------|-----|------|---------------|
EOF

# Use temp file to avoid SIGPIPE
TEMP_PVC=$(mktemp)
TEMP_PVC_SORTED=$(mktemp)
oc get pvc --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] | [.metadata.namespace, .metadata.name, .spec.resources.requests.storage, .spec.storageClassName] | @tsv' > "$TEMP_PVC" || true
sort -k3 -rh "$TEMP_PVC" > "$TEMP_PVC_SORTED"
head -15 "$TEMP_PVC_SORTED" | \
    while IFS=$'\t' read ns pvc size sc; do
        echo "| $ns | $pvc | $size | $sc |" >> "$REPORT_FILE"
    done
rm -f "$TEMP_PVC" "$TEMP_PVC_SORTED"

echo "" >> "$REPORT_FILE"

# Add recommendations
echo "Generating recommendations..."
cat >> "$REPORT_FILE" << 'EOF'
---

## 💡 Recommendations

### Immediate Actions (if applicable)

EOF

# Check for critical issues
if (( $(echo "$CPU_PERCENT >= 90" | bc -l) )); then
    echo "- 🔴 **CPU at critical levels** - Block new deployments, scale down non-critical workloads" >> "$REPORT_FILE"
fi

if (( $(echo "$MEM_PERCENT >= 90" | bc -l) )); then
    echo "- 🔴 **Memory at critical levels** - Remove unused workloads, cleanup immediately" >> "$REPORT_FILE"
fi

# Check for warnings
if (( $(echo "$CPU_PERCENT >= 85" | bc -l) )) && (( $(echo "$CPU_PERCENT < 90" | bc -l) )); then
    echo "- 🟡 **CPU approaching limits** - Defer non-critical deployments, review top consumers" >> "$REPORT_FILE"
fi

if (( $(echo "$MEM_PERCENT >= 85" | bc -l) )) && (( $(echo "$MEM_PERCENT < 90" | bc -l) )); then
    echo "- 🟡 **Memory approaching limits** - Review memory-intensive pods, consider cleanup" >> "$REPORT_FILE"
fi

# Check for hot nodes
TEMP_HOT=$(mktemp)
oc adm top nodes --no-headers 2>/dev/null > "$TEMP_HOT" || true
HOT_NODES=$(awk '$4 ~ /[0-9]+%/ {gsub(/%/,"",$4); if ($4 >= 80) print $1}' "$TEMP_HOT")
rm -f "$TEMP_HOT"
if [ -n "$HOT_NODES" ]; then
    echo "- 🟡 **Hot nodes detected** - Consider rebalancing workloads:" >> "$REPORT_FILE"
    echo "$HOT_NODES" | while read node; do
        echo "  - $node" >> "$REPORT_FILE"
    done
fi

cat >> "$REPORT_FILE" << 'EOF'

### General Recommendations

- Review and rightsize over-provisioned workloads
- Cleanup unused PVCs and resources
- Monitor trends over time for capacity planning
- Consider HPA (Horizontal Pod Autoscaler) for dynamic workloads
- Schedule capacity expansion if sustained >80% utilization

---

## 📈 Capacity Forecast

EOF

# Calculate time to thresholds (simple linear projection)
# This is a basic forecast - could be improved with historical data
DAYS_TO_85=$(echo "scale=0; (85 - $CPU_PERCENT) / 0.5" | bc 2>/dev/null || echo "N/A")
DAYS_TO_90=$(echo "scale=0; (90 - $CPU_PERCENT) / 0.5" | bc 2>/dev/null || echo "N/A")

if [ "$DAYS_TO_85" != "N/A" ] && (( $(echo "$DAYS_TO_85 > 0" | bc -l) )); then
    echo "- **Time to 85% CPU threshold:** ~$DAYS_TO_85 days (assuming 0.5% growth/day)" >> "$REPORT_FILE"
elif (( $(echo "$CPU_PERCENT >= 85" | bc -l) )); then
    echo "- **Time to 85% CPU threshold:** Already exceeded" >> "$REPORT_FILE"
else
    echo "- **Time to 85% CPU threshold:** Low utilization, no immediate concern" >> "$REPORT_FILE"
fi

if [ "$DAYS_TO_90" != "N/A" ] && (( $(echo "$DAYS_TO_90 > 0" | bc -l) )); then
    echo "- **Time to 90% CPU threshold:** ~$DAYS_TO_90 days (assuming 0.5% growth/day)" >> "$REPORT_FILE"
elif (( $(echo "$CPU_PERCENT >= 90" | bc -l) )); then
    echo "- **Time to 90% CPU threshold:** Already exceeded" >> "$REPORT_FILE"
else
    echo "- **Time to 90% CPU threshold:** Sufficient headroom" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" << 'EOF'

> **Note:** Forecasts are based on simple linear projections and should be validated with historical trends and planned deployments.

---

## 🔧 Next Steps

- [ ] Review top consumers and identify optimization opportunities
- [ ] Check for unused resources (PVCs, deployments, services)
- [ ] Update capacity thresholds if workload patterns have changed
- [ ] Plan capacity expansion if sustained high utilization
- [ ] Share report with team for review

---

## 📁 Additional Reports

Generate detailed reports with:
- `./scripts/top-consumers.sh` - Detailed resource consumer analysis
- `./scripts/storage-capacity.sh --show-unused` - Find unused PVCs
- `./scripts/node-utilization.sh` - Per-node detailed breakdown
- `./scripts/proxmox-capacity.sh` - Proxmox host capacity

---

*Report generated by capacity-planning skill*
EOF

echo ""
echo "✅ Report generated successfully!"
echo ""
echo "📄 Report location: $REPORT_FILE"
echo ""
echo "📊 Quick view:"
echo "   cat $REPORT_FILE"
echo ""
echo "🔗 Create symlink to latest:"
echo "   ln -sf $(basename $REPORT_FILE) $REPORTS_DIR/latest.md"
echo ""

# Create symlink to latest
ln -sf "$(basename "$REPORT_FILE")" "$REPORTS_DIR/latest.md"
echo "✅ Symlink created: $REPORTS_DIR/latest.md -> $(basename $REPORT_FILE)"
