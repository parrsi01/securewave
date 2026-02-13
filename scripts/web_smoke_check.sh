#!/usr/bin/env bash
# Web Smoke Check — validates static site structure and responsiveness
set -euo pipefail

STATIC_DIR="${1:-$(dirname "$0")/../static}"
REPORT_FILE="${2:-/dev/stdout}"

pass=0
fail=0
warnings=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "ok" ]; then
    echo "[PASS] $desc" >> "$REPORT_FILE"
    pass=$((pass + 1))
  elif [ "$result" = "warn" ]; then
    echo "[WARN] $desc" >> "$REPORT_FILE"
    warnings=$((warnings + 1))
  else
    echo "[FAIL] $desc" >> "$REPORT_FILE"
    fail=$((fail + 1))
  fi
}

echo "=== SecureWave Web Smoke Check ===" > "$REPORT_FILE"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$REPORT_FILE"
echo "Static dir: $STATIC_DIR" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# --- HTML Pages ---
echo "--- HTML Pages ---" >> "$REPORT_FILE"
for page in index.html home.html login.html register.html dashboard.html billing.html vpn.html settings.html subscription.html download.html contact.html about.html services.html privacy.html terms.html 404.html error.html; do
  if [ -f "$STATIC_DIR/$page" ]; then
    check "$page exists" "ok"
  else
    check "$page exists" "fail"
  fi
done

# --- CSS ---
echo "" >> "$REPORT_FILE"
echo "--- CSS ---" >> "$REPORT_FILE"
if [ -f "$STATIC_DIR/css/web_ui_v1.css" ]; then
  check "web_ui_v1.css exists" "ok"
  lines=$(wc -l < "$STATIC_DIR/css/web_ui_v1.css")
  check "CSS has $lines lines (>500 expected)" "$([ "$lines" -gt 500 ] && echo ok || echo fail)"

  # Responsive breakpoint checks
  for bp in "min-width:640px" "min-width:768px" "min-width:1024px"; do
    if grep -q "$bp" "$STATIC_DIR/css/web_ui_v1.css"; then
      check "Breakpoint $bp present" "ok"
    else
      check "Breakpoint $bp present" "fail"
    fi
  done

  # Mobile-first checks
  if grep -q "max-width:639px" "$STATIC_DIR/css/web_ui_v1.css"; then
    check "Mobile-specific styles (max-width:639px)" "ok"
  else
    check "Mobile-specific styles (max-width:639px)" "warn"
  fi

  # Accessibility focus states
  if grep -q "focus-visible" "$STATIC_DIR/css/web_ui_v1.css"; then
    check "Focus-visible accessibility states" "ok"
  else
    check "Focus-visible accessibility states" "warn"
  fi

  # Touch target sizes
  if grep -q "min-height:44px" "$STATIC_DIR/css/web_ui_v1.css"; then
    check "44px touch targets for mobile" "ok"
  else
    check "44px touch targets for mobile" "warn"
  fi
else
  check "web_ui_v1.css exists" "fail"
fi

# --- JavaScript ---
echo "" >> "$REPORT_FILE"
echo "--- JavaScript ---" >> "$REPORT_FILE"
for js in site.js auth.js dashboard.js billing_center.js device_center.js; do
  if [ -f "$STATIC_DIR/js/$js" ]; then
    check "$js exists" "ok"
  else
    check "$js exists" "fail"
  fi
done

# --- Assets ---
echo "" >> "$REPORT_FILE"
echo "--- Assets ---" >> "$REPORT_FILE"
if [ -f "$STATIC_DIR/img/logo.svg" ]; then
  check "logo.svg exists" "ok"
else
  check "logo.svg exists" "fail"
fi

for font in Manrope-400.ttf Manrope-600.ttf Manrope-700.ttf; do
  if [ -f "$STATIC_DIR/fonts/$font" ]; then
    check "Font $font exists" "ok"
  else
    check "Font $font exists" "fail"
  fi
done

# --- Navigation consistency ---
echo "" >> "$REPORT_FILE"
echo "--- Navigation Consistency ---" >> "$REPORT_FILE"
nav_pages=0
for page in index.html home.html subscription.html download.html contact.html about.html; do
  if [ -f "$STATIC_DIR/$page" ] && grep -q 'class="nav"' "$STATIC_DIR/$page"; then
    nav_pages=$((nav_pages + 1))
  fi
done
check "Navigation present in $nav_pages/6 public pages" "$([ "$nav_pages" -ge 4 ] && echo ok || echo warn)"

# --- No hardcoded secrets ---
echo "" >> "$REPORT_FILE"
echo "--- Security Checks ---" >> "$REPORT_FILE"
secret_found=false
for f in "$STATIC_DIR"/js/*.js; do
  if grep -qiE '(sk_live|pk_live|secret_key|api_key.*=.*[a-z0-9]{20,})' "$f" 2>/dev/null; then
    check "No secrets in $(basename "$f")" "fail"
    secret_found=true
  fi
done
if [ "$secret_found" = false ]; then
  check "No hardcoded secrets in JS files" "ok"
fi

# --- Summary ---
echo "" >> "$REPORT_FILE"
echo "=== Summary ===" >> "$REPORT_FILE"
echo "Passed: $pass  |  Warnings: $warnings  |  Failed: $fail" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if [ "$fail" -gt 0 ]; then
  echo "Status: ISSUES FOUND" >> "$REPORT_FILE"
  exit 1
else
  echo "Status: ALL CHECKS PASSED" >> "$REPORT_FILE"
  exit 0
fi
