#!/usr/bin/env bash
set -euo pipefail

# Manual remediation helper.
# This script does NOT run automatically in CI.
# Run only after team approval and backups.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS_FILE="${1:-$ROOT_DIR/artifacts/secret_filter_targets.txt}"
REPLACEMENTS_FILE="${2:-$ROOT_DIR/artifacts/secret_replace_rules.txt}"

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "ERROR: git-filter-repo is required. Install it first." >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR/.git" ]]; then
  echo "ERROR: not a git repository: $ROOT_DIR" >&2
  exit 1
fi

if [[ ! -f "$REPLACEMENTS_FILE" ]]; then
  echo "ERROR: replacement rules file not found: $REPLACEMENTS_FILE" >&2
  exit 1
fi

echo "WARNING: This rewrites git history."
echo "1) Ensure all secrets are rotated first."
echo "2) Ensure collaborators are notified."
echo "3) Ensure a backup exists (mirror clone)."

read -r -p "Type 'rewrite-history' to continue: " confirm
if [[ "$confirm" != "rewrite-history" ]]; then
  echo "Aborted."
  exit 1
fi

cd "$ROOT_DIR"
git tag "backup/pre-filter-repo-$(date -u +%Y%m%dT%H%M%SZ)"

args=(--force --replace-text "$REPLACEMENTS_FILE")

if [[ -s "$TARGETS_FILE" ]]; then
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ "$path" =~ ^# ]] && continue
    args+=(--path "$path")
  done < "$TARGETS_FILE"
  args+=(--invert-paths)
fi

git filter-repo "${args[@]}"

cat <<'TXT'
History rewrite completed locally.
Next steps:
1) Verify refs and app behavior locally.
2) Force-push all rewritten branches/tags:
   git push --force --all
   git push --force --tags
3) Invalidate old clones and rotate any impacted credentials.
TXT
