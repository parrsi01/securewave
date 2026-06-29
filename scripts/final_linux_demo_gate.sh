#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

API_BASE="${SECUREWAVE_API_BASE_URL:-https://api.securewaveapp.com/api}"
DOWNLOADS_URL="${SECUREWAVE_DOWNLOADS_URL:-$API_BASE/downloads}"
DEFAULT_AUTH_FILE="$ROOT_DIR/securewave_private/live_certification_account.env"
AUTH_FILE="${SECUREWAVE_CERT_AUTH_FILE:-${SECUREWAVE_LIVE_ACCOUNT_FILE:-$DEFAULT_AUTH_FILE}}"
PKEXEC_TIMEOUT="${SECUREWAVE_PKEXEC_TIMEOUT:-20}"
HOLD_SECONDS="${SECUREWAVE_PROOF_HOLD_SECONDS:-20}"
EVIDENCE_TIMEOUT="${SECUREWAVE_EVIDENCE_TIMEOUT:-180}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="${SECUREWAVE_GATE_LOG_DIR:-$ROOT_DIR/artifacts/final-linux-demo-gate/$TIMESTAMP}"

ALLOW_VERSION_DRIFT=false
APP_PROOF=false
BUILD=false
CLEANUP=false
CONNECTED=false
FULL_TESTS=false
PROVISION_LIVE_ACCOUNT=false
RELEASE=false
REVOKE_DEVICES=false
WRITE_AUTH_FILE=false
PROTOCOLS=()

BLOCKERS=0
WARNINGS=0
STEP_COUNT=0

usage() {
  cat <<'EOF'
Usage: bash scripts/final_linux_demo_gate.sh [options]

One-command Linux demo/release readiness gate. The script creates a dated log
directory under artifacts/final-linux-demo-gate and prints the remaining blocker
count at the end.

Options:
  --write-auth-file       Write securewave_private/live_certification_account.env
                          from DEMO_EMAIL/DEMO_PASSWORD or fallback aliases.
  --provision-live-account
                          Register one stable live certification account when
                          no credential file exists, then save it locally.
  --connected             Require active real-tunnel egress with --live-go-no-go.
  --app-proof             Run the app-driven tunnel proof after preflight.
  --protocol NAME         Protocol for --app-proof. Repeat for multiple values.
                          Defaults to the proof script defaults.
  --full-tests            Run scripts/devops_preflight.sh and full pytest suite.
  --build                 Let demo_preflight build the Linux release bundle.
                          Without this, demo_preflight uses --skip-build.
  --release               Run scripts/release_preflight.sh.
  --revoke-devices        Pass --revoke-devices to demo_preflight.
  --cleanup               Pass --cleanup to demo_preflight.
  --allow-version-drift   Warn instead of blocking when app and download
                          manifest versions differ.
  -h, --help              Show this help.

Credential environment:
  DEMO_EMAIL / DEMO_PASSWORD
  SECUREWAVE_TEST_EMAIL / SECUREWAVE_TEST_PASSWORD
  SECUREWAVE_RUNTIME_PROBE_EMAIL / SECUREWAVE_RUNTIME_PROBE_PASSWORD
  SECUREWAVE_CERT_AUTH_FILE or SECUREWAVE_LIVE_ACCOUNT_FILE
  SECUREWAVE_PROVISION_EMAIL / SECUREWAVE_PROVISION_PASSWORD
                          Optional values for --provision-live-account.
                          If omitted, a generated account is created and saved.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-auth-file)
      WRITE_AUTH_FILE=true
      shift
      ;;
    --provision-live-account)
      PROVISION_LIVE_ACCOUNT=true
      shift
      ;;
    --connected)
      CONNECTED=true
      shift
      ;;
    --app-proof)
      APP_PROOF=true
      shift
      ;;
    --protocol)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --protocol requires a value" >&2
        exit 64
      fi
      PROTOCOLS+=("$2")
      shift 2
      ;;
    --full-tests)
      FULL_TESTS=true
      shift
      ;;
    --build)
      BUILD=true
      shift
      ;;
    --release)
      RELEASE=true
      shift
      ;;
    --revoke-devices)
      REVOKE_DEVICES=true
      shift
      ;;
    --cleanup)
      CLEANUP=true
      shift
      ;;
    --allow-version-drift)
      ALLOW_VERSION_DRIFT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

