#!/usr/bin/env bash
set -euo pipefail

export FLUTTER_SKIP_UPDATE_CHECK=true
export FLUTTER_SUPPRESS_ANALYTICS=true

BASE_URL="${BASE_URL:-http://127.0.0.1:8000}"
FREE_EMAIL="${FREE_EMAIL:-}"
FREE_PASSWORD="${FREE_PASSWORD:-}"
PREMIUM_EMAIL="${PREMIUM_EMAIL:-}"
PREMIUM_PASSWORD="${PREMIUM_PASSWORD:-}"
CONNECT_CMD="${CONNECT_CMD:-}"
DISCONNECT_CMD="${DISCONNECT_CMD:-}"
EXPECT_FULL_TUNNEL="${EXPECT_FULL_TUNNEL:-unknown}" # yes|no|unknown
RUN_FLUTTER_TESTS=1
RUN_RUNTIME_PROBE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --free-email)
      FREE_EMAIL="${2:-}"
      shift 2
      ;;
    --free-password)
      FREE_PASSWORD="${2:-}"
      shift 2
      ;;
    --premium-email)
      PREMIUM_EMAIL="${2:-}"
      shift 2
      ;;
    --premium-password)
      PREMIUM_PASSWORD="${2:-}"
      shift 2
      ;;
    --connect-cmd)
      CONNECT_CMD="${2:-}"
      shift 2
      ;;
    --disconnect-cmd)
      DISCONNECT_CMD="${2:-}"
      shift 2
      ;;
    --expect-full-tunnel)
      EXPECT_FULL_TUNNEL="${2:-unknown}"
      shift 2
      ;;
    --skip-flutter-tests)
      RUN_FLUTTER_TESTS=0
      shift
      ;;
    --skip-runtime-probe)
      RUN_RUNTIME_PROBE=0
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: full_stack_alignment.sh [options]

Options:
  --base-url URL
  --free-email EMAIL --free-password PASSWORD
  --premium-email EMAIL --premium-password PASSWORD
  --connect-cmd "..."
  --disconnect-cmd "..."
  --expect-full-tunnel yes|no|unknown
  --skip-flutter-tests
  --skip-runtime-probe
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT_ROOT="${SCRIPT_DIR}/out"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${OUT_ROOT}/fullstack_${RUN_ID}"
REPORT="${OUT_DIR}/FULL_STACK_ALIGNMENT_REPORT.md"
mkdir -p "${OUT_DIR}"

passes=()
fails=()
warns=()
exceptions=()

append_report() {
  printf '%s\n' "$*" >>"${REPORT}"
}

add_pass() {
  passes+=("$1")
}

add_fail() {
  fails+=("$1")
}

add_warn() {
  warns+=("$1")
}

add_exception() {
  exceptions+=("$1")
}

capture_cmd() {
  local name="$1"
  shift
  local file="${OUT_DIR}/${name}.txt"
  {
    printf '$'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    "$@"
  } >"${file}" 2>&1
  local rc=$?
  printf '%s\n' "${rc}" >"${file}.rc"
  return "${rc}"
}

capture_cmd_redacted() {
  local name="$1"
  local display="$2"
  shift 2
  local file="${OUT_DIR}/${name}.txt"
  {
    printf '$ %s\n' "${display}"
    "$@"
  } >"${file}" 2>&1
  local rc=$?
  printf '%s\n' "${rc}" >"${file}.rc"
  return "${rc}"
}

capture_shell() {
  local name="$1"
  shift
  capture_cmd "${name}" bash -lc "$*"
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

extract_token() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.access_token // empty' "${file}" 2>/dev/null || true
    return
  fi
  grep -Eo '"access_token"[[:space:]]*:[[:space:]]*"[^"]+"' "${file}" \
    | head -1 \
    | sed -E 's/.*"access_token"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true
}

redact_tokens_file() {
  local src="$1"
  local dst="$2"
  sed -E \
    -e 's/"access_token"[[:space:]]*:[[:space:]]*"[^"]*"/"access_token":"[REDACTED]"/g' \
    -e 's/"refresh_token"[[:space:]]*:[[:space:]]*"[^"]*"/"refresh_token":"[REDACTED]"/g' \
    "${src}" >"${dst}"
}

