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

api_base="${SECUREWAVE_API_BASE_URL:-}"
[[ -n "$api_base" ]] || {
  echo "SECUREWAVE_API_BASE_URL must explicitly identify an authorized staging API." >&2
  exit 2
}
[[ "$api_base" =~ ^https?://[^[:space:]]+$ ]] || {
  echo "SECUREWAVE_API_BASE_URL must be an http(s) URL." >&2
  exit 2
}
[[ "$api_base" != "https://api.securewaveapp.com/api" ]] || {
  echo "Production cannot be selected by scripts/run_flutter_linux.sh." >&2
  exit 2
}

credential_file="${SECUREWAVE_CERT_AUTH_FILE:-$repo_root/securewave_private/live_certification_account.env}"
[[ -f "$credential_file" && ! -L "$credential_file" ]] || {
  echo "Live test credentials are missing: $credential_file" >&2
  echo "Create it with SECUREWAVE_RUNTIME_PROBE_EMAIL and SECUREWAVE_RUNTIME_PROBE_PASSWORD." >&2
  exit 2
}
[[ "$(stat -c '%u' "$credential_file")" == "$(id -u)" ]] || {
  echo "The live credential file must be owned by the current user." >&2
  exit 2
}
[[ "$(stat -c '%a' "$credential_file")" == "600" ]] || {
  echo "The live credential file must have mode 0600." >&2
  exit 2
}
python3 "$repo_root/scripts/check_live_certification_inputs.py" \
  --api-base "$api_base" --auth-file "$credential_file" >/dev/null

read_credential() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "$credential_file" | tail -n 1)"
  printf '%s' "$value"
}

test_email="$(read_credential SECUREWAVE_RUNTIME_PROBE_EMAIL)"
test_credential="$(read_credential SECUREWAVE_RUNTIME_PROBE_PASSWORD)"
[[ -n "$test_email" && -n "$test_credential" ]] || {
  echo "The live test credential file does not contain a supported email/password pair." >&2
  exit 2
}

login_payload_file="$(mktemp)"
chmod 600 "$login_payload_file"
jq -nc --arg email "$test_email" --arg password "$test_credential" \
  '{email:$email,password:$password}' >"$login_payload_file"
if ! login_status="$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' --data-binary "@$login_payload_file" "$api_base/auth/login")"; then
  rm -f "$login_payload_file"
  echo "Live test account preflight could not reach the explicit staging API." >&2
  exit 3
fi
rm -f "$login_payload_file"
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

# Flutter desktop does not inherit arbitrary shell environment values. Keep
# credentials exclusively in the protected auth file; the app must use its
# valid restored session or an interactive login with that same account.
app_env="$app_dir/.env"
umask 077
{
  printf 'SECUREWAVE_API_BASE_URL=%s\n' "$api_base"
  printf 'SECUREWAVE_PORTAL_URL=https://securewaveapp.com/account\n'
  printf 'SECUREWAVE_UPGRADE_URL=https://securewaveapp.com/subscription\n'
  printf 'SECUREWAVE_USE_MOCK_API=false\n'
  printf 'SECUREWAVE_RESET_SESSION_ON_BOOT=false\n'
  printf 'SECUREWAVE_DEBUG_AUTO_LOGIN=false\n'
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
echo "Close the app window to finish diagnostics."

set +e
flutter run -d linux \
  --dart-define="SECUREWAVE_API_BASE_URL=$api_base" \
  --dart-define="SECUREWAVE_USE_MOCK_API=false" \
  --dart-define="SECUREWAVE_RESET_SESSION_ON_BOOT=false" \
  --dart-define="SECUREWAVE_DEBUG_AUTO_LOGIN=false" \
  2>&1 | tee "$log_file"
flutter_status=$?
set -e

{
  echo "SecureWave native Flutter run summary"
  echo "Run: $run_id"
  echo "API: explicitly authorized staging target"
  echo "Account: authenticated existing account"
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
