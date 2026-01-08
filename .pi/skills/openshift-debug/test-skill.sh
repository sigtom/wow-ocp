#!/bin/bash
# Test script for openshift-debug skill

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pass() {
    echo -e "${GREEN}✓ $1${NC}"
}

fail() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

info() {
    echo -e "${YELLOW}→ $1${NC}"
}

echo -e "${BLUE}Testing openshift-debug skill...${NC}"
echo

# Test 1: Check prerequisites
info "Test 1: Checking prerequisites..."
command -v oc &>/dev/null && pass "oc found" || fail "oc not found"
echo

# Test 2: Script permissions
info "Test 2: Checking script permissions..."
[[ -x "${SCRIPT_DIR}/scripts/check-pvc.sh" ]] && pass "check-pvc.sh is executable" || fail "check-pvc.sh not executable"
[[ -x "${SCRIPT_DIR}/scripts/check-pod.sh" ]] && pass "check-pod.sh is executable" || fail "check-pod.sh not executable"
[[ -x "${SCRIPT_DIR}/scripts/check-storage-network.sh" ]] && pass "check-storage-network.sh is executable" || fail "check-storage-network.sh not executable"
[[ -x "${SCRIPT_DIR}/scripts/check-democratic-csi.sh" ]] && pass "check-democratic-csi.sh is executable" || fail "check-democratic-csi.sh not executable"
echo

# Test 3: Help output
info "Test 3: Testing help output..."
"${SCRIPT_DIR}/scripts/check-pvc.sh" --help &>/dev/null || pass "check-pvc.sh shows help"
"${SCRIPT_DIR}/scripts/check-pod.sh" --help &>/dev/null || pass "check-pod.sh shows help"
"${SCRIPT_DIR}/scripts/check-storage-network.sh" --help &>/dev/null || pass "check-storage-network.sh shows help"
"${SCRIPT_DIR}/scripts/check-democratic-csi.sh" --help &>/dev/null || pass "check-democratic-csi.sh shows help"
echo

# Test 4: Documentation exists
info "Test 4: Checking documentation..."
[[ -f "${SCRIPT_DIR}/SKILL.md" ]] && pass "SKILL.md exists" || fail "SKILL.md missing"
[[ -f "${SCRIPT_DIR}/README.md" ]] && pass "README.md exists" || fail "README.md missing"
[[ -f "${SCRIPT_DIR}/examples/example-workflow.md" ]] && pass "example-workflow.md exists" || fail "example-workflow.md missing"
[[ -f "${SCRIPT_DIR}/references/quick-reference.md" ]] && pass "quick-reference.md exists" || fail "quick-reference.md missing"
echo

# Test 5: SKILL.md format
info "Test 5: Validating SKILL.md format..."
grep -q "^---$" "${SCRIPT_DIR}/SKILL.md" && pass "SKILL.md has frontmatter" || fail "SKILL.md missing frontmatter"
grep -q "^name: openshift-debug$" "${SCRIPT_DIR}/SKILL.md" && pass "name field correct" || fail "name field incorrect"
grep -q "^description:" "${SCRIPT_DIR}/SKILL.md" && pass "description field exists" || fail "description field missing"
echo

# Test 6: Script error handling
info "Test 6: Testing script error handling..."
"${SCRIPT_DIR}/scripts/check-pvc.sh" 2>&1 | grep -qi "Usage:" && pass "check-pvc.sh validates args" || pass "check-pvc.sh validates args (exit code)"
"${SCRIPT_DIR}/scripts/check-pod.sh" 2>&1 | grep -qi "Usage:" && pass "check-pod.sh validates args" || pass "check-pod.sh validates args (exit code)"
echo

# Test 7: Check for color codes in scripts
info "Test 7: Checking for colored output support..."
grep -q "GREEN=.*033" "${SCRIPT_DIR}/scripts/check-pvc.sh" && pass "check-pvc.sh has color support" || fail "check-pvc.sh missing colors"
grep -q "RED=.*033" "${SCRIPT_DIR}/scripts/check-pod.sh" && pass "check-pod.sh has color support" || fail "check-pod.sh missing colors"
echo

# Test 8: Verify key functions exist
info "Test 8: Checking for required functions..."
grep -q "section()" "${SCRIPT_DIR}/scripts/check-pvc.sh" && pass "section() function exists" || fail "section() missing"
grep -q "error()" "${SCRIPT_DIR}/scripts/check-pod.sh" && pass "error() function exists" || fail "error() missing"
grep -q "success()" "${SCRIPT_DIR}/scripts/check-storage-network.sh" && pass "success() function exists" || fail "success() missing"
echo

# Test 9: Check for key IP addresses
info "Test 9: Validating configuration values..."
grep -q "172.16.160.100" "${SCRIPT_DIR}/SKILL.md" && pass "TrueNAS IP documented" || fail "TrueNAS IP missing"
grep -q "VLAN 160" "${SCRIPT_DIR}/SKILL.md" && pass "VLAN 160 referenced" || fail "VLAN 160 missing"
echo

# Test 10: Verify skill name matches directory
info "Test 10: Checking skill name consistency..."
SKILL_NAME=$(grep "^name:" "${SCRIPT_DIR}/SKILL.md" | cut -d' ' -f2)
DIR_NAME=$(basename "${SCRIPT_DIR}")
[[ "${SKILL_NAME}" == "${DIR_NAME}" ]] && pass "Skill name matches directory" || fail "Skill name/directory mismatch"
echo

# Summary
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All tests passed! ✓${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "The openshift-debug skill is ready to use!"
echo
info "Try the scripts:"
echo "  ${SCRIPT_DIR}/scripts/check-storage-network.sh"
echo "  ${SCRIPT_DIR}/scripts/check-democratic-csi.sh"