mkdir -p "$LOG_DIR"

slugify() {
  tr -cs 'A-Za-z0-9._-' '_' <<<"$1" | sed 's/^_//; s/_$//'
}

pass() {
  printf '[PASS] %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARN] %s\n' "$1"
}

blocker() {
  BLOCKERS=$((BLOCKERS + 1))
  printf '[FAIL] %s\n' "$1" >&2
}

run_required() {
  local label="$1"
  shift
  local slug
  slug="$(slugify "$label")"
  local log="$LOG_DIR/${slug}.log"
  STEP_COUNT=$((STEP_COUNT + 1))
  printf '\n== %s ==\n' "$label"
  set +e
  "$@" >"$log" 2>&1
  local code=$?
  set -e
  if (( code == 0 )); then
    pass "$label"
    return 0
  fi
  blocker "$label failed; see $log"
  tail -n 40 "$log" | sed 's/^/  /' >&2 || true
  return 0
}

write_auth_file() {
  local email="${DEMO_EMAIL:-${SECUREWAVE_TEST_EMAIL:-${SECUREWAVE_RUNTIME_PROBE_EMAIL:-}}}"
  local credential_value="${DEMO_PASSWORD:-${SECUREWAVE_TEST_PASSWORD:-${SECUREWAVE_RUNTIME_PROBE_PASSWORD:-}}}"
  local log="$LOG_DIR/write_auth_file.log"

  if [[ -z "$email" || -z "$credential_value" ]]; then
    blocker "--write-auth-file needs DEMO_EMAIL/DEMO_PASSWORD or fallback aliases"
    return 0
  fi

  set +e
  python3 - "$AUTH_FILE" "$email" "$credential_value" >"$log" 2>&1 <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
email = sys.argv[2]
credential_value = sys.argv[3]
if "\n" in email or "\n" in credential_value:
    raise SystemExit("credentials must not contain newlines")
path.parent.mkdir(parents=True, exist_ok=True)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    handle.write("# Local SecureWave live certification credentials. Do not commit.\n")
    handle.write(f"DEMO_EMAIL={email}\n")
    handle.write(f"DEMO_PASSWORD={credential_value}\n")
os.chmod(path, 0o600)
print(path)
PY
  local code=$?
  set -e
  if (( code == 0 )); then
    export SECUREWAVE_CERT_AUTH_FILE="$AUTH_FILE"
    pass "wrote credential file: $AUTH_FILE"
  else
    blocker "failed to write credential file; see $log"
    tail -n 20 "$log" | sed 's/^/  /' >&2 || true
  fi
}

