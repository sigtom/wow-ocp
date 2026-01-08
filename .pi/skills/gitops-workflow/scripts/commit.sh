#!/bin/bash
# Create conventional commit with validation

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

usage() {
    cat <<EOF
${BLUE}Usage:${NC}
  $0 <type> <message>

${BLUE}Create a conventional commit with validation.${NC}

${BLUE}Types:${NC}
  feat      - New feature or application
  fix       - Bug fix or issue resolution
  docs      - Documentation changes
  refactor  - Code restructuring
  chore     - Maintenance tasks
  ci        - CI/CD changes
  test      - Test changes

${BLUE}Examples:${NC}
  $0 feat "add Bazarr deployment"
  $0 fix "correct Sonarr PVC permissions"
  $0 docs "update media-stack README"

EOF
    exit 1
}

[[ $# -lt 2 ]] && usage

TYPE=$1
shift
MESSAGE="$*"

# Validate type
case "$TYPE" in
    feat|fix|docs|refactor|chore|ci|test|perf|style|revert)
        ;;
    *)
        echo -e "${RED}ERROR: Invalid type '$TYPE'${NC}" >&2
        echo "Valid types: feat, fix, docs, refactor, chore, ci, test, perf, style, revert" >&2
        exit 1
        ;;
esac

# Check if there are staged changes
if ! git diff --cached --quiet; then
    STAGED_FILES=$(git diff --cached --name-only)
    echo -e "${GREEN}Staged files:${NC}"
    echo "$STAGED_FILES" | sed 's/^/  /'
    echo ""
else
    echo -e "${RED}ERROR: No files staged for commit${NC}" >&2
    echo "Stage files with: git add <files>" >&2
    exit 1
fi

# Run validation on staged files
echo -e "${BLUE}Running validation checks...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Only validate if staged files include YAML
if echo "$STAGED_FILES" | grep -q "\.ya\?ml$"; then
    if [[ -x "$SCRIPT_DIR/validate.sh" ]]; then
        # Create temp dir with staged files
        TEMP_DIR=$(mktemp -d)
        trap "rm -rf $TEMP_DIR" EXIT
        
        echo "$STAGED_FILES" | while read -r file; do
            if [[ -f "$file" ]]; then
                mkdir -p "$TEMP_DIR/$(dirname "$file")"
                cp "$file" "$TEMP_DIR/$file"
            fi
        done
        
        if ! "$SCRIPT_DIR/validate.sh" "$TEMP_DIR" 2>&1 | grep -v "^$"; then
            echo ""
            echo -e "${RED}Validation failed. Fix errors before committing.${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Warning: validate.sh not found, skipping validation${NC}"
    fi
else
    echo -e "${YELLOW}No YAML files staged, skipping validation${NC}"
fi
echo ""

# Format commit message
COMMIT_MSG="${TYPE}: ${MESSAGE}"

# Commit
echo -e "${GREEN}Creating commit: ${COMMIT_MSG}${NC}"
git commit -m "$COMMIT_MSG"

# Success
echo -e "${GREEN}✓ Commit created successfully${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Push: ${BLUE}git push origin $(git branch --show-current)${NC}"
echo "  2. Create PR on GitHub"
echo "  3. After merge: verify ArgoCD sync"
