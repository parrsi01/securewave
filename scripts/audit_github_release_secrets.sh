#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENVIRONMENT_NAME="${1:-production}"
REPO_SLUG="${GITHUB_REPOSITORY:-}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || fail "$name is required."
}

require_cmd gh
require_cmd python3

if [[ -z "$REPO_SLUG" ]]; then
  REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
[[ -n "$REPO_SLUG" ]] || fail "Unable to determine GitHub repository slug. Set GITHUB_REPOSITORY or run inside a gh repo context."

required_secrets="$(
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

mapfile -t required_array <<<"$required_secrets"

repo_secret_output="$(gh secret list --repo "$REPO_SLUG" 2>/dev/null || true)"
env_secret_output="$(gh secret list --repo "$REPO_SLUG" --env "$ENVIRONMENT_NAME" 2>/dev/null || true)"

declare -A repo_secrets=()
declare -A env_secrets=()
declare -A union_secrets=()

while IFS=$'\t' read -r name _; do
  [[ -n "${name:-}" ]] || continue
  repo_secrets["$name"]=1
  union_secrets["$name"]=repo
done <<<"$repo_secret_output"

while IFS=$'\t' read -r name _; do
  [[ -n "${name:-}" ]] || continue
  env_secrets["$name"]=1
  union_secrets["$name"]=environment
done <<<"$env_secret_output"

missing=()
echo "SecureWave release secret audit"
echo "Repository: $REPO_SLUG"
echo "Environment: $ENVIRONMENT_NAME"
echo
printf "%-32s %-12s\n" "SECRET" "SOURCE"
printf "%-32s %-12s\n" "------" "------"
for name in "${required_array[@]}"; do
  if [[ -n "${env_secrets[$name]:-}" ]]; then
    printf "%-32s %-12s\n" "$name" "environment"
  elif [[ -n "${repo_secrets[$name]:-}" ]]; then
    printf "%-32s %-12s\n" "$name" "repository"
  else
    printf "%-32s %-12s\n" "$name" "missing"
    missing+=("$name")
  fi
done

echo
echo "Repo secret count: ${#repo_secrets[@]}"
echo "Environment secret count: ${#env_secrets[@]}"

if (( ${#missing[@]} > 0 )); then
  echo
  echo "Missing required release secrets:"
  printf ' - %s\n' "${missing[@]}"
  exit 1
fi

echo
echo "OK: all required release secrets are present."