provision_live_account() {
  local log="$LOG_DIR/provision_live_account.log"
  if [[ -f "$AUTH_FILE" && "${SECUREWAVE_FORCE_PROVISION:-false}" != "true" ]]; then
    pass "credential file already exists; skipping live account provisioning"
    export SECUREWAVE_CERT_AUTH_FILE="$AUTH_FILE"
    return 0
  fi

  set +e
  SECUREWAVE_PROVISION_AUTH_FILE="$AUTH_FILE" \
    SECUREWAVE_PROVISION_API_BASE="$API_BASE" \
    python3 - >"$log" 2>&1 <<'PY'
import json
import os
import secrets
import sys
import urllib.error
import urllib.request
from pathlib import Path

api_base = os.environ.get("SECUREWAVE_PROVISION_API_BASE", "").rstrip("/")
auth_file = Path(os.environ["SECUREWAVE_PROVISION_AUTH_FILE"]).expanduser()
email_value = os.environ.get("SECUREWAVE_PROVISION_EMAIL", "").strip()
cred_value = os.environ.get("SECUREWAVE_PROVISION_PASSWORD", "")

if not api_base:
    raise SystemExit("SECUREWAVE_PROVISION_API_BASE is required")

if not email_value:
    email_value = f"securewave-linux-cert+{secrets.token_hex(6)}@example.com"
if not cred_value:
    cred_value = "SwCert-" + secrets.token_urlsafe(18) + "!A1"

def redacted_email(value: str) -> str:
    local, separator, domain = value.partition("@")
    if not separator:
        return "configured"
    return f"{local[:1]}***@{domain}"

def request(method: str, path: str, payload: dict | None = None, token: str | None = None):
    headers = {"Accept": "application/json"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{api_base}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            body = response.read().decode("utf-8")
            return response.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8")
        try:
            parsed = json.loads(body) if body else {}
        except json.JSONDecodeError:
            parsed = {"detail": body}
        return exc.code, parsed

register_payload = {
    "email": email_value,
    "password": cred_value,
    "password_confirm": cred_value,
}
status, body = request("POST", "/auth/register", register_payload)
if status == 201:
    print(f"registered stable account: {redacted_email(email_value)}")
elif status == 400 and "registered" in str(body).lower():
    print(f"account already exists; validating login: {redacted_email(email_value)}")
elif status == 429:
    raise SystemExit(
        "live registration is rate limited; rerun with SECUREWAVE_PROVISION_EMAIL "
        "and SECUREWAVE_PROVISION_PASSWORD for an existing account, or retry after the limiter resets"
    )
else:
    raise SystemExit(f"registration failed HTTP {status}: {body}")

login_status, login_body = request(
    "POST",
    "/auth/login",
    {"email": email_value, "password": cred_value},
)
if login_status != 200 or not login_body.get("access_token"):
    raise SystemExit(f"login validation failed HTTP {login_status}: {login_body}")

auth_file.parent.mkdir(parents=True, exist_ok=True)
fd = os.open(auth_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    handle.write("# Local SecureWave live certification credentials. Do not commit.\n")
    handle.write(f"DEMO_EMAIL={email_value}\n")
    handle.write(f"DEMO_PASSWORD={cred_value}\n")
os.chmod(auth_file, 0o600)
print(f"saved credential file: {auth_file}")
PY
  local code=$?
  set -e
  if (( code == 0 )); then
    export SECUREWAVE_CERT_AUTH_FILE="$AUTH_FILE"
    pass "provisioned stable live certification account"
    grep -E '^(registered|account already exists|saved credential file)' "$log" | sed 's/^/  /' || true
  else
    blocker "failed to provision stable live account; see $log"
    tail -n 30 "$log" | sed 's/^/  /' >&2 || true
  fi
}

export_auth_file_if_present() {
  if [[ -f "$AUTH_FILE" ]]; then
    export SECUREWAVE_CERT_AUTH_FILE="$AUTH_FILE"
    pass "using credential file: $AUTH_FILE"
  fi
}

check_version_alignment() {
  local log="$LOG_DIR/version_alignment.log"
  printf '\n== version alignment ==\n'
  set +e
  python3 - "$DOWNLOADS_URL" >"$log" 2>&1 <<'PY'
import json
import sys
import urllib.request
from pathlib import Path

downloads_url = sys.argv[1]
pubspec = Path("securewave_app/pubspec.yaml")
local_version = ""
for line in pubspec.read_text(encoding="utf-8").splitlines():
    if line.startswith("version:"):
        local_version = line.split(":", 1)[1].strip()
        break
if not local_version:
    raise SystemExit("could not read securewave_app/pubspec.yaml version")
with urllib.request.urlopen(downloads_url, timeout=20) as response:
    manifest = json.loads(response.read().decode("utf-8"))
remote_version = str(manifest.get("version") or "")
if not remote_version:
    raise SystemExit("download manifest did not include version")
print(f"local={local_version}")
print(f"remote={remote_version}")
if local_version != remote_version:
    raise SystemExit(2)
PY
  local code=$?
  set -e
  if (( code == 0 )); then
    pass "app package version matches live download manifest"
    return 0
  fi
  if (( code == 2 )) && [[ "$ALLOW_VERSION_DRIFT" == "true" ]]; then
    warn "app package version differs from live download manifest; see $log"
    cat "$log" | sed 's/^/  /'
    return 0
  fi
  blocker "app package version differs from live download manifest; see $log"
  cat "$log" | sed 's/^/  /' >&2 || true
}

run_demo_preflight() {
  local args=(bash scripts/demo_preflight.sh)
  if [[ "$CONNECTED" == "true" ]]; then
    args+=(--live-go-no-go)
  fi
  if [[ "$BUILD" != "true" ]]; then
    args+=(--skip-build)
  fi
  if [[ "$REVOKE_DEVICES" == "true" ]]; then
    args+=(--revoke-devices)
  fi
  if [[ "$CLEANUP" == "true" ]]; then
    args+=(--cleanup)
  fi
  run_required "demo_preflight" "${args[@]}"
}

run_app_proof() {
  local args=(
    python3 scripts/linux_app_vpn_tunnel_proof.py
    --hold-seconds "$HOLD_SECONDS"
    --evidence-timeout "$EVIDENCE_TIMEOUT"
    --pkexec-timeout "$PKEXEC_TIMEOUT"
    --json
  )
  if [[ -f "${SECUREWAVE_CERT_AUTH_FILE:-}" ]]; then
    args+=(--auth-file "$SECUREWAVE_CERT_AUTH_FILE")
  fi
  for protocol in "${PROTOCOLS[@]}"; do
    args+=(--protocol "$protocol")
  done
  run_required "app_tunnel_proof" "${args[@]}"
}

run_full_tests() {
  run_required "devops_preflight" bash scripts/devops_preflight.sh
  local python_bin="python3"
  if [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
    python_bin="$ROOT_DIR/.venv/bin/python"
  fi
  run_required "pytest_full" "$python_bin" -m pytest tests -q
}

printf 'SecureWave final Linux gate\n'
printf 'Logs: %s\n' "$LOG_DIR"

if [[ "$WRITE_AUTH_FILE" == "true" ]]; then
  write_auth_file
fi
if [[ "$PROVISION_LIVE_ACCOUNT" == "true" ]]; then
  provision_live_account
fi
export_auth_file_if_present

run_required "runtime_verifier" python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout "$PKEXEC_TIMEOUT"
check_version_alignment
run_demo_preflight

if [[ "$FULL_TESTS" == "true" ]]; then
  run_full_tests
fi

if [[ "$APP_PROOF" == "true" ]]; then
  run_app_proof
fi

if [[ "$RELEASE" == "true" ]]; then
  run_required "release_preflight" bash scripts/release_preflight.sh
fi

summary="$LOG_DIR/summary.txt"
{
  echo "SecureWave final Linux gate"
  echo "timestamp=$TIMESTAMP"
  echo "blockers=$BLOCKERS"
  echo "warnings=$WARNINGS"
  echo "steps=$STEP_COUNT"
  echo "connected=$CONNECTED"
  echo "app_proof=$APP_PROOF"
  echo "full_tests=$FULL_TESTS"
  echo "provision_live_account=$PROVISION_LIVE_ACCOUNT"
  echo "release=$RELEASE"
  echo "logs=$LOG_DIR"
} >"$summary"

printf '\nSummary: blockers=%s warnings=%s logs=%s\n' "$BLOCKERS" "$WARNINGS" "$LOG_DIR"
if (( BLOCKERS > 0 )); then
  exit 1
fi
exit 0
