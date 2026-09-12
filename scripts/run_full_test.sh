#!/usr/bin/env bash
# Run SecureWave's source, package, public-service, installed-runtime, and UI
# checks as one fail-closed test command. Live tunnel proof is opt-in.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/securewave_app"
ARTIFACT_DIR="${SECUREWAVE_TEST_ARTIFACT_DIR:-$(mktemp -d /tmp/securewave-full-test.XXXXXX)}"
mkdir -p "$ARTIFACT_DIR"

usage() {
  cat <<'EOF'
Usage: bash scripts/run_full_test.sh [options]

Options:
  --live                    Run explicit real WireGuard acceptance proof.
  --skip-package            Skip local .deb construction.
  --skip-installed          Skip installed package, UI, and helper checks.
  --artifact-dir PATH       Store logs and reports at PATH.
EOF
}

RUN_LIVE=false
RUN_PACKAGE=true
RUN_INSTALLED=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) RUN_LIVE=true; shift ;;
    --skip-package) RUN_PACKAGE=false; shift ;;
    --skip-installed) RUN_INSTALLED=false; shift ;;
    --artifact-dir)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      ARTIFACT_DIR="$2"
      mkdir -p "$ARTIFACT_DIR"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "${PYTHON_BIN:-}" ]]; then
  PYTHON_BIN="$PYTHON_BIN"
elif [[ -x "$ROOT_DIR/venv/bin/python" ]]; then
  PYTHON_BIN="$ROOT_DIR/venv/bin/python"
else
  PYTHON_BIN="$(command -v python3 || true)"
fi
SYSTEM_PYTHON="$(command -v python3 || true)"
if [[ -z "$PYTHON_BIN" || -z "$SYSTEM_PYTHON" ]]; then
  echo "Python 3 is required." >&2
  exit 2
fi

declare -a FAILURES=()
declare -a SKIPS=()

run_step() {
  local label="$1"
  shift
  local log_file="$ARTIFACT_DIR/${label}.log"
  : >"$log_file"
  chmod 600 "$log_file"
  echo "RUN  $label"
  if "$@" >>"$log_file" 2>&1; then
    echo "PASS $label"
  else
    local status=$?
    if [[ "$status" -eq 3 ]]; then
      echo "SKIP $label"
      SKIPS+=("$label")
    else
      echo "FAIL $label (details: $log_file)"
      FAILURES+=("$label")
    fi
  fi
}

run_root() { (cd "$ROOT_DIR" && "$@"); }
run_app() { (cd "$APP_DIR" && "$@"); }

public_smoke() {
  local api_base="${SECUREWAVE_PUBLIC_API_BASE_URL:-https://api.securewaveapp.com}"
  local site_base="${SECUREWAVE_PUBLIC_SITE_URL:-https://securewaveapp.com}"
  "$PYTHON_BIN" - "$api_base" "$site_base" <<'PY'
import sys
import urllib.error
import urllib.request

api_base = sys.argv[1].rstrip('/')
site_base = sys.argv[2].rstrip('/')

def status(url):
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except Exception as error:  # noqa: BLE001 - public smoke reports status only.
        print(f"ERROR {url} {type(error).__name__}")
        return None

checks = [
    (api_base + '/version', 200),
    (api_base + '/health', 200),
    (api_base + '/api/health', 200),
    (api_base + '/api/health/email', 200),
    (api_base + '/api/downloads', 200),
    (api_base + '/api/auth/me', 401),
    (api_base + '/api/vpn/servers', 401),
    (api_base + '/api/vpn/status', 401),
    (api_base + '/api/vpn/config', 401),
    (site_base + '/', 200),
    (site_base + '/index.html', 200),
    (site_base + '/login', 200),
    (site_base + '/register', 200),
    (site_base + '/dashboard', 200),
    (site_base + '/vpn', 200),
    (site_base + '/download', 200),
    (site_base + '/verify-email', 200),
    (site_base + '/settings', 200),
]
failed = False
for url, expected in checks:
    observed = status(url)
    print(f'{observed} expected={expected} {url}')
    failed |= observed != expected
raise SystemExit(1 if failed else 0)
PY
}

