#!/bin/bash
# test-skill.sh - Validate media-stack skill functionality
#
# Usage: ./test-skill.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

print_error() {
    echo -e "${RED}✗ $1${NC}"
    ((TESTS_FAILED++))
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    ((TESTS_PASSED++))
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

test_file_exists() {
    local file="$1"
    local desc="$2"
    
    if [[ -f "$file" ]]; then
        print_success "$desc exists"
    else
        print_error "$desc missing: $file"
    fi
}

test_script_executable() {
    local script="$1"
    local desc="$2"
    
    if [[ -x "$script" ]]; then
        print_success "$desc is executable"
    else
        print_error "$desc not executable: $script"
    fi
}

test_script_help() {
    local script="$1"
    local desc="$2"
    
    if "$script" --help &> /dev/null; then
        print_success "$desc has --help"
    else
        print_error "$desc missing --help"
    fi
}

test_template_syntax() {
    local template="$1"
    local desc="$2"
    
    # Basic YAML syntax check
    if grep -q "apiVersion:" "$template" && \
       grep -q "kind:" "$template" && \
       grep -q "metadata:" "$template"; then
        print_success "$desc has valid YAML structure"
    else
        print_error "$desc invalid YAML structure"
    fi
    
    # Check for required placeholders
    if grep -q "{{APP_NAME}}" "$template" && \
       grep -q "{{IMAGE}}" "$template" && \
       grep -q "{{PORT}}" "$template"; then
        print_success "$desc has required placeholders"
    else
        print_error "$desc missing required placeholders"
    fi
}

test_skill_structure() {
    print_header "Test 1: Skill Structure"
    
    test_file_exists "$SKILL_DIR/SKILL.md" "SKILL.md"
    test_file_exists "$SKILL_DIR/README.md" "README.md"
    test_file_exists "$SKILL_DIR/references/architecture.md" "architecture.md"
    test_file_exists "$SKILL_DIR/references/sidecar-pattern.md" "sidecar-pattern.md"
    test_file_exists "$SKILL_DIR/templates/media-deployment.yaml" "media-deployment.yaml template"
}

test_scripts() {
    print_header "Test 2: Helper Scripts"
    
    local scripts=(
        "generate-media-app.sh"
        "check-media-mounts.sh"
        "add-sidecars.sh"
        "troubleshoot-mounts.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_path="$SKILL_DIR/scripts/$script"
        test_file_exists "$script_path" "$script"
        test_script_executable "$script_path" "$script"
        test_script_help "$script_path" "$script"
    done
}

test_template() {
    print_header "Test 3: Deployment Template"
    
    local template="$SKILL_DIR/templates/media-deployment.yaml"
    test_template_syntax "$template" "media-deployment.yaml"
    
    # Check for sidecar containers
    if grep -q "name: rclone-zurg" "$template"; then
        print_success "Template includes rclone-zurg sidecar"
    else
        print_error "Template missing rclone-zurg sidecar"
    fi
    
    if grep -q "name: rclone-torbox" "$template"; then
        print_success "Template includes rclone-torbox sidecar"
    else
        print_error "Template missing rclone-torbox sidecar"
    fi
    
    # Check for init container
    if grep -q "name: init-dirs" "$template"; then
        print_success "Template includes init-dirs initContainer"
    else
        print_error "Template missing init-dirs initContainer"
    fi
    
    # Check for mountPropagation
    if grep -q "mountPropagation: Bidirectional" "$template"; then
        print_success "Template includes Bidirectional mountPropagation"
    else
        print_error "Template missing Bidirectional mountPropagation"
    fi
    
    if grep -q "mountPropagation: HostToContainer" "$template"; then
        print_success "Template includes HostToContainer mountPropagation"
    else
        print_error "Template missing HostToContainer mountPropagation"
    fi
    
    # Check for privileged securityContext
    if grep -q "privileged: true" "$template"; then
        print_success "Template includes privileged securityContext"
    else
        print_error "Template missing privileged securityContext"
    fi
    
    # Check for node affinity (preferred, not required)
    if grep -q "preferredDuringSchedulingIgnoredDuringExecution" "$template"; then
        print_success "Template uses preferred nodeAffinity (not required)"
    else
        print_error "Template missing preferred nodeAffinity"
    fi
}

test_documentation() {
    print_header "Test 4: Documentation"
    
    # Check SKILL.md frontmatter
    if head -10 "$SKILL_DIR/SKILL.md" | grep -q "^name: media-stack"; then
        print_success "SKILL.md has valid frontmatter"
    else
        print_error "SKILL.md missing valid frontmatter"
    fi
    
    # Check for key sections
    local sections=(
        "Quick Operations"
        "Deployment Workflows"
        "Common Issues"
        "Sidecar Pattern Reference"
        "Best Practices"
    )
    
    for section in "${sections[@]}"; do
        if grep -q "## $section" "$SKILL_DIR/SKILL.md"; then
            print_success "SKILL.md has '$section' section"
        else
            print_error "SKILL.md missing '$section' section"
        fi
    done
    
    # Check architecture.md key content
    if grep -q "Zone 1: Cloud Gateway" "$SKILL_DIR/references/architecture.md"; then
        print_success "architecture.md documents zone structure"
    else
        print_error "architecture.md missing zone structure"
    fi
    
    # Check sidecar-pattern.md key content
    if grep -q "Why Sidecars?" "$SKILL_DIR/references/sidecar-pattern.md"; then
        print_success "sidecar-pattern.md explains rationale"
    else
        print_error "sidecar-pattern.md missing rationale"
    fi
}

test_script_dry_run() {
    print_header "Test 5: Script Dry-Run (No Side Effects)"
    
    # Test generate-media-app.sh dry-run
    if "$SKILL_DIR/scripts/generate-media-app.sh" test-app test-image:latest 8080 --dry-run &> /dev/null; then
        print_success "generate-media-app.sh dry-run works"
    else
        print_error "generate-media-app.sh dry-run failed"
    fi
    
    # Note: Other scripts require cluster access, skip dry-run for now
    print_info "Skipping cluster-dependent script tests (check-media-mounts.sh, add-sidecars.sh)"
}

print_summary() {
    print_header "Test Summary"
    
    local total=$((TESTS_PASSED + TESTS_FAILED))
    echo "Tests passed: $TESTS_PASSED / $total"
    echo "Tests failed: $TESTS_FAILED / $total"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        print_success "All tests passed! Skill is ready to use."
        exit 0
    else
        echo ""
        print_error "Some tests failed. Fix issues before deploying."
        exit 1
    fi
}

# Main execution
main() {
    print_info "Testing media-stack skill..."
    print_info "Skill directory: $SKILL_DIR"
    
    test_skill_structure
    test_scripts
    test_template
    test_documentation
    test_script_dry_run
    
    print_summary
}

main "$@"
