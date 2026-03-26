#!/usr/bin/env bash
# Automated secret scanner for SecureWave.
# Usage: ./scripts/secret_scan.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT/artifacts"
REPORT="$REPORT_DIR/SECRET_SCAN_REPORT.md"
TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$REPORT_DIR"

# Secret patterns (regex). Keep tight to avoid obvious false positives.
PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  'sk_live_[0-9A-Za-z]{16,}'
  'sk_test_[0-9A-Za-z]{16,}'
  'pk_live_[0-9A-Za-z]{16,}'
  'pk_test_[0-9A-Za-z]{16,}'
  'whsec_[0-9A-Za-z]{16,}'
  'SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}'
  'xox[baprs]-[0-9A-Za-z-]{10,}'
  '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
  '-----BEGIN PGP PRIVATE KEY BLOCK-----'
  'HETZNER_API_TOKEN\s*=\s*[A-Za-z0-9_-]{24,}'
  'HCLOUD_TOKEN\s*=\s*[A-Za-z0-9_-]{24,}'
  'JWT_SECRET(_KEY)?\s*=\s*["\047]?[A-Za-z0-9_\-]{16,}'
  'SECRET_KEY\s*=\s*["\047]?[A-Za-z0-9_\-]{16,}'
)

RG_BASE=(rg -n --no-heading --hidden)
RG_EXCLUDES=(
  --glob '!.git/**'
  --glob '!venv/**'
  --glob '!.venv/**'
  --glob '!docs/**'
  --glob '!tests/**'
  --glob '!tests_real/**'
  --glob '!sandbox/**'
  --glob '!dev_tools/sandbox/**'
  --glob '!tools/**/out/**'
  --glob '!tools/egress_proof/out/**'
  --glob '!.env.example.backend'
  --glob '!.env.production.example'
  --glob '!.env.template'
  --glob '!.env.*.template'
  --glob '!FINAL_REPORT.md'
  --glob '!SETUP_GUIDE.md'
  --glob '!PROJECT_COMPLETION_PHASES.md'
  --glob '!.github/workflows/ci-cd.yml'
  --glob '!scripts/dev_bootstrap.sh'
  --glob '!scripts/run_backend_tests.sh'
  --glob '!securewave_app/.dart_tool/**'
  --glob '!securewave_app/ios/ThirdParty/**'
  --glob '!artifacts/**'
  --glob '!scripts/secret_scan.sh'
  --glob '!scripts/scan_git_history_for_secrets.sh'
  --glob '!scripts/pre-commit-hook.sh'
)

HISTORY_PATH_EXCLUDES=(
  --
  .
  ':(exclude)artifacts/*'
  ':(exclude)docs/*'
  ':(exclude)tests/*'
  ':(exclude)tests_real/*'
  ':(exclude)sandbox/*'
  ':(exclude)dev_tools/sandbox/*'
  ':(exclude,glob)tools/*/out/**'
  ':(exclude,glob)tools/egress_proof/out/**'
  ':(exclude).env.example.backend'
  ':(exclude).env.production.example'
  ':(exclude).env.template'
  ':(exclude).env.*.template'
  ':(exclude)FINAL_REPORT.md'
  ':(exclude)SETUP_GUIDE.md'
  ':(exclude)PROJECT_COMPLETION_PHASES.md'
  ':(exclude).github/workflows/ci-cd.yml'
  ':(exclude)scripts/dev_bootstrap.sh'
  ':(exclude)scripts/run_backend_tests.sh'
  ':(exclude)scripts/secret_scan.sh'
  ':(exclude)scripts/scan_git_history_for_secrets.sh'
  ':(exclude)scripts/pre-commit-hook.sh'
)

scan_tree() {
  local pattern="$1"
  "${RG_BASE[@]}" "${RG_EXCLUDES[@]}" "$pattern" "$ROOT" 2>/dev/null \
    | awk -F: '{print $1 ":" $2}' \
    | sort -u
}

scan_history() {
  local pattern="$1"
  git -C "$ROOT" log --all -G "$pattern" --oneline --decorate "${HISTORY_PATH_EXCLUDES[@]}" 2>/dev/null \
    | sed 's/[[:space:]]\+$//' \
    | head -200
}

{
  echo "# Secret Scan Report"
  echo ""
  echo "Generated (UTC): $TIMESTAMP_UTC"
  echo ""
  echo "## Working Tree Findings"

  local_found=0
  for pattern in "${PATTERNS[@]}"; do
    matches=$(scan_tree "$pattern" || true)
    if [[ -n "$matches" ]]; then
      local_found=1
      echo ""
      printf 'Pattern: `%s`\n' "$pattern"
      echo ""
      echo "$matches" | sed 's/^/- /'
    fi
  done

  if [[ $local_found -eq 0 ]]; then
    echo "No matching secrets detected in the working tree."
  fi

  echo ""
  echo "## Git History Findings"
  history_found=0
  for pattern in "${PATTERNS[@]}"; do
    history=$(scan_history "$pattern" || true)
    if [[ -n "$history" ]]; then
      history_found=1
      echo ""
      printf 'Pattern: `%s`\n' "$pattern"
      echo ""
      echo "$history" | sed 's/^/- /'
    fi
  done

  if [[ $history_found -eq 0 ]]; then
    echo "No matching secrets detected in git history."
  fi

  echo ""
  echo "## Notes"
  echo "- This scan is heuristic and may flag test fixtures or documentation examples."
  echo "- If a real secret is detected, rotate it immediately and rewrite git history."
} > "$REPORT"

echo "Wrote $REPORT"

if grep -q "Pattern:" "$REPORT"; then
  echo "Potential secrets detected. Review $REPORT."
  exit 1
fi

echo "No secrets detected."
