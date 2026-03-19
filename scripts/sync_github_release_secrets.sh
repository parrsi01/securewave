#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENVIRONMENT_NAME="production"
REPO_SLUG="${GITHUB_REPOSITORY:-}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: bash scripts/sync_github_release_secrets.sh [--env production] [--repo owner/repo] [--dry-run]

Reads required SecureWave release secret names from scripts/release_preflight.sh and
pushes already-set local environment variables into the target GitHub Actions
environment. Values are never printed.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || fail "$name is required."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      [[ $# -ge 2 ]] || fail "--env requires a value."
      ENVIRONMENT_NAME="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || fail "--repo requires a value."
      REPO_SLUG="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_cmd gh
require_cmd python3

if [[ -z "$REPO_SLUG" ]]; then
  REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
[[ -n "$REPO_SLUG" ]] || fail "Unable to determine GitHub repository slug. Set GITHUB_REPOSITORY or pass --repo owner/repo."

required_names="$(
python3 - <<'PY'
from pathlib import Path
import re

script = Path("scripts/release_preflight.sh").read_text(encoding="utf-8")
required = set(re.findall(r'require_var\s+"([A-Z0-9_]+)"', script))
required.update({"FROM_EMAIL", "AUTH_ENCRYPTION_KEY", "WG_ENCRYPTION_KEY"})
for name in sorted(required):
    print(name)
PY
)"

mapfile -t required_array <<<"$required_names"

missing_local=()
synced=0

echo "SecureWave GitHub release secret sync"
echo "Repository: $REPO_SLUG"
echo "Environment: $ENVIRONMENT_NAME"
echo "Mode: $([[ "$DRY_RUN" == "true" ]] && echo dry-run || echo apply)"
echo

for name in "${required_array[@]}"; do
  value="${!name-}"
  if [[ -z "$value" ]]; then
    missing_local+=("$name")
    echo "[skip] $name (local env missing)"
    continue
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[plan] $name -> $ENVIRONMENT_NAME"
    synced=$((synced + 1))
    continue
  fi

  gh secret set "$name" --repo "$REPO_SLUG" --env "$ENVIRONMENT_NAME" --body "$value" >/dev/null
  echo "[sync] $name -> $ENVIRONMENT_NAME"
  synced=$((synced + 1))
done

echo
echo "Secrets prepared: $synced"
echo "Missing local values: ${#missing_local[@]}"

if (( ${#missing_local[@]} > 0 )); then
  echo
  echo "Local environment is missing required values for:"
  printf ' - %s\n' "${missing_local[@]}"
  echo
  echo "Tip: populate them locally first with scripts/setup_production_env.sh or your secret manager."
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "OK: dry-run completed."
else
  echo "OK: GitHub production secrets synced."
fi
