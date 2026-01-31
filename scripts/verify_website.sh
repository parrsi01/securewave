#!/bin/bash
# ------------------------------------------------------------------
# SecureWave Website Static Asset Verification
# Validates all required assets, links, and CSS references.
# Safe to re-run repeatedly (read-only checks).
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATIC_DIR="$ROOT_DIR/static"

echo "SecureWave Website Verification"
echo "================================"
echo ""

ERRORS=0
WARNINGS=0

pass() { echo "  OK: $1"; }
fail() { echo "  FAIL: $1"; ((ERRORS++)); }
warn() { echo "  WARN: $1"; ((WARNINGS++)); }

# ---- 1. Required files ----
echo "1. Checking required files..."
REQUIRED_FILES=(
  "css/web_ui_v1.css"
  "js/site.js"
  "js/auth.js"
  "js/dashboard.js"
  "js/bootstrap.bundle.min.js"
  "img/logo.svg"
  "favicon.svg"
  "fonts/Manrope-400.ttf"
  "fonts/Manrope-600.ttf"
  "fonts/Manrope-700.ttf"
  "fonts/Manrope-800.ttf"
  "index.html"
  "home.html"
  "login.html"
  "register.html"
  "dashboard.html"
  "subscription.html"
  "services.html"
  "settings.html"
  "contact.html"
  "privacy.html"
  "terms.html"
  "404.html"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$STATIC_DIR/$file" ]]; then
    pass "$file"
  else
    fail "Missing: $file"
  fi
done

# ---- 2. No legacy CSS ----
echo ""
echo "2. Checking for legacy CSS..."
if [[ -f "$STATIC_DIR/css/professional.css" ]]; then
  fail "Legacy professional.css still exists. Delete it."
else
  pass "No legacy professional.css"
fi

# Count CSS files (should be exactly 1)
CSS_COUNT=$(find "$STATIC_DIR/css" -name "*.css" -type f 2>/dev/null | wc -l)
if [[ "$CSS_COUNT" -eq 1 ]]; then
  pass "Exactly 1 CSS file (web_ui_v1.css)"
elif [[ "$CSS_COUNT" -eq 0 ]]; then
  fail "No CSS files found"
else
  warn "$CSS_COUNT CSS files found (expected 1)"
fi

# ---- 3. HTML file checks ----
echo ""
echo "3. Checking HTML references..."

for html_file in "$STATIC_DIR"/*.html; do
  basename=$(basename "$html_file")

  # Skip lightweight files
  if [[ "$basename" == "error.html" ]] || [[ "$basename" == "404.html" ]] || [[ "$basename" == "diagnostics.html" ]]; then
    continue
  fi

  # Check CSS reference
  if grep -q "web_ui_v1.css" "$html_file"; then
    pass "$basename -> web_ui_v1.css"
  else
    # login.html and register.html use auth.js only, check if they have CSS at all
    if grep -q 'rel="stylesheet"' "$html_file"; then
      fail "$basename: references a stylesheet but not web_ui_v1.css"
    fi
  fi

  # Check for legacy CSS references
  if grep -q "professional.css" "$html_file"; then
    fail "$basename: still references legacy professional.css"
  fi

  # Check UI version marker
  if grep -q 'UI_VERSION v1.0' "$html_file"; then
    pass "$basename -> UI_VERSION v1.0"
  else
    warn "$basename: missing UI_VERSION v1.0 marker"
  fi

  # Check build timestamp marker
  if grep -q 'build-timestamp' "$html_file"; then
    pass "$basename -> build-timestamp meta"
  else
    warn "$basename: missing build-timestamp meta tag"
  fi
done

# ---- 4. Check for broken internal links ----
echo ""
echo "4. Checking internal links..."

for html_file in "$STATIC_DIR"/*.html; do
  basename_file=$(basename "$html_file")
  # Extract href values that point to local pages
  while IFS= read -r link; do
    # Strip query params and anchors
    clean_link=$(echo "$link" | sed 's/[?#].*//')
    # Skip external links, javascript:, mailto:, empty
    if [[ -z "$clean_link" ]] || [[ "$clean_link" == http* ]] || [[ "$clean_link" == javascript* ]] || [[ "$clean_link" == mailto* ]]; then
      continue
    fi
    # Remove leading /
    clean_link="${clean_link#/}"
    if [[ -n "$clean_link" ]] && [[ ! -f "$STATIC_DIR/$clean_link" ]]; then
      warn "$basename_file: broken link -> /$clean_link"
    fi
  done < <(grep -oP 'href="\K[^"]+' "$html_file" 2>/dev/null || true)
done

# ---- 5. Summary ----
echo ""
echo "================================"
echo "Errors: $ERRORS   Warnings: $WARNINGS"
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo "Website verification passed."
  exit 0
else
  echo "Website verification FAILED. Fix errors above."
  exit 1
fi
