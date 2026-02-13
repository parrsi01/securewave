#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IGNORE_PATHS=(
  "securewave_app/ios/ThirdParty/"
  "docs/"
  "artifacts/"
  "sandbox/realism/"
  "FULL_SIM_REPORT.md"
  "SECURITY_SCRUB_REPORT.md"
  "scripts/check_no_azure_refs.sh"
)

pattern='azure|Azure'

args=()
for path in "${IGNORE_PATHS[@]}"; do
  args+=(--glob "!${path}**")
done

if rg -n "$pattern" . "${args[@]}" >/tmp/azure_refs.out; then
  echo "ERROR: Azure reference(s) detected in active code/config paths:"
  cat /tmp/azure_refs.out
  exit 1
fi

echo "OK: no Azure references in active code/config paths."
