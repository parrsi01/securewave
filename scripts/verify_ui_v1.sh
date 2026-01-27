#!/usr/bin/env bash
set -euo pipefail

# CI guard to ensure only UI v1.0 assets are in use
CSS_DIR="static/css"
EXPECTED_CSS="${CSS_DIR}/web_ui_v1.css"
HTML_FILES=(static/*.html)

if [[ ! -f "${EXPECTED_CSS}" ]]; then
  echo "Missing required stylesheet: ${EXPECTED_CSS}" >&2
  exit 1
fi

EXTRA_CSS=$(find "${CSS_DIR}" -maxdepth 1 -type f ! -name "web_ui_v1.css")
if [[ -n "${EXTRA_CSS}" ]]; then
  echo "Unexpected CSS files present:" >&2
  echo "${EXTRA_CSS}" >&2
  exit 1
fi

missing_css_refs=()
missing_build_meta=()
missing_ui_version=()
for file in "${HTML_FILES[@]}"; do
  if ! grep -q "web_ui_v1.css?v=" "${file}"; then
    missing_css_refs+=("${file}")
  fi
  if grep -q "href=\"/css/web_ui_v1.css\"" "${file}"; then
    echo "Cache-busting query string missing in ${file}" >&2
    exit 1
  fi
  stylesheet_count=$(grep -c "rel=\"stylesheet\"" "${file}")
  if [ "$stylesheet_count" -ne 1 ]; then
    echo "Unexpected number of stylesheet links in ${file} (found ${stylesheet_count})" >&2
    exit 1
  fi
  if grep -Eq "href=\"/css/(professional|ui_v1)\\.css\"" "${file}"; then
    echo "Legacy CSS reference found in ${file}" >&2
    exit 1
  fi
  if ! grep -q "name=\"build-timestamp\"" "${file}"; then
    missing_build_meta+=("${file}")
  fi
  if ! grep -q "UI_VERSION v1.0" "${file}"; then
    missing_ui_version+=("${file}")
  fi
 done

if (( ${#missing_css_refs[@]} > 0 )); then
  echo "HTML files missing web_ui_v1.css reference:" >&2
  printf ' - %s\n' "${missing_css_refs[@]}" >&2
  exit 1
fi

if (( ${#missing_build_meta[@]} > 0 )); then
  echo "HTML files missing build timestamp meta tag:" >&2
  printf ' - %s\n' "${missing_build_meta[@]}" >&2
  exit 1
fi

if (( ${#missing_ui_version[@]} > 0 )); then
  echo "HTML files missing UI_VERSION v1.0 marker:" >&2
  printf ' - %s\n' "${missing_ui_version[@]}" >&2
  exit 1
fi

python3 - <<'PY'
import glob
import os
import re
import sys

missing = []

html_pattern = re.compile(r'(?:href|src)="/([^"]+)"')
for path in glob.glob("static/*.html"):
    with open(path, "r", encoding="utf-8") as handle:
        content = handle.read()
    for ref in html_pattern.findall(content):
        ref = ref.split("?", 1)[0]
        if ref.endswith(".html") or ref.startswith("api/"):
            continue
        if ref.startswith(("css/", "js/", "img/", "downloads/")) or ref == "favicon.svg":
            asset_path = os.path.join("static", ref)
            if not os.path.exists(asset_path):
                missing.append(f"{path}:{ref}")

css_path = "static/css/web_ui_v1.css"
if os.path.exists(css_path):
    with open(css_path, "r", encoding="utf-8") as handle:
        css = handle.read()
    for match in re.findall(r"url\\(['\\\"](/[^'\\\"]+)['\\\"]\\)", css):
        ref = match.lstrip("/").split("?", 1)[0]
        if ref.startswith("fonts/"):
            asset_path = os.path.join("static", ref)
            if not os.path.exists(asset_path):
                missing.append(f"{css_path}:{ref}")

if missing:
    print("Missing static assets referenced by HTML/CSS:", file=sys.stderr)
    for item in missing:
        print(f" - {item}", file=sys.stderr)
    sys.exit(1)
PY

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

if command -v rg >/dev/null 2>&1; then
  if ! rg -q "AppUIv1.theme" securewave_app/lib/app.dart; then
    echo "Flutter app is not using AppUIv1.theme" >&2
    exit 1
  fi
else
  if ! grep -q "AppUIv1.theme" securewave_app/lib/app.dart; then
    echo "Flutter app is not using AppUIv1.theme" >&2
    exit 1
  fi
fi

echo "UI v1.0 guard checks passed"