evaluate_protocols() {
  local file="$1"
  local prefix="$2"
  if ! command -v jq >/dev/null 2>&1; then
    add_exception "${prefix}: jq not installed; protocol assertions skipped."
    return
  fi
  local enabled
  enabled="$(jq -r '[.protocols[] | select(.enabled == true) | .protocol] | sort | join(",")' "${file}" 2>/dev/null || true)"
  if [[ "${enabled}" == *"wireguard"* && "${enabled}" == *"openvpn"* && "${enabled}" == *"ikev2"* ]]; then
    add_pass "${prefix}: all 3 protocols enabled (wireguard/openvpn/ikev2)."
  else
    add_fail "${prefix}: protocol enablement mismatch (${enabled:-none})."
  fi
}

evaluate_locations() {
  local file="$1"
  local prefix="$2"
  if ! command -v jq >/dev/null 2>&1; then
    add_exception "${prefix}: jq not installed; location assertions skipped."
    return
  fi
  local total premium
  total="$(jq -r '(.regions // .servers // []) | length' "${file}" 2>/dev/null || echo 0)"
  premium="$(jq -r '[((.regions // .servers // [])[]?) | select((.premium_only == true) or ((.tier_restriction // "" | ascii_downcase) == "premium"))] | length' "${file}" 2>/dev/null || echo 0)"
  if (( total >= 5 )); then
    add_pass "${prefix}: location count ${total} (>=5)."
  else
    add_fail "${prefix}: location count ${total} (<5)."
  fi
  if (( premium >= 3 )); then
    add_pass "${prefix}: premium location markers ${premium} (>=3)."
  else
    add_fail "${prefix}: premium location markers ${premium} (<3)."
  fi
}

append_report "# SecureWave Full-Stack Alignment Report"
append_report ""
append_report "- Run ID: \`${RUN_ID}\`"
append_report "- Base URL: \`${BASE_URL}\`"
append_report "- Output dir: \`${OUT_DIR}\`"
append_report ""

append_report "## Baseline Network Capture"
capture_shell "baseline_date" "date -Is" || true
capture_shell "baseline_uname" "uname -a" || true
capture_shell "baseline_ip_addr" "ip addr" || true
capture_shell "baseline_ip_route" "ip route" || true
capture_shell "baseline_ip_rule" "ip rule show" || true
capture_shell "baseline_nmcli_general" "nmcli -t -f GENERAL.STATE general status" || true
capture_shell "baseline_nmcli_devices" "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status" || true
capture_shell "baseline_resolvectl" "resolvectl status" || true
capture_shell "baseline_wg_show" "wg show" || true
if capture_cmd "backend_health" curl -fsS --max-time 10 "${BASE_URL}/api/health"; then
  add_pass "Backend health endpoint reachable."
else
  add_fail "Backend health endpoint unreachable."
fi

login_account() {
  local label="$1"
  local email="$2"
  local password="$3"
  local login_file="${OUT_DIR}/${label}_login_raw.json"
  if [[ -z "${email}" || -z "${password}" ]]; then
    add_exception "${label}: credentials not provided; API capability checks skipped."
    return 1
  fi
  local payload
  payload="$(printf '{"email":"%s","password":"%s"}' \
    "$(json_escape "${email}")" \
    "$(json_escape "${password}")")"
  if ! capture_cmd_redacted \
      "${label}_login_http" \
      "curl -fsS --max-time 15 -H 'Content-Type: application/json' -X POST ${BASE_URL}/api/auth/login -d '{...REDACTED...}'" \
      curl -fsS --max-time 15 \
      -H "Content-Type: application/json" \
      -X POST "${BASE_URL}/api/auth/login" \
      -d "${payload}"; then
    add_fail "${label}: login failed."
    return 1
  fi
  cp "${OUT_DIR}/${label}_login_http.txt" "${login_file}"
  redact_tokens_file "${login_file}" "${OUT_DIR}/${label}_login.json"
  local token
  token="$(extract_token "${login_file}")"
  rm -f "${login_file}"
  if [[ -z "${token}" ]]; then
    add_fail "${label}: login succeeded but no access token returned."
    return 1
  fi
  printf '%s' "${token}"
  return 0
}

