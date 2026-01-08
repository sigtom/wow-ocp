#!/bin/bash
# Create new feature branch following naming conventions

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

usage() {
    cat <<EOF
${BLUE}Usage:${NC}
  $0 <type> <name>

${BLUE}Create a new branch following GitOps conventions.${NC}

${BLUE}Types:${NC}
  feature   - New features or applications
  fix       - Bug fixes or issue resolution
  docs      - Documentation changes
  refactor  - Code restructuring
  chore     - Maintenance tasks

${BLUE}Examples:${NC}
  $0 feature add-bazarr-deployment
  $0 fix sonarr-pvc-permissions
  $0 docs update-media-stack-readme

EOF
    exit 1
}

[[ $# -ne 2 ]] && usage

TYPE=$1
NAME=$2

# Validate type
case "$TYPE" in
    feature|fix|docs|refactor|chore)
        ;;
    *)
        echo -e "${RED}ERROR: Invalid type '$TYPE'${NC}" >&2
        echo "Valid types: feature, fix, docs, refactor, chore" >&2
        exit 1
        ;;
esac

# Sanitize name (replace spaces/underscores with hyphens, lowercase)
NAME=$(echo "$NAME" | tr '_ ' '-' | tr '[:upper:]' '[:lower:]')

BRANCH_NAME="${TYPE}/${NAME}"

# Check if on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo -e "${YELLOW}Warning: Not on main branch (currently on '$CURRENT_BRANCH')${NC}"
    read -p "Switch to main first? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Switching to main...${NC}"
        git checkout main
    fi
fi

# Check if branch already exists
if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Branch '$BRANCH_NAME' already exists${NC}" >&2
    exit 1
fi

# Pull latest changes
echo -e "${BLUE}Pulling latest changes from origin/main...${NC}"
git pull origin main

# Create and checkout branch
echo -e "${GREEN}Creating branch: ${BRANCH_NAME}${NC}"
git checkout -b "$BRANCH_NAME"

# Verify
CURRENT=$(git branch --show-current)
if [[ "$CURRENT" == "$BRANCH_NAME" ]]; then
    echo -e "${GREEN}✓ Successfully created and checked out branch: ${BRANCH_NAME}${NC}"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Make your changes"
    echo "  2. Stage files: ${BLUE}git add <files>${NC}"
    echo "  3. Commit: ${BLUE}./scripts/commit.sh $TYPE \"<message>\"${NC}"
    echo "  4. Push: ${BLUE}git push origin $BRANCH_NAME${NC}"
    echo "  5. Create PR on GitHub"
else
    echo -e "${RED}ERROR: Failed to create branch${NC}" >&2
    exit 1
fi
