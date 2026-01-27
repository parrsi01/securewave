#!/usr/bin/env bash
set -euo pipefail

# CI guard to ensure only UI v1.0 assets are in use
CSS_DIR="static/css"
EXPECTED_CSS="${CSS_DIR}/ui_v1.css"
HTML_FILES=(static/*.html)

if [[ ! -f "${EXPECTED_CSS}" ]]; then
  echo "Missing required stylesheet: ${EXPECTED_CSS}" >&2
  exit 1
fi

EXTRA_CSS=$(find "${CSS_DIR}" -maxdepth 1 -type f ! -name "ui_v1.css")
if [[ -n "${EXTRA_CSS}" ]]; then
  echo "Unexpected CSS files present:" >&2
  echo "${EXTRA_CSS}" >&2
  exit 1
fi

missing_css_refs=()
for file in "${HTML_FILES[@]}"; do
  if ! grep -q "ui_v1.css?v=" "${file}"; then
    missing_css_refs+=("${file}")
  fi
  if grep -q "href=\"/css/ui_v1.css\"" "${file}"; then
    echo "Cache-busting query string missing in ${file}" >&2
    exit 1
  fi
 done

if (( ${#missing_css_refs[@]} > 0 )); then
  echo "HTML files missing ui_v1.css reference:" >&2
  printf ' - %s\n' "${missing_css_refs[@]}" >&2
  exit 1
fi

if ! test -f securewave_app/lib/ui/app_ui_v1.dart; then
  echo "Missing Flutter UI v1.0 theme file" >&2
  exit 1
fi

EXTRA_THEME_FILES=$(find securewave_app/lib/ui -maxdepth 1 -type f ! -name "app_ui_v1.dart")
if [[ -n "${EXTRA_THEME_FILES}" ]]; then
  echo "Unexpected Flutter theme files present:" >&2
  echo "${EXTRA_THEME_FILES}" >&2
  exit 1
fi

if ! rg -q "AppUIv1.theme" securewave_app/lib/app.dart; then
  echo "Flutter app is not using AppUIv1.theme" >&2
  exit 1
fi

echo "UI v1.0 guard checks passed"