fetch_api_bundle() {
  local label="$1"
  local token="$2"
  capture_cmd_redacted \
    "${label}_protocols" \
    "curl -fsS --max-time 15 -H 'Authorization: Bearer [REDACTED]' ${BASE_URL}/api/vpn/protocols?device_type=linux" \
    curl -fsS --max-time 15 \
    -H "Authorization: Bearer ${token}" \
    "${BASE_URL}/api/vpn/protocols?device_type=linux" || true
  capture_cmd_redacted \
    "${label}_protocol_capabilities" \
    "curl -fsS --max-time 15 -H 'Authorization: Bearer [REDACTED]' ${BASE_URL}/api/vpn/protocol-capabilities?device_type=linux" \
    curl -fsS --max-time 15 \
    -H "Authorization: Bearer ${token}" \
    "${BASE_URL}/api/vpn/protocol-capabilities?device_type=linux" || true
  capture_cmd_redacted \
    "${label}_servers" \
    "curl -fsS --max-time 15 -H 'Authorization: Bearer [REDACTED]' ${BASE_URL}/api/vpn/servers" \
    curl -fsS --max-time 15 \
    -H "Authorization: Bearer ${token}" \
    "${BASE_URL}/api/vpn/servers" || true
  capture_cmd_redacted \
    "${label}_regions" \
    "curl -fsS --max-time 15 -H 'Authorization: Bearer [REDACTED]' ${BASE_URL}/api/vpn/regions" \
    curl -fsS --max-time 15 \
    -H "Authorization: Bearer ${token}" \
    "${BASE_URL}/api/vpn/regions" || true
  capture_cmd_redacted \
    "${label}_user_plan" \
    "curl -fsS --max-time 15 -H 'Authorization: Bearer [REDACTED]' ${BASE_URL}/api/user/plan" \
    curl -fsS --max-time 15 \
    -H "Authorization: Bearer ${token}" \
    "${BASE_URL}/api/user/plan" || true
}

premium_token=""
if premium_token="$(login_account "premium" "${PREMIUM_EMAIL}" "${PREMIUM_PASSWORD}")"; then
  add_pass "premium: login succeeded."
  fetch_api_bundle "premium" "${premium_token}"
  evaluate_protocols "${OUT_DIR}/premium_protocols.txt" "premium"
  evaluate_locations "${OUT_DIR}/premium_regions.txt" "premium"
else
  add_exception "premium: skipped because login failed or credentials missing."
fi

free_token=""
if free_token="$(login_account "free" "${FREE_EMAIL}" "${FREE_PASSWORD}")"; then
  add_pass "free: login succeeded."
  fetch_api_bundle "free" "${free_token}"
  evaluate_protocols "${OUT_DIR}/free_protocols.txt" "free"
else
  add_exception "free: skipped because login failed or credentials missing."
fi

if [[ "${RUN_FLUTTER_TESTS}" -eq 1 ]]; then
  if capture_shell "flutter_validation_tests" "cd '${REPO_ROOT}/securewave_app' && export FLUTTER_SKIP_UPDATE_CHECK=true FLUTTER_SUPPRESS_ANALYTICS=true && flutter test test/preferences_state_test.dart test/protocol_selector_test.dart test/protocol_capability_matrix_test.dart test/state_machine/auto_connect_listener_test.dart test/state_machine/multiple_concurrent_connect_requests_test.dart test/vpn_state_test.dart"; then
    add_pass "Flutter validation test slice passed."
  else
    if grep -Eqi 'engine\.stamp: Permission denied|flutter/bin/cache' \
        "${OUT_DIR}/flutter_validation_tests.txt" 2>/dev/null; then
      add_exception "Flutter validation slice blocked by sandbox/write permissions on Flutter cache."
    else
      add_fail "Flutter validation test slice failed."
    fi
  fi
else
  add_warn "Flutter tests skipped by flag."
fi

