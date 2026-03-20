#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENVIRONMENT_NAME="production"
REPO_SLUG="${GITHUB_REPOSITORY:-}"
REF_NAME="$(git rev-parse --abbrev-ref HEAD)"
OUTPUT_PATH="${ROOT_DIR}/artifacts/release_operator_readiness_report.md"

VERIFY_SCRIPT_PATH="${VERIFY_PRODUCTION_ENV_SCRIPT:-scripts/verify_production_env.sh}"
SYNC_SCRIPT_PATH="${SYNC_GITHUB_RELEASE_SECRETS_SCRIPT:-scripts/sync_github_release_secrets.sh}"
AUDIT_SCRIPT_PATH="${AUDIT_GITHUB_RELEASE_SECRETS_SCRIPT:-scripts/audit_github_release_secrets.sh}"
WORKFLOW_PATH="${RELEASE_WORKFLOW_FILE:-.github/workflows/flutter-release.yml}"

usage() {
  cat <<'EOF'
Usage: bash scripts/generate_release_readiness_report.sh [--output path] [--env production] [--repo owner/repo] [--ref git-ref]

Runs the SecureWave release operator checks in dry-run mode and writes a markdown
artifact summarizing:
- local env completeness
- GitHub secret sync readiness
- GitHub secret inventory readiness
- workflow dispatch readiness
- exact remaining blockers
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || fail "--output requires a value."
      OUTPUT_PATH="$2"
      shift 2
      ;;
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
    --ref)
      [[ $# -ge 2 ]] || fail "--ref requires a value."
      REF_NAME="$2"
      shift 2
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

if [[ -z "$REPO_SLUG" ]]; then
  REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
[[ -n "$REPO_SLUG" ]] || fail "Unable to determine GitHub repository slug. Set GITHUB_REPOSITORY or pass --repo owner/repo."

mkdir -p "$(dirname "$OUTPUT_PATH")"

run_capture() {
  local __outvar="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  set +e
  "$@" >"$tmp" 2>&1
  local status=$?
  set -e
  printf -v "$__outvar" '%s' "$(cat "$tmp")"
  rm -f "$tmp"
  return "$status"
}

status_label() {
  if [[ "$1" -eq 0 ]]; then
    echo "PASS"
  else
    echo "FAIL"
  fi
}

sanitize_block() {
  printf '%s\n' "$1" | sed -e 's/\r$//'
}

collect_blockers() {
  printf '%s\n' "$1" | awk '
    /^ERROR:/ {print; next}
    /^Missing required release secrets:/ {flag=1; next}
    /^Local environment is missing required values for:/ {flag=1; next}
    flag && /^ - / {sub(/^ - /, "", $0); print; next}
    flag && !/^ - / {flag=0}
  '
}

verify_output=""
sync_output=""
audit_output=""

verify_status=0
sync_status=0
audit_status=0

if run_capture verify_output env VERIFY_STRICT=true ENVIRONMENT=production bash "$VERIFY_SCRIPT_PATH"; then
  verify_status=0
else
  verify_status=$?
fi
if run_capture sync_output bash "$SYNC_SCRIPT_PATH" --dry-run --env "$ENVIRONMENT_NAME" --repo "$REPO_SLUG"; then
  sync_status=0
else
  sync_status=$?
fi
if run_capture audit_output bash "$AUDIT_SCRIPT_PATH" "$ENVIRONMENT_NAME"; then
  audit_status=0
else
  audit_status=$?
fi

workflow_ready="PASS"
if [[ ! -f "$WORKFLOW_PATH" ]]; then
  workflow_ready="FAIL"
fi
if [[ "$verify_status" -ne 0 || "$sync_status" -ne 0 || "$audit_status" -ne 0 ]]; then
  workflow_ready="FAIL"
fi

all_blockers="$(
  {
    collect_blockers "$verify_output"
    collect_blockers "$sync_output"
    collect_blockers "$audit_output"
  } | awk 'NF && !seen[$0]++'
)"

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat >"$OUTPUT_PATH" <<EOF
# SecureWave Release Operator Readiness Report

- Generated at: \`${generated_at}\`
- Repository: \`${REPO_SLUG}\`
- Environment: \`${ENVIRONMENT_NAME}\`
- Ref: \`${REF_NAME}\`
- Workflow: \`${WORKFLOW_PATH}\`

## Summary

- Local env readiness: **$(status_label "$verify_status")**
- GitHub secret sync readiness: **$(status_label "$sync_status")**
- GitHub secret inventory readiness: **$(status_label "$audit_status")**
- Workflow dispatch readiness: **${workflow_ready}**

## Exact Remaining Blockers

EOF

if [[ -n "$all_blockers" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    printf -- '- %s\n' "$line" >>"$OUTPUT_PATH"
  done <<<"$all_blockers"
else
  echo "- None" >>"$OUTPUT_PATH"
fi

cat >>"$OUTPUT_PATH" <<EOF

## Local Env Check Output

\`\`\`text
$(sanitize_block "$verify_output")
\`\`\`

## GitHub Secret Sync Dry-Run Output

\`\`\`text
$(sanitize_block "$sync_output")
\`\`\`

## GitHub Secret Audit Output

\`\`\`text
$(sanitize_block "$audit_output")
\`\`\`

## Next Step

\`\`\`bash
bash scripts/setup_production_env.sh --write-env-file ~/.config/securewave/release.env
set -a && source ~/.config/securewave/release.env && set +a
bash scripts/run_release_ops.sh --dry-run
\`\`\`
EOF

echo "INFO: Wrote release readiness report to $OUTPUT_PATH"
if [[ "$verify_status" -eq 0 && "$sync_status" -eq 0 && "$audit_status" -eq 0 && "$workflow_ready" == "PASS" ]]; then
  echo "OK: release operator readiness is green."
  exit 0
fi

echo "WARN: release operator readiness has blockers."
exit 1
