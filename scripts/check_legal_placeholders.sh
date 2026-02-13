#!/usr/bin/env bash
# Fail CI if any legal/policy page contains placeholder text.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATIC_DIR="$ROOT_DIR/static"
ARTIFACT_DIR="$ROOT_DIR/artifacts/legal_pages"

LEGAL_FILES=(
  "$STATIC_DIR/privacy.html"
  "$STATIC_DIR/terms.html"
  "$STATIC_DIR/data_retention.html"
  "$STATIC_DIR/acceptable_use.html"
)

PLACEHOLDER_PATTERNS=(
  "TODO"
  "TBD"
  "PLACEHOLDER"
  "Lorem ipsum"
  "REPLACE_ME"
  "INSERT (YOUR|COMPANY|LEGAL)"
  "\\[\\s*INSERT\\s*\\]"
  "\\[\\s*TODO\\s*\\]"
  "\\[COMPANY\\]"
  "\\[DATE\\]"
  "\\[EMAIL\\]"
  "\\[ADDRESS\\]"
)

missing=0
for f in "${LEGAL_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Missing legal page: $f"
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

found=0
echo "Legal placeholder scan:"
for f in "${LEGAL_FILES[@]}"; do
  for pattern in "${PLACEHOLDER_PATTERNS[@]}"; do
    if grep -Ein "$pattern" "$f" >/dev/null 2>&1; then
      echo "ERROR: Placeholder pattern '$pattern' found in $(basename "$f"):"
      grep -Ein "$pattern" "$f" || true
      found=1
    fi
  done
done

mkdir -p "$ARTIFACT_DIR"
report="$ARTIFACT_DIR/placeholder_free.md"
{
  echo "# Legal Placeholder Guard"
  echo ""
  echo "- Result: $( [[ "$found" -eq 0 ]] && echo PASS || echo FAIL )"
  echo "- Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "## Checked Files"
  for f in "${LEGAL_FILES[@]}"; do
    echo "- \`static/$(basename "$f")\`"
  done
  echo ""
  echo "## Placeholder Patterns"
  for pattern in "${PLACEHOLDER_PATTERNS[@]}"; do
    echo "- \`$pattern\`"
  done
} > "$report"

if [[ "$found" -ne 0 ]]; then
  echo ""
  echo "Legal placeholder guard FAILED."
  echo "See: $report"
  exit 2
fi

echo "Legal placeholder guard passed."
echo "Wrote: $report"
exit 0
