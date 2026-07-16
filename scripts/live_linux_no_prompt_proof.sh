#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
auth_file="${SECUREWAVE_CERT_AUTH_FILE:-$repo_root/securewave_private/live_certification_account.env}"
api_base="${SECUREWAVE_API_BASE_URL:-https://api.securewaveapp.com/api}"
hold_seconds="${SECUREWAVE_LIVE_HOLD_SECONDS:-20}"
evidence_timeout="${SECUREWAVE_LIVE_EVIDENCE_TIMEOUT:-120}"

if [[ ! -f "$auth_file" ]]; then
  echo "Live proof credential file is missing: $auth_file" >&2
  echo "Run 'make linux-live-auth-init' once. No administrator access is required." >&2
  exit 2
fi

mode="$(stat -c '%a' "$auth_file")"
if [[ "$mode" != "600" ]]; then
  echo "Live proof credential file must have mode 0600: $auth_file" >&2
  exit 2
fi

exec python3 "$repo_root/scripts/linux_app_vpn_tunnel_proof.py" \
  --api-base "$api_base" \
  --allow-production \
  --auth-file "$auth_file" \
  --protocol wireguard \
  --protocol openvpn \
  --hold-seconds "$hold_seconds" \
  --evidence-timeout "$evidence_timeout" \
  --json
