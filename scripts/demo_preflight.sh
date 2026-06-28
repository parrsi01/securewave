#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE="${SECUREWAVE_API_BASE_URL:-https://api.securewaveapp.com/api}"
DEMO_EMAIL="${DEMO_EMAIL:-}"
DEMO_PASSWORD="${DEMO_PASSWORD:-}"
CLEANUP=false
REVOKE_DEVICES=false
SKIP_BUILD=false
BLOCKERS=0

usage() {
  cat <<'EOF'
Usage: bash scripts/demo_preflight.sh [--cleanup] [--revoke-devices] [--skip-build]

Environment:
  SECUREWAVE_API_BASE_URL  API base URL. Defaults to https://api.securewaveapp.com/api
  DEMO_EMAIL               Dedicated demo account email. Optional.
  DEMO_PASSWORD            Dedicated demo account password. Optional.

If DEMO_EMAIL/DEMO_PASSWORD are omitted, the script provisions a disposable
QA account for inventory checks. Device revocation only runs with
--revoke-devices.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup)
      CLEANUP=true
      shift
      ;;
    --revoke-devices)
      REVOKE_DEVICES=true
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[FAIL] Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

pass() {
  printf '[PASS] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  BLOCKERS=$((BLOCKERS + 1))
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "tool available: $1"
  else
    fail "missing required tool: $1"
  fi
}

check_url() {
  local path="$1"
  local label="$2"
  if curl -fsS --max-time 20 "$API_BASE$path" >/dev/null; then
    pass "$label reachable"
  else
    fail "$label unreachable at $API_BASE$path"
  fi
}

check_helper_contract() {
  local helper="/usr/local/libexec/securewave-wg-quick"
  local contract_file="/usr/local/libexec/securewave-wg-quick.contract"
  if [[ -x "$helper" ]]; then
    pass "SecureWave helper installed"
  else
    fail "$helper is missing or not executable"
  fi

  if [[ ! -f "$contract_file" ]]; then
    fail "$contract_file is missing"
    return
  fi

  local contract
  contract="$(tr -d '[:space:]' < "$contract_file")"
  if [[ "$contract" =~ ^[0-9]+$ ]] && (( contract >= 6 )); then
    pass "SecureWave helper contract $contract >= 6"
  else
    fail "SecureWave helper contract '$contract' is below required version 6"
  fi
}