verify_installed_package() {
  if ! command -v dpkg-query >/dev/null 2>&1 ||
     ! dpkg-query -W -f='${Status}' securewave-vpn 2>/dev/null | grep -q 'install ok installed'; then
    echo "No installed securewave-vpn package is available."
    return 3
  fi

  local marker="/usr/share/securewave/release/source-sha"
  local contract="/usr/share/securewave/release/helper-contract"
  [[ -x /usr/bin/securewave-vpn ]] || { echo "installed launcher missing"; return 1; }
  [[ -f "$marker" ]] || { echo "installed source marker missing"; return 1; }
  [[ -f "$contract" ]] || { echo "installed helper contract marker missing"; return 1; }
  [[ "$(tr -d '[:space:]' < "$contract")" == "13" ]] || {
    echo "installed helper contract is not 13"
    return 1
  }
  if ! dpkg -V securewave-vpn >/dev/null 2>&1; then
    echo "dpkg reports modified installed package files"
    return 1
  fi

  local installed_sha current_sha
  installed_sha="$(tr -d '[:space:]' < "$marker")"
  current_sha="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  if [[ "$installed_sha" != "$current_sha" ]]; then
    echo "installed source $installed_sha differs from tested source $current_sha"
    return 1
  fi
  if ! git -C "$ROOT_DIR" show "$installed_sha:securewave_app/lib/ui/sw_theme.dart" 2>/dev/null |
      grep -q 'securewave-black-blue-v1'; then
    echo "installed source does not contain the locked black/blue design system"
    return 1
  fi
}

run_step backend_pytest run_root "$PYTHON_BIN" -m pytest tests -q \
  --junitxml="$ARTIFACT_DIR/backend-junit.xml"
run_step flutter_analyze run_app flutter analyze
run_step flutter_test run_app flutter test --reporter expanded
run_step flutter_linux_build run_app flutter build linux --release
run_step ui_guard run_root bash scripts/verify_ui_v1.sh
run_step website_guard run_root bash scripts/verify_website.sh
run_step release_guard run_root bash scripts/verify_release_guards.sh
run_step public_smoke public_smoke

if [[ "$RUN_PACKAGE" == true ]]; then
  run_step linux_deb_build run_root env SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}" \
    bash securewave_app/scripts/build_deb.sh
else
  echo "SKIP linux_deb_build (requested)"
  SKIPS+=(linux_deb_build)
fi

if [[ "$RUN_INSTALLED" == true ]]; then
  run_step installed_package verify_installed_package
  if [[ -x /usr/bin/securewave-vpn && -n "$SYSTEM_PYTHON" ]]; then
    run_step installed_ui_smoke "$SYSTEM_PYTHON" \
      "$ROOT_DIR/scripts/linux_installed_app_smoke.py" --json
  else
    echo "SKIP installed_ui_smoke (installed launcher unavailable)"
    SKIPS+=(installed_ui_smoke)
  fi
  if [[ -S /run/securewave/helper.sock ]]; then
    run_step installed_runtime "$PYTHON_BIN" \
      "$ROOT_DIR/scripts/linux_vpn_runtime_verifier.py" --json --skip-build-checks
  else
    echo "SKIP installed_runtime (helper socket unavailable)"
    SKIPS+=(installed_runtime)
  fi
else
  echo "SKIP installed_package (requested)"
  echo "SKIP installed_ui_smoke (requested)"
  echo "SKIP installed_runtime (requested)"
  SKIPS+=(installed_package installed_ui_smoke installed_runtime)
fi

if [[ "$RUN_LIVE" == true ]]; then
  run_live() {
    local auth_file="${SECUREWAVE_CERT_AUTH_FILE:-$ROOT_DIR/securewave_private/live_certification_account.env}"
    local live_api="${SECUREWAVE_LIVE_API_BASE_URL:-https://api.securewaveapp.com/api}"
    [[ -f "$auth_file" ]] || { echo "live credential file is missing"; return 1; }
    SECUREWAVE_ALLOW_PRODUCTION_PROOF=true "$PYTHON_BIN" \
      "$ROOT_DIR/scripts/linux_app_vpn_tunnel_proof.py" \
      --api-base "$live_api" \
      --allow-production --auth-file "$auth_file" --protocol wireguard \
      --hold-seconds "${SECUREWAVE_LIVE_HOLD_SECONDS:-20}" \
      --evidence-timeout "${SECUREWAVE_LIVE_EVIDENCE_TIMEOUT:-120}" --json
  }
  run_step live_wireguard run_live
else
  echo "SKIP live_wireguard (pass --live for explicit real VPN acceptance)"
  SKIPS+=(live_wireguard)
fi

echo
echo "Full test artifacts: $ARTIFACT_DIR"
if ((${#FAILURES[@]})); then
  echo "FAILED COMPONENTS: ${FAILURES[*]}"
  echo "SKIPPED COMPONENTS: ${SKIPS[*]:-none}"
  exit 1
fi
echo "ALL REQUIRED COMPONENTS PASSED"
echo "SKIPPED COMPONENTS: ${SKIPS[*]:-none}"