if [[ "${RUN_RUNTIME_PROBE}" -eq 1 ]]; then
  if [[ -z "${CONNECT_CMD}" || -z "${DISCONNECT_CMD}" ]]; then
    for cfg in "${HOME}/.config/securewave/securewave-wireguard.conf" "${HOME}/.config/securewave/sw-wg.conf"; do
      if [[ -f "${cfg}" && -x "/usr/local/libexec/securewave-wg-quick" ]]; then
        CONNECT_CMD="pkexec /usr/local/libexec/securewave-wg-quick up ${cfg}"
        DISCONNECT_CMD="pkexec /usr/local/libexec/securewave-wg-quick down ${cfg}"
        break
      fi
    done
  fi

  if [[ -z "${CONNECT_CMD}" || -z "${DISCONNECT_CMD}" ]]; then
    add_exception "Runtime probe skipped: no connect/disconnect command configured."
  else
    if capture_cmd "runtime_probe_run" \
      "${SCRIPT_DIR}/run_probe.sh" \
      --connect-cmd "${CONNECT_CMD}" \
      --disconnect-cmd "${DISCONNECT_CMD}" \
      --expect-full-tunnel "${EXPECT_FULL_TUNNEL}"; then
      add_pass "Runtime probe completed successfully."
    else
      if grep -Eqi 'pkexec must be setuid root|no desktop authentication session|permission required|authentication agent' \
          "${OUT_DIR}/runtime_probe_run.txt" 2>/dev/null; then
        add_exception "Runtime probe blocked by host privilege/elevation configuration."
      else
        add_fail "Runtime probe failed."
      fi
    fi
  fi
else
  add_warn "Runtime probe skipped by flag."
fi

capture_shell "post_nmcli_general" "nmcli -t -f GENERAL.STATE general status" || true
capture_shell "post_nmcli_devices" "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status" || true
capture_shell "post_ip_route" "ip route" || true
capture_shell "post_ip_rule" "ip rule show" || true
capture_shell "post_resolvectl" "resolvectl status" || true

wifi_before="$(grep -Ec ':wifi:connected' "${OUT_DIR}/baseline_nmcli_devices.txt" 2>/dev/null || true)"
wifi_after="$(grep -Ec ':wifi:connected' "${OUT_DIR}/post_nmcli_devices.txt" 2>/dev/null || true)"
if [[ "${wifi_before}" != "0" && "${wifi_after}" == "0" ]]; then
  add_warn "Wi-Fi was connected before tests and disconnected afterward."
fi

append_report "## Verdict"
append_report ""
append_report "- Passes: ${#passes[@]}"
append_report "- Fails: ${#fails[@]}"
append_report "- Warnings: ${#warns[@]}"
append_report "- Exceptions: ${#exceptions[@]}"
append_report ""

append_report "## Passes"
append_report ""
if [[ "${#passes[@]}" -eq 0 ]]; then
  append_report "- None"
else
  for item in "${passes[@]}"; do
    append_report "- ${item}"
  done
fi

append_report ""
append_report "## Fails"
append_report ""
if [[ "${#fails[@]}" -eq 0 ]]; then
  append_report "- None"
else
  for item in "${fails[@]}"; do
    append_report "- ${item}"
  done
fi

append_report ""
append_report "## Warnings"
append_report ""
if [[ "${#warns[@]}" -eq 0 ]]; then
  append_report "- None"
else
  for item in "${warns[@]}"; do
    append_report "- ${item}"
  done
fi

append_report ""
append_report "## Exceptions"
append_report ""
if [[ "${#exceptions[@]}" -eq 0 ]]; then
  append_report "- None"
else
  for item in "${exceptions[@]}"; do
    append_report "- ${item}"
  done
fi

append_report ""
append_report "## Evidence Files"
append_report ""
append_report "- Baseline network: \`baseline_ip_addr.txt\`, \`baseline_ip_route.txt\`, \`baseline_ip_rule.txt\`, \`baseline_nmcli_devices.txt\`"
append_report "- Backend checks: \`backend_health.txt\`, \`premium_protocols.txt\`, \`premium_regions.txt\`, \`free_protocols.txt\`"
append_report "- Flutter tests: \`flutter_validation_tests.txt\`"
append_report "- Runtime probe: \`runtime_probe_run.txt\`"
append_report "- Post network: \`post_nmcli_devices.txt\`, \`post_ip_route.txt\`, \`post_ip_rule.txt\`"

echo "[full_stack_alignment] report: ${REPORT}"
echo "[full_stack_alignment] output: ${OUT_DIR}"

if [[ "${#fails[@]}" -gt 0 ]]; then
  exit 1
fi
exit 0
