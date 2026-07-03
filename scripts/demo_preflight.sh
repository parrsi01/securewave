#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_BASE="${SECUREWAVE_API_BASE_URL:-https://api.securewaveapp.com/api}"
WIREGUARD_INTERFACE="sw-wg"
DEFAULT_AUTH_FILE="$ROOT_DIR/securewave_private/live_certification_account.env"
AUTH_FILE="${SECUREWAVE_CERT_AUTH_FILE:-${SECUREWAVE_LIVE_ACCOUNT_FILE:-}}"
if [[ -z "$AUTH_FILE" && -f "$DEFAULT_AUTH_FILE" ]]; then
  AUTH_FILE="$DEFAULT_AUTH_FILE"
fi
DEMO_EMAIL="${DEMO_EMAIL:-${SECUREWAVE_TEST_EMAIL:-${SECUREWAVE_RUNTIME_PROBE_EMAIL:-}}}"
DEMO_PASSWORD="${DEMO_PASSWORD:-${SECUREWAVE_TEST_PASSWORD:-${SECUREWAVE_RUNTIME_PROBE_PASSWORD:-}}}"
CLEANUP=false
REVOKE_DEVICES=false
SKIP_BUILD=false
REQUIRE_REAL_TUNNEL=false
REQUIRE_EMAIL_HEALTH=false
BLOCKERS=0

usage() {
  cat <<'EOF'
Usage: bash scripts/demo_preflight.sh [--cleanup] [--revoke-devices] [--skip-build] [--require-real-tunnel] [--require-email-health] [--live-go-no-go]

Environment:
  SECUREWAVE_API_BASE_URL  API base URL. Defaults to https://api.securewaveapp.com/api
  DEMO_EMAIL               Dedicated demo account email. Required for live account checks.
  DEMO_PASSWORD            Dedicated demo account password. Required for live account checks.
  SECUREWAVE_TEST_EMAIL / SECUREWAVE_TEST_PASSWORD
                           Fallback aliases when DEMO_EMAIL/DEMO_PASSWORD are unset.
  SECUREWAVE_CERT_AUTH_FILE Optional key=value credential file. If unset,
                           securewave_private/live_certification_account.env
                           is used when present.

Live account checks log in with a stable existing account. They do not create
disposable accounts because live registration can be rate-limited. Device
revocation only runs with --revoke-devices.

Use --live-go-no-go after connecting the real tunnel. It requires tunnel egress
and email health in addition to the default live API, inventory, residue, helper,
polkit, and build checks.
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
    --require-real-tunnel)
      REQUIRE_REAL_TUNNEL=true
      shift
      ;;
    --require-email-health)
      REQUIRE_EMAIL_HEALTH=true
      shift
      ;;
    --live-go-no-go)
      REQUIRE_REAL_TUNNEL=true
      REQUIRE_EMAIL_HEALTH=true
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
  if [[ "$contract" =~ ^[0-9]+$ ]] && (( contract >= 8 )); then
    pass "SecureWave helper contract $contract >= 8"
  else
    fail "SecureWave helper contract '$contract' is below required version 8"
  fi
}

check_polkit_authorization() {
  local helper="/usr/local/libexec/securewave-wg-quick"
  if [[ ! -x "$helper" ]]; then
    fail "$helper is missing or not executable"
    return
  fi

  local output
  local code
  set +e
  output="$(timeout 20 pkexec --disable-internal-agent "$helper" probe wireguard 2>&1)"
  code=$?
  set -e

  if (( code == 0 )); then
    pass "prompt-free SecureWave helper authorization works"
  elif (( code == 124 )); then
    fail "SecureWave helper authorization timed out; install /etc/polkit-1/rules.d/50-securewave-wg.rules or start a PolicyKit agent"
  else
    fail "SecureWave helper authorization failed: ${output:-pkexec exited $code}"
  fi
}

api_hostname() {
  python3 - "$API_BASE" <<'PY'
import sys
from urllib.parse import urlparse

print(urlparse(sys.argv[1]).hostname or "")
PY
}

check_email_health() {
  local url="$API_BASE/health/email"
  if curl -fsS --max-time 20 "$url" >/dev/null; then
    pass "email health endpoint ok"
  elif [[ "$REQUIRE_EMAIL_HEALTH" == "true" ]]; then
    fail "email health endpoint is not ok at $url"
  else
    warn "email health endpoint is not ok at $url; use --require-email-health for release go/no-go"
  fi
}

