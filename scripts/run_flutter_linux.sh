#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
app_dir="$repo_root/securewave_app"

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter is required. Install Flutter and rerun make flutter-run." >&2
  exit 2
}

[[ -d "$app_dir" && -f "$app_dir/pubspec.yaml" ]] || {
  echo "securewave_app/pubspec.yaml is missing; run this from the repository root." >&2
  exit 2
}

api_base="${SECUREWAVE_API_BASE_URL:-https://api.securewaveapp.com/api}"
[[ "$api_base" =~ ^https?://[^[:space:]]+$ ]] || {
  echo "SECUREWAVE_API_BASE_URL must be an http(s) URL." >&2
  exit 2
}

credential_file="${SECUREWAVE_CERT_AUTH_FILE:-$repo_root/securewave_private/live_certification_account.env}"
[[ -f "$credential_file" ]] || {
  echo "Live test credentials are missing: $credential_file" >&2
  echo "Create it with SECUREWAVE_RUNTIME_PROBE_EMAIL and SECUREWAVE_RUNTIME_PROBE_PASSWORD." >&2
  exit 2
}

read_credential() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "$credential_file" | tail -n 1)"
  printf '%s' "$value"
}

test_email="${SECUREWAVE_TEST_EMAIL:-${SECUREWAVE_RUNTIME_PROBE_EMAIL:-${DEMO_EMAIL:-}}}"
test_credential="${SECUREWAVE_TEST_PASSWORD:-${SECUREWAVE_RUNTIME_PROBE_PASSWORD:-${DEMO_PASSWORD:-}}}"
if [[ -z "$test_email" ]]; then
  test_email="$(read_credential SECUREWAVE_RUNTIME_PROBE_EMAIL)"
  [[ -n "$test_email" ]] || test_email="$(read_credential SECUREWAVE_TEST_EMAIL)"
  [[ -n "$test_email" ]] || test_email="$(read_credential DEMO_EMAIL)"
fi
if [[ -z "$test_credential" ]]; then
  test_credential="$(read_credential SECUREWAVE_RUNTIME_PROBE_PASSWORD)"
  [[ -n "$test_credential" ]] || test_credential="$(read_credential SECUREWAVE_TEST_PASSWORD)"
  [[ -n "$test_credential" ]] || test_credential="$(read_credential DEMO_PASSWORD)"
fi
[[ -n "$test_email" && -n "$test_credential" ]] || {
  echo "The live test credential file does not contain a supported email/password pair." >&2
  exit 2
}

login_payload="$(jq -nc --arg email "$test_email" --arg password "$test_credential" '{email:$email,password:$password}')"
login_status="$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' -d "$login_payload" "$api_base/auth/login")"
[[ "$login_status" == "200" ]] || {
  echo "Live test account preflight failed against $api_base (HTTP $login_status)." >&2
  exit 3
}

runtime_preflight="$(mktemp)"
if ! python3 "$repo_root/scripts/linux_vpn_runtime_verifier.py" --json >"$runtime_preflight"; then
  relevant_failures="$(jq '[.checks[] | select(.ok == false and (.name | startswith("residue:ikev2_") | not))] | length' "$runtime_preflight")"
  if [[ "$relevant_failures" -gt 0 ]]; then
    echo "Warning: the supported Linux VPN runtime has failed checks; the app will still open." >&2
    jq -r '.checks[] | select(.ok == false and (.name | startswith("residue:ikev2_") | not)) | "  - \(.name): \(.detail)"' \
      "$runtime_preflight" >&2
  else
    echo "WireGuard runtime ready; protocol-specific IKEv2 host diagnostics remain in the post-run report." >&2
  fi
fi

FORCE_FLUTTER_ENV=true bash "$repo_root/scripts/prepare_flutter_env.sh" >/dev/null

# Flutter desktop does not inherit arbitrary shell environment values. Keep the
# debug-only account in the ignored app environment file rather than exposing
# its password in dart-define process arguments.
app_env="$app_dir/.env"
umask 077
{
  printf 'SECUREWAVE_API_BASE_URL=%s\n' "$api_base"
  printf 'SECUREWAVE_PORTAL_URL=https://securewaveapp.com/account\n'
  printf 'SECUREWAVE_UPGRADE_URL=https://securewaveapp.com/subscription\n'
  printf 'SECUREWAVE_USE_MOCK_API=false\n'
  printf 'SECUREWAVE_RESET_SESSION_ON_BOOT=true\n'
  printf 'SECUREWAVE_DEBUG_AUTO_LOGIN=true\n'
  printf 'SECUREWAVE_DEBUG_EMAIL=%s\n' "$test_email"
  printf 'SECUREWAVE_DEBUG_PASSWORD=%s\n' "$test_credential"
} > "$app_env"
chmod 600 "$app_env"

cd "$app_dir"
flutter pub get

report_dir="$repo_root/artifacts/flutter-live-runs"
mkdir -p "$report_dir"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
log_file="$report_dir/$run_id.log"
report_file="$report_dir/$run_id-summary.txt"

echo "Opening the native SecureWave Linux app."
echo "Test account: $test_email"
echo "Close the app window to finish diagnostics."

set +e
flutter run -d linux \
  2>&1 | tee "$log_file"
flutter_status=$?
set -e

{
  echo "SecureWave native Flutter run summary"
  echo "Run: $run_id"
  echo "API: $api_base"
  echo "Account: $test_email"
  echo "Exit code: $flutter_status"
  echo
  echo "Linux VPN runtime preflight:"
  cat "$runtime_preflight"
  echo
  echo "Detected diagnostics:"
  grep -Ein 'error|exception|failed|warning|lost connection|unavailable' "$log_file" || echo "No matching diagnostics."
  echo
  echo "Final log lines:"
  tail -n 80 "$log_file"
} > "$report_file"

rm -f "$runtime_preflight"

echo "Debug summary: $report_file"
exit "$flutter_status"