cleanup_wireguard_interfaces() {
  local links
  links="$(ip -o link show type wireguard 2>/dev/null || true)"
  if [[ -z "$links" ]]; then
    pass "no leftover WireGuard interfaces"
    return
  fi

  warn "WireGuard interfaces are present:"
  printf '%s\n' "$links" | sed 's/^/  /'

  if [[ "$CLEANUP" != "true" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local iface
      iface="$(awk -F': ' '{print $2}' <<<"$line" | cut -d@ -f1)"
      if [[ "$iface" == "sw-wg" ]]; then
        warn "cleanup command: pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick policy-clear-link sw-wg"
      else
        warn "cleanup command: sudo wg-quick down $iface"
      fi
    done <<<"$links"
    fail "leftover WireGuard interfaces require --cleanup or manual cleanup"
    return
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    local iface
    iface="$(awk -F': ' '{print $2}' <<<"$line" | cut -d@ -f1)"
    if [[ "$iface" == "sw-wg" ]]; then
      pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick policy-clear-link sw-wg
    else
      sudo -n wg-quick down "$iface"
    fi
  done <<<"$links"

  if [[ -z "$(ip -o link show type wireguard 2>/dev/null || true)" ]]; then
    pass "leftover WireGuard interfaces cleaned"
  else
    fail "WireGuard interfaces are still present after cleanup"
  fi
}

cleanup_wg_quick_units() {
  local units
  units="$(systemctl list-units --type=service --all 'wg-quick@*.service' --no-legend --plain 2>/dev/null | awk '{print $1}' || true)"
  if [[ -z "$units" ]]; then
    pass "no wg-quick systemd units loaded"
    return
  fi

  warn "wg-quick systemd units are loaded:"
  printf '%s\n' "$units" | sed 's/^/  /'
  if [[ "$CLEANUP" != "true" ]]; then
    while IFS= read -r unit; do
      [[ -n "$unit" ]] || continue
      warn "cleanup command: sudo systemctl stop $unit"
    done <<<"$units"
    fail "wg-quick systemd units require --cleanup or manual cleanup"
    return
  fi

  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    sudo -n systemctl stop "$unit"
  done <<<"$units"
  pass "wg-quick systemd units stopped"
}

run_live_account_checks() {
  local output
  set +e
  output="$(
    python3 - "$API_BASE" "$DEMO_EMAIL" "$DEMO_PASSWORD" "$REVOKE_DEVICES" <<'PY'
import json
import secrets
import sys
import time
import urllib.error
import urllib.request

api_base, email, password, revoke_devices = sys.argv[1:5]
revoke_devices = revoke_devices.lower() == "true"

def request(method, path, token=None, payload=None, expected=(200,)):
    headers = {"Accept": "application/json"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        f"{api_base}{path}", data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            body = resp.read().decode("utf-8")
            parsed = json.loads(body) if body else {}
            status = resp.status
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8")
        try:
            parsed = json.loads(body) if body else {}
        except json.JSONDecodeError:
            parsed = {"detail": body}
        status = exc.code
    if status not in expected:
        raise RuntimeError(f"{method} {path} failed HTTP {status}: {parsed}")
    return status, parsed

generated = False
if not email or not password:
    stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    email = f"securewave.demo.{stamp}.{secrets.token_hex(3)}@gmail.com"
    password = f"SwDemo{secrets.token_hex(4)}!A1"
    generated = True

if generated:
    _, auth = request(
        "POST",
        "/auth/register",
        payload={
            "email": email,
            "password": password,
            "password_confirm": password,
        },
        expected=(201,),
    )
    print(f"[PASS] disposable demo account provisioned: {email}")
    print(f"[WARN] disposable demo password: {password}")
    if not auth.get("access_token"):
        _, auth = request(
            "POST",
            "/auth/login",
            payload={"email": email, "password": password},
            expected=(200,),
        )
else:
    _, auth = request(
        "POST",
        "/auth/login",
        payload={"email": email, "password": password},
        expected=(200,),
    )
    print(f"[PASS] dedicated demo account login succeeded: {email}")

token = auth.get("access_token")
if not token:
    raise RuntimeError("auth response did not include access_token")

_, servers = request("GET", "/vpn/servers?device_type=linux", token=token)
server_items = servers.get("servers") or []
if not server_items:
    raise RuntimeError("server inventory returned zero servers")
print(f"[PASS] live Linux server inventory: {len(server_items)} server(s)")

_, devices = request("GET", "/vpn/devices", token=token)
device_items = devices.get("devices") or []
active_devices = [
    item
    for item in device_items
    if item.get("is_active") is True and item.get("is_revoked") is not True
]
limit = int(devices.get("limit") or 0)
remaining = int(devices.get("remaining") or 0)
print(
    f"[PASS] device inventory: {len(active_devices)} active / "
    f"{limit} limit / {remaining} remaining"
)

if active_devices and revoke_devices:
    for item in active_devices:
        request("DELETE", f"/vpn/devices/{item['id']}", token=token, expected=(204,))
        print(f"[PASS] revoked stale demo device {item['id']}: {item.get('name')}")
elif active_devices and remaining <= 0:
    raise RuntimeError(
        "demo account is at the device limit; rerun with --revoke-devices "
        "or revoke devices manually"
    )
elif active_devices:
    print("[WARN] active demo devices remain; use --revoke-devices for a clean account")
PY
  )"
  local code=$?
  set -e
  printf '%s\n' "$output"
  if (( code == 0 )); then
    pass "live account checks passed"
  else
    fail "live account checks failed"
  fi
}

prebuild_linux_bundle() {
  if [[ "$SKIP_BUILD" == "true" ]]; then
    warn "Linux release prebuild skipped by --skip-build"
    return
  fi

  (
    cd "$ROOT_DIR/securewave_app"
    flutter pub get
    flutter build linux --release
  )

  local bundle
  bundle="$(find "$ROOT_DIR/securewave_app/build/linux" -path '*/release/bundle/securewave_app' -type f -executable -print -quit 2>/dev/null || true)"
  if [[ -n "$bundle" ]]; then
    pass "Linux release bundle ready: ${bundle#$ROOT_DIR/}"
  else
    fail "Linux release bundle was not produced"
  fi
}

cd "$ROOT_DIR"
printf 'SecureWave demo preflight\n'
printf 'API: %s\n\n' "$API_BASE"

require_command curl
require_command python3
require_command ip
require_command systemctl
require_command flutter

check_url "/health" "live API health"
check_url "/downloads" "download manifest"
run_live_account_checks
cleanup_wireguard_interfaces
cleanup_wg_quick_units
check_helper_contract
prebuild_linux_bundle

if (( BLOCKERS > 0 )); then
  printf '\n[FAIL] Demo preflight found %d blocker(s).\n' "$BLOCKERS" >&2
  exit 1
fi

printf '\n[PASS] Demo preflight passed.\n'
