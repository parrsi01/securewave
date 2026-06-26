#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Branch =="
git status --short --branch

echo
echo "== Tracked changes =="
git status --short --untracked-files=no

echo
echo "== Untracked files still visible after .gitignore =="
git ls-files --others --exclude-standard | sed 's#^#  #'

echo
echo "== Ignored generated roots =="
for path in artifacts data/usage securewaveapp_mobile PROJECT_STATUS_REPORT.txt securewave_app/build static/build; do
  if [[ -e "$path" ]]; then
    printf '  %s\n' "$path"
  fi
done
