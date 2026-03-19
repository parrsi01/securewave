#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${1:-$ROOT_DIR/artifacts/SECRET_ATTESTATION_REPORT.md}"
TARGETS_FILE="${ROOT_DIR}/artifacts/secret_filter_targets.txt"
REPLACE_FILE="${ROOT_DIR}/artifacts/secret_replace_rules.txt"
TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

HISTORY_SCAN_EXCLUDES=(
  -- .
  ':(exclude)artifacts/*'
  ':(exclude)scripts/secret_scan.sh'
  ':(exclude)scripts/scan_git_history_for_secrets.sh'
  ':(exclude)scripts/pre-commit-hook.sh'
)

mkdir -p "$(dirname "$OUT_FILE")"

declare -a finding_rows=()
declare -a rotation_steps=()

append_unique() {
  local value="$1"
  shift
  local -n arr="$1"
  for item in "${arr[@]:-}"; do
    if [[ "$item" == "$value" ]]; then
      return 0
    fi
  done
  arr+=("$value")
}

scan_head() {
  local regex="$1"
  git -C "$ROOT_DIR" grep -nIE "$regex" -- . \
    ':(exclude)artifacts/*' \
    ':(exclude)securewave_app/ios/ThirdParty/*' \
    ':(exclude)scripts/secret_scan.sh' \
    ':(exclude)scripts/scan_git_history_for_secrets.sh' \
    ':(exclude)scripts/pre-commit-hook.sh' \
    2>/dev/null || true
}

scan_history() {
  local regex="$1"
  git -C "$ROOT_DIR" log --all -G "$regex" --date=short \
    --pretty=format:'%H|%h|%ad|%s' "${HISTORY_SCAN_EXCLUDES[@]}" 2>/dev/null || true
}

collect_paths_from_commits() {
  local regex="$1"
  local commit
  local tmp_file
  tmp_file="$(mktemp)"
  git -C "$ROOT_DIR" log --all -G "$regex" --pretty=format:'%H' "${HISTORY_SCAN_EXCLUDES[@]}" | head -n 50 >"$tmp_file" || true
  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    git -C "$ROOT_DIR" show --pretty='' --name-only "$commit" \
      | sed '/^$/d' \
      | sed '/^artifacts\//d' \
      | sed '/^securewave_app\/ios\/ThirdParty\//d'
  done <"$tmp_file" | sort -u
  rm -f "$tmp_file"
}

readarray -t PATTERNS <<'EOF'
AWS Access Key|critical|AKIA[0-9A-Z]{16}|Rotate AWS access keys and disable old IAM credentials.|yes
Stripe Live Secret|critical|sk_live_[0-9A-Za-z]{16,}|Rotate Stripe live secret keys and webhook signing secret.|yes
Stripe Test Secret|low|sk_test_[0-9A-Za-z]{16,}|Confirm test-only fixture use; rotate if ever used outside tests.|no
Stripe Live Publishable|medium|pk_live_[0-9A-Za-z]{16,}|Verify publishable key ownership and regenerate if uncertain.|yes
Stripe Webhook Secret|critical|whsec_[0-9A-Za-z]{16,}|Rotate Stripe webhook endpoint secret and invalidate previous signing credentials.|yes
SendGrid API Key|critical|SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}|Rotate SendGrid API key and revoke old key IDs.|yes
Slack Token|high|xox[baprs]-[0-9A-Za-z-]{10,}|Revoke Slack tokens and reissue with least privilege scopes.|yes
Private Key Block|critical|-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|Rotate corresponding private/public keypairs immediately.|yes
PGP Private Key Block|critical|-----BEGIN PGP PRIVATE KEY BLOCK-----|Revoke impacted PGP key material and issue replacement keys.|yes
Hetzner Token|critical|HETZNER_API_TOKEN[[:space:]]*=[[:space:]]*[A-Za-z0-9_-]{24,}|Rotate Hetzner token and re-scope API permissions.|yes
Hetzner Cloud Token|critical|HCLOUD_TOKEN[[:space:]]*=[[:space:]]*[A-Za-z0-9_-]{24,}|Rotate HCLOUD token and validate audit logs.|yes
JWT Secret Assignment|high|JWT_SECRET(_KEY)?[[:space:]]*=[[:space:]]*["\047]?[A-Za-z0-9_-]{16,}|Rotate JWT signing secrets and invalidate sessions.|no
Generic Secret Key Assignment|medium|SECRET_KEY[[:space:]]*=[[:space:]]*["\047]?[A-Za-z0-9_-]{16,}|Validate if placeholder/example; rotate if value was live.|no
EOF

critical_count=0
high_count=0
medium_count=0
low_count=0
clean=true
critical_head_hits=false

for row in "${PATTERNS[@]}"; do
  IFS='|' read -r name severity regex rotation collect_paths <<<"$row"

  head_hits="$(scan_head "$regex")"
  history_hits="$(scan_history "$regex")"
  commit_count=0
  if [[ -n "$history_hits" ]]; then
    commit_count="$(printf '%s\n' "$history_hits" | sed '/^$/d' | wc -l | tr -d ' ')"
  fi

  if [[ -n "$head_hits" || -n "$history_hits" ]]; then
    clean=false
    case "$severity" in
      critical) critical_count=$((critical_count + 1)) ;;
      high) high_count=$((high_count + 1)) ;;
      medium) medium_count=$((medium_count + 1)) ;;
      low) low_count=$((low_count + 1)) ;;
    esac
    append_unique "$rotation" rotation_steps
    if [[ "$severity" == "critical" && -n "$head_hits" ]]; then
      critical_head_hits=true
    fi

    head_sample="$(printf '%s\n' "$head_hits" | sed '/^$/d' | head -n 5)"
    history_sample="$(printf '%s\n' "$history_hits" | sed '/^$/d' | head -n 5 | sed 's/|/ - /g')"
    finding_rows+=("$name|$severity|$commit_count|${head_sample:-none}|${history_sample:-none}")

    if [[ "$collect_paths" == "yes" ]]; then
      collect_paths_from_commits "$regex" >>"$TARGETS_FILE.tmp"
    fi
  fi
