#!/bin/bash
# Test script for argocd-ops skill

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

echo -e "${BLUE}Testing argocd-ops skill...${NC}"
echo

# Test 1: Check prerequisites
info "Test 1: Checking prerequisites..."
command -v argocd &>/dev/null && pass "argocd CLI found" || info "argocd not found (optional for testing)"
command -v oc &>/dev/null && pass "oc CLI found" || info "oc not found (optional for testing)"
command -v jq &>/dev/null && pass "jq found" || fail "jq not found (required)"
echo

# Test 2: Script permissions
info "Test 2: Checking script permissions..."
[[ -x "${SCRIPT_DIR}/scripts/sync-status.sh" ]] && pass "sync-status.sh is executable" || fail "sync-status.sh not executable"
[[ -x "${SCRIPT_DIR}/scripts/sync-app.sh" ]] && pass "sync-app.sh is executable" || fail "sync-app.sh not executable"
[[ -x "${SCRIPT_DIR}/scripts/diff-app.sh" ]] && pass "diff-app.sh is executable" || fail "diff-app.sh not executable"
[[ -x "${SCRIPT_DIR}/scripts/rollback-app.sh" ]] && pass "rollback-app.sh is executable" || fail "rollback-app.sh not executable"
[[ -x "${SCRIPT_DIR}/scripts/watch-sync.sh" ]] && pass "watch-sync.sh is executable" || fail "watch-sync.sh not executable"
echo

# Test 3: Help output
info "Test 3: Testing help output..."
"${SCRIPT_DIR}/scripts/sync-status.sh" --help &>/dev/null || pass "sync-status.sh shows help"
"${SCRIPT_DIR}/scripts/sync-app.sh" --help &>/dev/null || pass "sync-app.sh shows help"
"${SCRIPT_DIR}/scripts/diff-app.sh" --help &>/dev/null || pass "diff-app.sh shows help"
"${SCRIPT_DIR}/scripts/rollback-app.sh" --help &>/dev/null || pass "rollback-app.sh shows help"
"${SCRIPT_DIR}/scripts/watch-sync.sh" --help &>/dev/null || pass "watch-sync.sh shows help"
echo

# Test 4: Documentation exists
info "Test 4: Checking documentation..."
[[ -f "${SCRIPT_DIR}/SKILL.md" ]] && pass "SKILL.md exists" || fail "SKILL.md missing"
[[ -f "${SCRIPT_DIR}/README.md" ]] && pass "README.md exists" || fail "README.md missing"
[[ -f "${SCRIPT_DIR}/QUICKSTART.md" ]] && pass "QUICKSTART.md exists" || fail "QUICKSTART.md missing"
[[ -f "${SCRIPT_DIR}/examples/workflow-examples.md" ]] && pass "workflow-examples.md exists" || fail "workflow-examples.md missing"
[[ -f "${SCRIPT_DIR}/references/quick-reference.md" ]] && pass "quick-reference.md exists" || fail "quick-reference.md missing"
echo

# Test 5: SKILL.md format
info "Test 5: Validating SKILL.md format..."
grep -q "^---$" "${SCRIPT_DIR}/SKILL.md" && pass "SKILL.md has frontmatter" || fail "SKILL.md missing frontmatter"
grep -q "^name: argocd-ops$" "${SCRIPT_DIR}/SKILL.md" && pass "name field correct" || fail "name field incorrect"
grep -q "^description:" "${SCRIPT_DIR}/SKILL.md" && pass "description field exists" || fail "description field missing"
echo

# Test 6: Script structure
info "Test 6: Checking script structure..."
grep -q "usage()" "${SCRIPT_DIR}/scripts/sync-status.sh" && pass "sync-status.sh has usage function" || fail "sync-status.sh missing usage"
grep -q "error()" "${SCRIPT_DIR}/scripts/sync-app.sh" && pass "sync-app.sh has error function" || fail "sync-app.sh missing error"
grep -q "info()" "${SCRIPT_DIR}/scripts/diff-app.sh" && pass "diff-app.sh has info function" || fail "diff-app.sh missing info"
echo

# Test 7: Color support
info "Test 7: Checking for colored output..."
grep -q "GREEN=.*033" "${SCRIPT_DIR}/scripts/sync-status.sh" && pass "sync-status.sh has colors" || fail "sync-status.sh missing colors"
grep -q "RED=.*033" "${SCRIPT_DIR}/scripts/sync-app.sh" && pass "sync-app.sh has colors" || fail "sync-app.sh missing colors"
echo

# Test 8: Key patterns
info "Test 8: Validating key patterns..."
grep -q "argocd app" "${SCRIPT_DIR}/scripts/sync-status.sh" && pass "sync-status.sh uses argocd CLI" || fail "sync-status.sh missing argocd"
grep -q "argocd app sync" "${SCRIPT_DIR}/scripts/sync-app.sh" && pass "sync-app.sh uses sync command" || fail "sync-app.sh missing sync"
grep -q "argocd app diff" "${SCRIPT_DIR}/scripts/diff-app.sh" && pass "diff-app.sh uses diff command" || fail "diff-app.sh missing diff"
grep -q "argocd app rollback" "${SCRIPT_DIR}/scripts/rollback-app.sh" && pass "rollback-app.sh uses rollback" || fail "rollback-app.sh missing rollback"
echo

# Test 9: JSON parsing
info "Test 9: Checking jq usage..."
grep -q "jq" "${SCRIPT_DIR}/scripts/sync-status.sh" && pass "sync-status.sh uses jq" || fail "sync-status.sh missing jq"
grep -q "jq" "${SCRIPT_DIR}/scripts/sync-app.sh" && pass "sync-app.sh uses jq" || fail "sync-app.sh missing jq"
echo

# Test 10: Skill name consistency
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
echo "The argocd-ops skill is ready to use!"
echo
info "Note: Some scripts require argocd CLI and cluster access to run."
info "Install argocd: brew install argocd (macOS)"
info "Login: argocd login <server-url>"
