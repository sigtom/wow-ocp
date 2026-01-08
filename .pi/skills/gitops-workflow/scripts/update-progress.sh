#!/bin/bash
# Update PROGRESS.md with dated entry

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

PROGRESS_FILE="PROGRESS.md"
DATE=$(date '+%Y-%m-%d')

usage() {
    cat <<EOF
${BLUE}Usage:${NC}
  $0 <message>

${BLUE}Add dated entry to PROGRESS.md${NC}

${BLUE}Examples:${NC}
  $0 "Deployed Bazarr for subtitle management"
  $0 "Fixed Sonarr PVC permissions issue"
  $0 "Updated media-stack documentation"

${BLUE}Format:${NC}
  Entries are added with today's date: [$DATE]
  Follow Scribe Protocol (append-only, never remove)

EOF
    exit 1
}

[[ $# -eq 0 ]] && usage

MESSAGE="$*"

# Check if PROGRESS.md exists
if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo -e "${RED}ERROR: $PROGRESS_FILE not found${NC}" >&2
    echo "Are you in the repository root?" >&2
    exit 1
fi

# Create temp file with new entry
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Read first line (header)
HEADER=$(head -1 "$PROGRESS_FILE")

# Create new entry
cat > "$TEMP_FILE" <<EOF
$HEADER

- [$DATE]: $MESSAGE

EOF

# Append rest of file (skip first empty line if present)
tail -n +2 "$PROGRESS_FILE" | sed '/^$/d;q' | head -1 >> "$TEMP_FILE" || true
tail -n +3 "$PROGRESS_FILE" >> "$TEMP_FILE"

# Show preview
echo -e "${BOLD}Preview of new entry:${NC}"
echo ""
echo -e "${GREEN}+ [$DATE]: $MESSAGE${NC}"
echo ""

# Confirm
read -p "Add this entry to PROGRESS.md? (y/n): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Update PROGRESS.md
cp "$TEMP_FILE" "$PROGRESS_FILE"

echo -e "${GREEN}✓ PROGRESS.md updated${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Review: ${BLUE}git diff PROGRESS.md${NC}"
echo "  2. Commit: ${BLUE}git add PROGRESS.md && git commit -m 'docs: update PROGRESS.md'${NC}"
echo "  3. Push: ${BLUE}git push origin main${NC}"
echo ""
echo -e "${YELLOW}Note: PROGRESS.md updates typically go directly to main (docs-only)${NC}"