done

if [[ -f "$TARGETS_FILE.tmp" ]]; then
  sort -u "$TARGETS_FILE.tmp" >"$TARGETS_FILE"
  rm -f "$TARGETS_FILE.tmp"
else
  : >"$TARGETS_FILE"
fi

cat >"$REPLACE_FILE" <<'EOF'
regex:sk_live_[0-9A-Za-z]{16,}==>sk_live_[REDACTED]
regex:sk_test_[0-9A-Za-z]{16,}==>sk_test_[REDACTED]
regex:pk_live_[0-9A-Za-z]{16,}==>pk_live_[REDACTED]
regex:pk_test_[0-9A-Za-z]{16,}==>pk_test_[REDACTED]
regex:whsec_[0-9A-Za-z]{16,}==>whsec_[REDACTED]
regex:AKIA[0-9A-Z]{16}==>AKIA[REDACTED]
regex:SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}==>SG.[REDACTED].[REDACTED]
regex:xox[baprs]-[0-9A-Za-z-]{10,}==>xox[REDACTED]
regex:(HETZNER_API_TOKEN|HCLOUD_TOKEN)\s*=\s*[A-Za-z0-9_-]{24,}==>\1=[REDACTED]
regex:(JWT_SECRET(?:_KEY)?|SECRET_KEY)\s*=\s*["']?[A-Za-z0-9_-]{16,}["']?==>\1=[REDACTED]
EOF

risk_classification="clean"
if (( critical_count > 0 )); then
  risk_classification="critical"
elif (( high_count > 0 )); then
  risk_classification="high"
elif (( medium_count > 0 )); then
  risk_classification="medium"
elif (( low_count > 0 )); then
  risk_classification="low"
fi

if [[ "$risk_classification" == "critical" && "$critical_head_hits" == "false" && ! -s "$TARGETS_FILE" ]]; then
  risk_classification="medium (historical pattern matches require manual verification)"
fi

{
  echo "# Secret History Attestation Report"
  echo ""
  echo "Generated (UTC): ${TIMESTAMP_UTC}"
  echo ""
  echo "## Scope"
  echo "- Working tree scan (tracked files)"
  echo "- Full git history scan (git log --all -G <pattern>)"
  echo ""
  echo "## Summary"
  echo "- Risk classification: **${risk_classification}**"
  echo "- Triggered detector classes: critical=${critical_count}, high=${high_count}, medium=${medium_count}, low=${low_count}"
  echo "- Candidate path list for history rewrite: \`artifacts/secret_filter_targets.txt\`"
  echo "- Replacement rules for history rewrite: \`artifacts/secret_replace_rules.txt\`"
  echo "- Manual rewrite helper: \`scripts/history_secret_remediation_filter_repo.sh\`"
  echo ""
  if [[ "$clean" == "true" ]]; then
    echo "## Attestation"
    echo "**No secret patterns detected in the current tree or commit history for configured detectors.**"
    echo ""
  else
    echo "## Findings"
    for item in "${finding_rows[@]}"; do
      IFS='|' read -r name severity commit_count head_sample history_sample <<<"$item"
      echo ""
      echo "### ${name}"
      echo "- Severity: ${severity}"
      echo "- History commit matches: ${commit_count}"
      echo "- Working tree sample:"
      if [[ "$head_sample" == "none" ]]; then
        echo "  - none"
      else
        printf '%s\n' "$head_sample" | sed 's/^/  - /'
      fi
      echo "- History sample:"
      if [[ "$history_sample" == "none" ]]; then
        echo "  - none"
      else
        printf '%s\n' "$history_sample" | sed 's/^/  - /'
      fi
    done
    echo ""
    echo "## Required Rotation Steps"
    for step in "${rotation_steps[@]}"; do
      echo "- ${step}"
    done
    echo ""
    echo "## Remediation Workflow (Manual, Non-Destructive by Default)"
    echo "1. Rotate all impacted credentials before any git history rewrite."
    echo "2. Review generated candidate paths in \`artifacts/secret_filter_targets.txt\`."
    echo "3. Review replacement rules in \`artifacts/secret_replace_rules.txt\`."
    echo "4. Run manual helper when approved:"
    echo "   - \`bash scripts/history_secret_remediation_filter_repo.sh\`"
    echo "5. Force-push rewritten refs and invalidate old clones."
    echo "6. Re-run this scan to confirm clean history."
    echo ""
    echo "## Clean Confirmation"
    echo "Not clean for configured detectors; manual review and/or history rewrite is required."
  fi
} >"$OUT_FILE"

echo "Wrote ${OUT_FILE}"
if [[ "$clean" == "true" ]]; then
  echo "Secret attestation: CLEAN"
  exit 0
fi
echo "Secret attestation: FINDINGS DETECTED"
exit 1
