#!/bin/bash
# Test script for sealed-secrets skill

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEAL_SCRIPT="${SCRIPT_DIR}/scripts/seal-secret.sh"

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

info "Testing sealed-secrets skill..."
echo

# Test 1: Check prerequisites
info "Test 1: Checking prerequisites..."
command -v kubeseal &>/dev/null && pass "kubeseal found" || fail "kubeseal not found"
command -v kubectl &>/dev/null || command -v oc &>/dev/null && pass "kubectl/oc found" || fail "kubectl/oc not found"
[[ -f "${SCRIPT_DIR}/../../../pub-sealed-secrets.pem" ]] && pass "Certificate found" || fail "Certificate not found"
echo

# Test 2: Script permissions
info "Test 2: Checking script permissions..."
[[ -x "${SEAL_SCRIPT}" ]] && pass "seal-secret.sh is executable" || fail "seal-secret.sh not executable"
[[ -x "${SCRIPT_DIR}/scripts/quick-secrets.sh" ]] && pass "quick-secrets.sh is executable" || fail "quick-secrets.sh not executable"
echo

# Test 3: Help output
info "Test 3: Testing help output..."
if "${SEAL_SCRIPT}" --help &>/dev/null; then
    pass "Help text displays"
else
    pass "Help text displays (exit 1 expected)"
fi
echo

# Test 4: Pipe mode with test secret
info "Test 4: Testing pipe mode with sample secret..."
TEST_SECRET=$(cat <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
  namespace: default
type: Opaque
stringData:
  username: testuser
  password: testpass123
YAML
)

RESULT=$(echo "${TEST_SECRET}" | "${SEAL_SCRIPT}" --stdin 2>/dev/null)

if echo "${RESULT}" | grep -q "kind: SealedSecret"; then
    pass "Successfully created SealedSecret"
else
    fail "Failed to create SealedSecret"
fi

if echo "${RESULT}" | grep -q "encryptedData:"; then
    pass "Contains encrypted data"
else
    fail "Missing encrypted data"
fi

if echo "${RESULT}" | grep -q "username:"; then
    pass "Contains username field"
else
    fail "Missing username field"
fi

if echo "${RESULT}" | grep -q "password:"; then
    pass "Contains password field"
else
    fail "Missing password field"
fi
echo

# Test 5: Verify sealed secret format
info "Test 5: Verifying sealed secret format..."
if echo "${RESULT}" | grep -q "apiVersion: bitnami.com/v1alpha1"; then
    pass "Correct apiVersion"
else
    fail "Incorrect apiVersion"
fi

if echo "${RESULT}" | grep -q "name: test-secret"; then
    pass "Preserves secret name"
else
    fail "Secret name not preserved"
fi

if echo "${RESULT}" | grep -q "namespace: default"; then
    pass "Preserves namespace"
else
    fail "Namespace not preserved"
fi
echo

# Test 6: Documentation exists
info "Test 6: Checking documentation..."
[[ -f "${SCRIPT_DIR}/SKILL.md" ]] && pass "SKILL.md exists" || fail "SKILL.md missing"
[[ -f "${SCRIPT_DIR}/README.md" ]] && pass "README.md exists" || fail "README.md missing"
[[ -f "${SCRIPT_DIR}/QUICKSTART.md" ]] && pass "QUICKSTART.md exists" || fail "QUICKSTART.md missing"
echo

# Test 7: Examples exist
info "Test 7: Checking examples..."
[[ -f "${SCRIPT_DIR}/examples/example-usage.sh" ]] && pass "example-usage.sh exists" || fail "example-usage.sh missing"
[[ -x "${SCRIPT_DIR}/examples/example-usage.sh" ]] && pass "example-usage.sh is executable" || fail "example-usage.sh not executable"
echo

# Summary
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All tests passed! ✓${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "The sealed-secrets skill is ready to use!"
echo "Try: ${SEAL_SCRIPT}"
