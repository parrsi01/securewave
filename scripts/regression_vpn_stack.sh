#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/vpn_checks.sh"

REPORTS_DIR="${ROOT_DIR}/reports"
SNAPSHOT_DIR="${REPORTS_DIR}/snapshots"
TS="$(date -u +"%Y%m%dT%H%M%SZ")"
REPORT_FILE="${REPORTS_DIR}/regression_${TS}.txt"

mkdir -p "${REPORTS_DIR}" "${SNAPSHOT_DIR}"
exec > >(tee -a "${REPORT_FILE}") 2>&1

FAILURES=0
DRY_RUN_COUNT=0

PRECHECKS=(
  "scripts/verify_policy_routing.sh"
  "scripts/verify_nat_isolation.sh"
  "scripts/verify_teardown_safety.sh"
  "scripts/verify_wireguard_regression.sh"
  "scripts/verify_openvpn_connectivity.sh"
  "scripts/verify_ikev2_coexistence.sh"
  "scripts/verify_throughput_sanity.sh"
  "scripts/verify_shaping.sh"
)

log() {
  printf '[%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

mark_fail() {
  FAILURES=$((FAILURES + 1))
  log "FAIL: $*"
}

run_check() {
  local script_rel="$1"
  local script_path="${ROOT_DIR}/${script_rel}"

  if [[ ! -f "$script_path" ]]; then
    mark_fail "missing preflight script: ${script_rel}"
    return 0
  fi
  if [[ ! -x "$script_path" ]]; then
    mark_fail "preflight script is not executable: ${script_rel}"
    return 0
  fi

  log "preflight: ${script_rel}"
  if "$script_path"; then
    log "preflight ok: ${script_rel}"
  else
    mark_fail "preflight failed: ${script_rel}"
  fi
}

shuffle_protocols() {
  printf '%s\n' "${VPN_PROTOCOLS[@]}" | shuf
}

connector_cmd_exists() {
  [[ -x "/usr/local/bin/securewave-vpn-routing" ]] || [[ -x "${ROOT_DIR}/scripts/setup_vpn_routing.sh" ]]
}

run_connect() {
  local proto="$1"
  local output=""
  if [[ -x "/usr/local/bin/securewave-vpn-routing" ]]; then
    if output="$(/usr/local/bin/securewave-vpn-routing setup "$proto" 2>&1)"; then
      [[ -n "${output}" ]] && printf '%s\n' "${output}"
      return 0
    fi
    printf '%s\n' "${output}" >&2
    if grep -q "RTNETLINK answers: File exists" <<<"${output}"; then
      log "connect ${proto}: treating existing route state as already configured"
      return 0
    fi
    return 1
  elif [[ -x "${ROOT_DIR}/scripts/setup_vpn_routing.sh" ]]; then
    if output="$("${ROOT_DIR}/scripts/setup_vpn_routing.sh" setup "$proto" 2>&1)"; then
      [[ -n "${output}" ]] && printf '%s\n' "${output}"
      return 0
    fi
    printf '%s\n' "${output}" >&2
    if grep -q "RTNETLINK answers: File exists" <<<"${output}"; then
      log "connect ${proto}: treating existing route state as already configured"
      return 0
    fi
    # Best-effort lifecycle: treat "File exists" as already configured.
    return 1
  else
    return 2
  fi
}

run_disconnect() {
  local proto="$1"
  if [[ -x "/usr/local/bin/securewave-vpn-routing" ]]; then
    if /usr/local/bin/securewave-vpn-routing teardown "$proto"; then
      return 0
    fi
    return 1
  elif [[ -x "${ROOT_DIR}/scripts/setup_vpn_routing.sh" ]]; then
    if "${ROOT_DIR}/scripts/setup_vpn_routing.sh" teardown "$proto"; then
      return 0
    fi
    return 1
  else
    return 2
  fi
}

assert_post_disconnect_isolation() {
  local disconnected="$1"
  shift
  local -a still_connected=("$@")

  local nat_rules
  nat_rules="$(iptables -t nat -S 2>/dev/null || true)"

  for other in "${still_connected[@]}"; do
    local chain
    chain="$(protocol_chain "$other")"
    local hook_count
    hook_count="$(grep -cE "^-A POSTROUTING -j ${chain}$" <<<"$nat_rules" || true)"
    if [[ "$hook_count" -ne 1 ]]; then
      mark_fail "teardown of ${disconnected} changed active hook for ${other} (${chain}); count=${hook_count}"
    fi
  done
}

capture_and_drift() {
  local step="$1"
  shift
  local -a active_protocols=("$@")
  local snapshot_file
  snapshot_file="$(snapshot_state "$step" "$SNAPSHOT_DIR")"
  log "snapshot: ${snapshot_file}"

  if ! check_default_route_drift "$BASELINE_DEFAULT_ROUTE"; then
    FAILURES=$((FAILURES + 1))
  fi
  if [[ "${#active_protocols[@]}" -gt 0 ]]; then
    if ! check_nat_integrity "${active_protocols[@]}"; then
      FAILURES=$((FAILURES + $?))
    fi
  fi
  if ! check_global_shaping_drift "$BASELINE_DEFAULT_IFACE"; then
    FAILURES=$((FAILURES + 1))
  fi
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: run as root (required for iptables/tc and root-only checks)" >&2
    exit 2
  fi

  if ! command_exists ip || ! command_exists iptables || ! command_exists tc; then
    echo "ERROR: missing dependency (ip, iptables, tc required)" >&2
    exit 2
  fi

  log "starting vpn stack regression"
  BASELINE_DEFAULT_ROUTE="$(detect_default_route_line)"
  BASELINE_DEFAULT_IFACE="$(detect_default_iface)"
  log "baseline default route: ${BASELINE_DEFAULT_ROUTE:-<empty>}"
  log "baseline default iface: ${BASELINE_DEFAULT_IFACE:-<empty>}"

  if [[ -x "/usr/local/bin/securewave-vpn-routing" ]]; then
    log "bootstrap: /usr/local/bin/securewave-vpn-routing setup"
    if ! /usr/local/bin/securewave-vpn-routing setup; then
      mark_fail "bootstrap failed: /usr/local/bin/securewave-vpn-routing setup"
    fi
  elif [[ -x "${ROOT_DIR}/scripts/setup_vpn_routing.sh" ]]; then
    log "bootstrap: scripts/setup_vpn_routing.sh setup"
    if ! "${ROOT_DIR}/scripts/setup_vpn_routing.sh" setup; then
      mark_fail "bootstrap failed: scripts/setup_vpn_routing.sh setup"
    fi
  else
    mark_fail "bootstrap skipped: no routing setup command found"
  fi

  capture_and_drift "baseline"

  log "running preflight checks"
  for check_script in "${PRECHECKS[@]}"; do
    run_check "$check_script"
  done

  local has_real_connectors=0
  if connector_cmd_exists; then
    has_real_connectors=1
    log "connect/disconnect mode: real commands"
  else
    DRY_RUN_COUNT=$((DRY_RUN_COUNT + 1))
    log "connect/disconnect mode: dry-run (no lifecycle command found)"
  fi

  local -a connect_order=()
  mapfile -t connect_order < <(shuffle_protocols)
  log "random connect order: ${connect_order[*]}"

  local -a connected=()

  for proto in "${connect_order[@]}"; do
    log "step connect ${proto}"
    if [[ "$has_real_connectors" -eq 1 ]]; then
      if run_connect "$proto"; then
        connected+=("$proto")
      else
        mark_fail "connect command failed for ${proto}"
        # Keep transition flow for isolation checks even when setup is already present.
        connected+=("$proto")
      fi
    else
      DRY_RUN_COUNT=$((DRY_RUN_COUNT + 1))
      log "dry-run connect ${proto}"
      connected+=("$proto")
    fi
    capture_and_drift "connect_${proto}" "${connected[@]}"
  done

  local -a disconnect_order=()
  if [[ "${#connected[@]}" -gt 0 ]]; then
    mapfile -t disconnect_order < <(printf '%s\n' "${connected[@]}" | shuf)
  fi
  log "random disconnect order: ${disconnect_order[*]:-<none>}"

  local -a still_connected=("${connected[@]}")
  for proto in "${disconnect_order[@]}"; do
    [[ -z "${proto}" ]] && continue
    log "step disconnect ${proto}"
    if [[ "$has_real_connectors" -eq 1 ]]; then
      if ! run_disconnect "$proto"; then
        mark_fail "disconnect command failed for ${proto}"
      fi
    else
      DRY_RUN_COUNT=$((DRY_RUN_COUNT + 1))
      log "dry-run disconnect ${proto}"
    fi

    local -a next_connected=()
    local p
    for p in "${still_connected[@]}"; do
      if [[ "$p" != "$proto" ]]; then
        next_connected+=("$p")
      fi
    done
    still_connected=("${next_connected[@]}")

    capture_and_drift "disconnect_${proto}" "${still_connected[@]}"
    assert_post_disconnect_isolation "$proto" "${still_connected[@]}"
  done

  capture_and_drift "final" "${still_connected[@]}"

  echo
  log "report file: ${REPORT_FILE}"
  log "dry-run steps: ${DRY_RUN_COUNT}"

  if [[ "$FAILURES" -gt 0 ]]; then
    log "regression result: FAILED (${FAILURES} issues)"
    exit 1
  fi

  log "regression result: OK"
}

main "$@"
