#!/usr/bin/env bash
# =============================================================================
# check_xcworkspace_usage.sh
# =============================================================================
# Verifies that no scripts or CI workflows use Runner.xcodeproj for actual
# builds (guard verification tests are allowed).
#
# This script catches accidental .xcodeproj usage that would bypass CocoaPods.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "Checking for accidental Runner.xcodeproj usage..."
echo ""

errors=0

# Find xcodebuild commands that use -project Runner.xcodeproj
# Exclude: guard verification tests (lines containing "must FAIL" or "Guard verification")
while IFS= read -r file; do
  # Skip .venv and node_modules
  if [[ "$file" == *".venv"* ]] || [[ "$file" == *"node_modules"* ]]; then
    continue
  fi

  while IFS=: read -r line_num line_content; do
    # Check if this is a guard verification test (intentional negative test)
    context_before=$(sed -n "$((line_num > 2 ? line_num - 2 : 1)),$((line_num - 1))p" "$file" 2>/dev/null || true)
    context_after=$(sed -n "$((line_num + 1)),$((line_num + 2))p" "$file" 2>/dev/null || true)

    if echo "$context_before$line_content$context_after" | grep -qiE "(must fail|guard verification|expected to fail|negative test)"; then
      # This is an intentional negative test, skip it
      continue
    fi

    # Check if this is in a warning/error message (quoted or in echo)
    if echo "$line_content" | grep -qE '(echo|print|ERROR|WARN|".*xcodeproj.*")'; then
      # This is documentation/messaging, not actual usage
      continue
    fi

    # If it's an actual xcodebuild -project command, flag it
    if echo "$line_content" | grep -qE 'xcodebuild.*-project.*Runner\.xcodeproj'; then
      echo "ERROR: $file:$line_num"
      echo "  $line_content"
      echo ""
      echo "  This appears to use Runner.xcodeproj for an actual build."
      echo "  Use Runner.xcworkspace instead to include CocoaPods dependencies."
      echo ""
      errors=$((errors + 1))
    fi
  done < <(grep -n "Runner\.xcodeproj" "$file" 2>/dev/null || true)
done < <(find . -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.yaml" \) 2>/dev/null)

# Verify workspace guards exist
echo "Verifying workspace guards exist..."

guards=(
  "securewave_app/ios/scripts/ensure_workspace.sh"
  "securewave_app/macos/scripts/ensure_workspace.sh"
)

for guard in "${guards[@]}"; do
  if [[ -f "$guard" ]]; then
    echo "  OK: $guard"
  else
    echo "  MISSING: $guard"
    errors=$((errors + 1))
  fi
done

echo ""

if [[ $errors -gt 0 ]]; then
  echo "============================================"
  echo "FAIL: $errors issue(s) found"
  echo "============================================"
  exit 1
fi

echo "============================================"
echo "OK: No accidental .xcodeproj usage detected"
echo "============================================"
exit 0
