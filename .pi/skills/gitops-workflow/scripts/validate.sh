#!/bin/bash
# Validate Kubernetes manifests before commit

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

TARGET_PATH="${1:-.}"
ERRORS=0

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}${BOLD}                   Manifest Validation Report                       ${NC}${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Target:${NC} $TARGET_PATH"
echo ""

# Check prerequisites
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${YELLOW}Warning: '$1' not found, skipping related checks${NC}"
        return 1
    fi
    return 0
}

# 1. YAML Syntax Check
echo -e "${BOLD}[1/6] YAML Syntax Validation${NC}"
if check_tool yamllint; then
    if find "$TARGET_PATH" -name "*.yaml" -o -name "*.yml" | xargs yamllint -f parsable 2>&1 | grep -v "^$"; then
        echo -e "${RED}✗ YAML syntax errors found${NC}"
        ((ERRORS++))
    else
        echo -e "${GREEN}✓ YAML syntax valid${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Skipped (yamllint not installed)${NC}"
fi
echo ""

# 2. Kustomize Build Check
echo -e "${BOLD}[2/6] Kustomize Build Validation${NC}"
if check_tool kustomize; then
    KUSTOMIZE_DIRS=$(find "$TARGET_PATH" -name "kustomization.yaml" -exec dirname {} \;)
    if [[ -n "$KUSTOMIZE_DIRS" ]]; then
        KUSTOMIZE_ERRORS=0
        while IFS= read -r dir; do
            echo -n "  Checking $dir... "
            if kustomize build "$dir" >/dev/null 2>&1; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗${NC}"
                kustomize build "$dir" 2>&1 | sed 's/^/    /'
                ((KUSTOMIZE_ERRORS++))
            fi
        done <<< "$KUSTOMIZE_DIRS"
        
        if [[ $KUSTOMIZE_ERRORS -gt 0 ]]; then
            echo -e "${RED}✗ Kustomize build failed for $KUSTOMIZE_ERRORS directories${NC}"
            ((ERRORS++))
        else
            echo -e "${GREEN}✓ All kustomize builds successful${NC}"
        fi
    else
        echo -e "${YELLOW}⊘ No kustomization.yaml files found${NC}"
    fi
else
    echo -e "${YELLOW}⊘ Skipped (kustomize not installed)${NC}"
fi
echo ""

# 3. Resource Limits Check
echo -e "${BOLD}[3/6] Resource Limits Validation${NC}"
DEPLOYMENTS=$(find "$TARGET_PATH" -name "*.yaml" -exec grep -l "kind: Deployment" {} \;)
if [[ -n "$DEPLOYMENTS" ]]; then
    MISSING_LIMITS=0
    while IFS= read -r file; do
        if ! grep -q "resources:" "$file"; then
            echo -e "${RED}✗ Missing resources in: $file${NC}"
            ((MISSING_LIMITS++))
        fi
    done <<< "$DEPLOYMENTS"
    
    if [[ $MISSING_LIMITS -gt 0 ]]; then
        echo -e "${RED}✗ $MISSING_LIMITS deployments missing resource limits${NC}"
        ((ERRORS++))
    else
        echo -e "${GREEN}✓ All deployments have resource limits${NC}"
    fi
else
    echo -e "${YELLOW}⊘ No Deployment resources found${NC}"
fi
echo ""

# 4. Secrets Check
echo -e "${BOLD}[4/6] Secrets Validation${NC}"
RAW_SECRETS=$(find "$TARGET_PATH" -name "*.yaml" -exec grep -l "kind: Secret$" {} \; | grep -v "/tmp/" || true)
if [[ -n "$RAW_SECRETS" ]]; then
    echo -e "${RED}✗ Raw Secret resources found (use SealedSecret instead):${NC}"
    echo "$RAW_SECRETS" | sed 's/^/  /'
    ((ERRORS++))
else
    echo -e "${GREEN}✓ No raw secrets found (only SealedSecrets or no secrets)${NC}"
fi
echo ""

# 5. Ingress Annotations Check
echo -e "${BOLD}[5/6] Ingress Annotations Validation${NC}"
INGRESSES=$(find "$TARGET_PATH" -name "*.yaml" -exec grep -l "kind: Ingress\|kind: Route" {} \; || true)
if [[ -n "$INGRESSES" ]]; then
    MISSING_ANNOTATIONS=0
    while IFS= read -r file; do
        if ! grep -q "cert-manager.io/cluster-issuer" "$file"; then
            echo -e "${YELLOW}⚠ Missing cert-manager annotation in: $file${NC}"
            ((MISSING_ANNOTATIONS++))
        fi
    done <<< "$INGRESSES"
    
    if [[ $MISSING_ANNOTATIONS -gt 0 ]]; then
        echo -e "${YELLOW}⚠ $MISSING_ANNOTATIONS ingress(es) missing cert-manager annotations${NC}"
        echo "  (This is a warning, not an error)"
    else
        echo -e "${GREEN}✓ All ingresses have cert-manager annotations${NC}"
    fi
else
    echo -e "${YELLOW}⊘ No Ingress/Route resources found${NC}"
fi
echo ""

# 6. Dry-run Check (requires cluster access)
echo -e "${BOLD}[6/6] Cluster Dry-Run Validation${NC}"
if check_tool oc && oc whoami &>/dev/null; then
    YAML_FILES=$(find "$TARGET_PATH" -name "*.yaml" ! -name "kustomization.yaml")
    if [[ -n "$YAML_FILES" ]]; then
        DRYRUN_ERRORS=0
        for file in $YAML_FILES; do
            if ! oc apply --dry-run=client -f "$file" &>/dev/null; then
                echo -e "${RED}✗ Dry-run failed: $file${NC}"
                oc apply --dry-run=client -f "$file" 2>&1 | sed 's/^/  /'
                ((DRYRUN_ERRORS++))
            fi
        done
        
        if [[ $DRYRUN_ERRORS -gt 0 ]]; then
            echo -e "${RED}✗ Dry-run failed for $DRYRUN_ERRORS files${NC}"
            ((ERRORS++))
        else
            echo -e "${GREEN}✓ All files pass dry-run validation${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⊘ Skipped (not logged into cluster)${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✓ VALIDATION PASSED${NC}"
    echo -e "All checks completed successfully. Safe to commit."
    exit 0
else
    echo -e "${RED}${BOLD}✗ VALIDATION FAILED${NC}"
    echo -e "Found $ERRORS critical error(s). Fix before committing."
    echo ""
    echo -e "${BOLD}Common fixes:${NC}"
    echo "  - YAML syntax: Check indentation, quotes, colons"
    echo "  - Kustomize: Verify kustomization.yaml references"
    echo "  - Resources: Add requests/limits to all Deployments"
    echo "  - Secrets: Use kubeseal to create SealedSecret"
    echo "  - Dry-run: Check API versions and required fields"
    exit 1
fi