check_real_tunnel_egress() {
  local tunnel_interface=""
  local tunnel_protocol=""

  if ip -o link show "$WIREGUARD_INTERFACE" >/dev/null 2>&1; then
    tunnel_interface="$WIREGUARD_INTERFACE"
    tunnel_protocol="WireGuard"
  elif ip -o link show tun0 >/dev/null 2>&1 && pgrep -af 'openvpn .*securewave\.ovpn' >/dev/null 2>&1; then
    tunnel_interface="tun0"
    tunnel_protocol="OpenVPN"
  fi

  if [[ -z "$tunnel_interface" ]]; then
    if [[ "$REQUIRE_REAL_TUNNEL" == "true" ]]; then
      fail "real tunnel egress was required but no SecureWave WireGuard/OpenVPN tunnel is active"
    else
      warn "real tunnel egress skipped because no SecureWave tunnel is active; rerun with --live-go-no-go while connected"
    fi
    return
  fi

  pass "real $tunnel_protocol interface active: $tunnel_interface"

  local route
  route="$(ip route get 1.1.1.1 2>&1 || true)"
  if [[ "$route" == *" dev $tunnel_interface "* ]]; then
    pass "default egress route uses $tunnel_interface"
  else
    fail "default egress route does not use $tunnel_interface: $route"
  fi

  local host
  host="$(api_hostname)"
  if [[ -n "$host" ]] && getent ahosts "$host" >/dev/null; then
    pass "DNS resolves live API host: $host"
  else
    fail "DNS did not resolve live API host: ${host:-unknown}"
  fi

  if curl -fsS --max-time 20 "$API_BASE/health" >/dev/null; then
    pass "live API reachable through active tunnel"
  else
    fail "live API unreachable through active tunnel"
  fi

  local egress_ip
  if egress_ip="$(curl -fsS --max-time 20 https://api.ipify.org 2>/dev/null)" && [[ -n "$egress_ip" ]]; then
    pass "public egress IP visible through active tunnel: $egress_ip"
  else
    fail "public egress IP lookup failed through active tunnel"
  fi

  if command -v resolvectl >/dev/null 2>&1; then
    local dns_status
    dns_status="$(resolvectl dns "$tunnel_interface" 2>/dev/null || true)"
    if [[ -n "$dns_status" ]]; then
      pass "resolvectl has DNS state for $tunnel_interface"
    else
      warn "resolvectl has no DNS state for $tunnel_interface; DNS may be managed outside systemd-resolved"
    fi
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

  if [[ "$REQUIRE_REAL_TUNNEL" == "true" ]]; then
    local unexpected=""
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local iface
      iface="$(awk -F': ' '{print $2}' <<<"$line" | cut -d@ -f1)"
      if [[ "$iface" != "$WIREGUARD_INTERFACE" ]]; then
        unexpected+="$line"$'\n'
      fi
    done <<<"$links"
    if [[ -z "$unexpected" ]]; then
      pass "$WIREGUARD_INTERFACE is active for the required real-tunnel egress check"
      return
    fi
    fail "unexpected WireGuard interfaces are present during real-tunnel check: ${unexpected//$'\n'/; }"
    return
  fi

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
    python3 - "$API_BASE" "$DEMO_EMAIL" "$DEMO_PASSWORD" "$REVOKE_DEVICES" "$AUTH_FILE" <<'PY'
import json
from pathlib import Path
import sys
import urllib.error
import urllib.request

api_base, email, password, revoke_devices, auth_file = sys.argv[1:6]
revoke_devices = revoke_devices.lower() == "true"
placeholder_values = {
    "existing-live-email",
    "existing-live-password",
    "real@email.com",
    "real-password",
    "your-real-test-account@example.com",
    "your-real-test-password",
}

def is_placeholder(value):
    return value.strip().lower() in placeholder_values

def parse_env_file(path):
    values = {}
    allowed = {
        "DEMO_EMAIL",
        "DEMO_PASSWORD",
        "SECUREWAVE_TEST_EMAIL",
        "SECUREWAVE_TEST_PASSWORD",
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
        "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
    }
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("export "):
            stripped = stripped[len("export "):].strip()
        if "=" not in stripped:
            continue
        key, raw_value = stripped.split("=", 1)
        key = key.strip()
        if key not in allowed:
            continue
        value = raw_value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        values[key] = value
    return values

def file_default(values, *names):
    for name in names:
        value = values.get(name)
        if value:
            return value
    return None

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

credential_values = {}
if auth_file:
    auth_path = Path(auth_file).expanduser()
    if not auth_path.is_file():
        raise SystemExit(f"credential file does not exist: {auth_path}")
    credential_values = parse_env_file(auth_path)

email = email or file_default(
    credential_values,
    "DEMO_EMAIL",
    "SECUREWAVE_TEST_EMAIL",
    "SECUREWAVE_RUNTIME_PROBE_EMAIL",
)
password = password or file_default(
    credential_values,
    "DEMO_PASSWORD",
    "SECUREWAVE_TEST_PASSWORD",
    "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
)

if not email or not password:
    raise SystemExit(
        "stable live account credentials are required via DEMO_EMAIL/DEMO_PASSWORD "
        "or SECUREWAVE_TEST_EMAIL/SECUREWAVE_TEST_PASSWORD; "
        "SECUREWAVE_CERT_AUTH_FILE may point to a local key-value credential file"
    )
if is_placeholder(email) or is_placeholder(password):
    raise SystemExit(
        "placeholder live account credentials are not valid; configure a stable existing test account"
    )

_, auth = request(
    "POST",
    "/auth/login",
    payload={"email": email, "password": password},
    expected=(200,),
)
print("[PASS] dedicated demo account login succeeded")

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
require_command pkexec
require_command timeout
require_command getent

check_url "/health" "live API health"
check_email_health
check_url "/downloads" "download manifest"
run_live_account_checks
cleanup_wireguard_interfaces
cleanup_wg_quick_units
check_helper_contract
check_polkit_authorization
check_real_tunnel_egress
prebuild_linux_bundle

if (( BLOCKERS > 0 )); then
  printf '\n[FAIL] Demo preflight found %d blocker(s).\n' "$BLOCKERS" >&2
  exit 1
fi

printf '\n[PASS] Demo preflight passed.\n'
