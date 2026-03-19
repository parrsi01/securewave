#!/usr/bin/env bash
set -euo pipefail

IFACE="${1:-sw-wg}"
CONFIG_PATH="${2:-$HOME/.config/securewave/sw-wg.conf}"
DURATION_MINUTES="${DURATION_MINUTES:-30}"
CYCLE_SECONDS="${CYCLE_SECONDS:-45}"
IDLE_SECONDS="${IDLE_SECONDS:-20}"
CONNECT_TIMEOUT_SECONDS="${CONNECT_TIMEOUT_SECONDS:-20}"
HANDSHAKE_MAX_AGE="${HANDSHAKE_MAX_AGE:-30}"
TABLE_ID="${TABLE_ID:-51820}"
FWMARK="${FWMARK:-51820}"
POLICY_PRIORITY="${POLICY_PRIORITY:-32764}"
SUPPRESS_PRIORITY="${SUPPRESS_PRIORITY:-32765}"
PING_TARGET="${PING_TARGET:-8.8.8.8}"
IFCONFIG_URL="${IFCONFIG_URL:-https://ifconfig.me/ip}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR%/scripts}/logs"
LOG_FILE="${LOG_DIR}/long_run_test.json"
TMP_CYCLES="$(mktemp)"
WATCHDOG_PID=""

cleanup() {
  if [[ -n "${WATCHDOG_PID}" ]]; then
    kill "${WATCHDOG_PID}" >/dev/null 2>&1 || true
    wait "${WATCHDOG_PID}" >/dev/null 2>&1 || true
  fi
  wg-quick down "$CONFIG_PATH" >/dev/null 2>&1 || true
  clear_policy_state 1 >/dev/null 2>&1 || true
  rm -f "$TMP_CYCLES"
}
trap cleanup EXIT

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0 ${IFACE@Q} ${CONFIG_PATH@Q}" >&2
    exit 1
  fi
}

ensure_prereqs() {
  local missing=0
  for bin in ip wg wg-quick nmcli ping curl date awk grep sed; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "Missing required command: $bin" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_ms() {
  date +%s%3N
}

json_escape() {
  printf '%s' "${1:-}" |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

policy_rule_count() {
  ip rule show | awk -v table="$TABLE_ID" '
    index($0, "lookup " table) && index($0, "fwmark") && index($0, "not") { count++ }
    END { print count + 0 }
  '
}

main_suppress_count() {
  ip rule show | awk '
    index($0, "lookup main") && index($0, "suppress_prefixlength 0") { count++ }
    END { print count + 0 }
  '
}

table_route_present() {
  ip -4 route show table "$TABLE_ID" 2>/dev/null |
    grep -q "^default dev ${IFACE}\( \|$\)"
}

networkmanager_unmanaged() {
  nmcli -t -f DEVICE,STATE device status 2>/dev/null |
    grep -q "^${IFACE}:unmanaged$"
}

fwmark_valid() {
  local value
  value="$(wg show "$IFACE" fwmark 2>/dev/null | tr -d '[:space:]')"
  [[ -n "$value" && "$value" != "off" ]] || return 1
  if [[ "$value" == "0x"* ]]; then
    (( value == FWMARK ))
  else
    [[ "$value" == "$FWMARK" ]]
  fi
}

latest_handshake_age() {
  local latest now age
  latest="$(
    wg show "$IFACE" latest-handshakes 2>/dev/null |
      awk 'BEGIN { latest = 0 } { if ($2 > latest) latest = $2 } END { print latest }'
  )"
  [[ -n "$latest" && "$latest" != "0" ]] || return 1
  now="$(date +%s)"
  age=$(( now - latest ))
  if (( age < 0 )); then
    age=0
  fi
  printf '%s\n' "$age"
}

clear_policy_state() {
  local remove_link="${1:-0}"
  while ip rule del not fwmark "$FWMARK" table "$TABLE_ID" priority "$POLICY_PRIORITY" >/dev/null 2>&1; do
    :
  done
  while ip rule del table main suppress_prefixlength 0 priority "$SUPPRESS_PRIORITY" >/dev/null 2>&1; do
    :
  done
  ip -4 route flush table "$TABLE_ID" >/dev/null 2>&1 || true
  ip -6 route flush table "$TABLE_ID" >/dev/null 2>&1 || true
  if [[ "$remove_link" == "1" ]]; then
    ip link delete "$IFACE" >/dev/null 2>&1 || true
  fi
  ip route flush cache >/dev/null 2>&1 || true
}

apply_policy_routing() {
  local policy_count suppress_count

  nmcli device set "$IFACE" managed no >/dev/null 2>&1 || true
  wg set "$IFACE" fwmark "$FWMARK"

  if ! table_route_present; then
    ip -4 route flush table "$TABLE_ID" >/dev/null 2>&1 || true
    ip -6 route flush table "$TABLE_ID" >/dev/null 2>&1 || true
    ip route add default dev "$IFACE" table "$TABLE_ID"
  fi

  policy_count="$(policy_rule_count)"
  suppress_count="$(main_suppress_count)"
  if (( policy_count > 1 || suppress_count > 1 )); then
    clear_policy_state 0
    ip route add default dev "$IFACE" table "$TABLE_ID"
    policy_count=0
    suppress_count=0
  fi
  if (( policy_count == 0 )); then
    ip rule add not fwmark "$FWMARK" table "$TABLE_ID" priority "$POLICY_PRIORITY"
  fi
  if (( suppress_count == 0 )); then
    ip rule add table main suppress_prefixlength 0 priority "$SUPPRESS_PRIORITY"
  fi
  ip route flush cache >/dev/null 2>&1 || true
}

route_consistent() {
  (( $(policy_rule_count) == 1 )) &&
    (( $(main_suppress_count) == 1 )) &&
    table_route_present
}

cleanup_clean() {
  local routes
  routes="$(ip -4 route show table "$TABLE_ID" 2>/dev/null | tr -d '[:space:]')"
  (( $(policy_rule_count) == 0 )) &&
    (( $(main_suppress_count) == 0 )) &&
    [[ -z "$routes" ]] &&
    ! ip link show "$IFACE" >/dev/null 2>&1
}

wait_for_healthy() {
  local started deadline age
  started="$(now_ms)"
  deadline=$(( started + (CONNECT_TIMEOUT_SECONDS * 1000) ))
  while (( $(now_ms) < deadline )); do
    if route_consistent && fwmark_valid && networkmanager_unmanaged; then
      if age="$(latest_handshake_age 2>/dev/null)" && (( age < HANDSHAKE_MAX_AGE )); then
        HEALTHY_HANDSHAKE_AGE="$age"
        HEALTHY_RECONNECT_MS=$(( $(now_ms) - started ))
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

start_watchdog() {
  "${SCRIPT_DIR}/vpn_watchdog.sh" "$IFACE" "$CONFIG_PATH" >/dev/null 2>&1 &
  WATCHDOG_PID=$!
}

stop_watchdog() {
  if [[ -n "${WATCHDOG_PID}" ]]; then
    kill "${WATCHDOG_PID}" >/dev/null 2>&1 || true
    wait "${WATCHDOG_PID}" >/dev/null 2>&1 || true
    WATCHDOG_PID=""
  fi
}

append_cycle() {
  local cycle_index="$1"
  local started_at="$2"
  local completed="$3"
  local reconnect_ms="$4"
  local handshake_age="$5"
  local route_ok="$6"
  local cleanup_ok="$7"
  local ping_ok="$8"
  local public_ip="$9"
  local failure_category="${10}"
  local failure_detail="${11}"
  printf '{' >>"$TMP_CYCLES"
  printf '"cycle":%s,' "$cycle_index" >>"$TMP_CYCLES"
  printf '"started_at":"%s",' "$(json_escape "$started_at")" >>"$TMP_CYCLES"
  printf '"completed":%s,' "$completed" >>"$TMP_CYCLES"
  printf '"reconnect_ms":%s,' "$reconnect_ms" >>"$TMP_CYCLES"
  printf '"handshake_age_seconds":%s,' "$handshake_age" >>"$TMP_CYCLES"
  printf '"route_consistent":%s,' "$route_ok" >>"$TMP_CYCLES"
  printf '"cleanup_clean":%s,' "$cleanup_ok" >>"$TMP_CYCLES"
  printf '"ping_ok":%s,' "$ping_ok" >>"$TMP_CYCLES"
  printf '"public_ip":"%s",' "$(json_escape "$public_ip")" >>"$TMP_CYCLES"
  printf '"failure_category":"%s",' "$(json_escape "$failure_category")" >>"$TMP_CYCLES"
  printf '"failure_detail":"%s"' "$(json_escape "$failure_detail")" >>"$TMP_CYCLES"
  printf '}\n' >>"$TMP_CYCLES"
}

require_root
ensure_prereqs
mkdir -p "$LOG_DIR"

STARTED_AT="$(timestamp_utc)"
END_AT_MS=$(( $(date +%s) + (DURATION_MINUTES * 60) ))
TOTAL_CYCLES=0
SUCCESS_CYCLES=0
SUM_RECONNECT_MS=0
CONNECT_FAILURES=0
HANDSHAKE_FAILURES=0
ROUTE_FAILURES=0
CLEANUP_FAILURES=0
TRAFFIC_FAILURES=0

while (( $(date +%s) < END_AT_MS )); do
  TOTAL_CYCLES=$((TOTAL_CYCLES + 1))
  cycle_started_at="$(timestamp_utc)"
  HEALTHY_HANDSHAKE_AGE=-1
  HEALTHY_RECONNECT_MS=-1
  public_ip=""
  ping_ok=false
  route_ok=false
  cleanup_ok=false
  failure_category=""
  failure_detail=""
  cycle_completed=false

  wg-quick down "$CONFIG_PATH" >/dev/null 2>&1 || true
  clear_policy_state 1

  if ! wg-quick up "$CONFIG_PATH" >/dev/null 2>&1; then
    CONNECT_FAILURES=$((CONNECT_FAILURES + 1))
    failure_category="connect_failed"
    failure_detail="wg-quick up failed"
    append_cycle "$TOTAL_CYCLES" "$cycle_started_at" "$cycle_completed" -1 -1 false false false "$public_ip" "$failure_category" "$failure_detail"
    sleep "$CYCLE_SECONDS"
    continue
  fi

  apply_policy_routing
  start_watchdog

  if ! wait_for_healthy; then
    if ! route_consistent; then
      ROUTE_FAILURES=$((ROUTE_FAILURES + 1))
      failure_category="route_inconsistent"
      failure_detail="policy routing never stabilized"
    else
      HANDSHAKE_FAILURES=$((HANDSHAKE_FAILURES + 1))
      failure_category="handshake_stale"
      failure_detail="handshake did not become fresh within timeout"
    fi
    stop_watchdog
    wg-quick down "$CONFIG_PATH" >/dev/null 2>&1 || true
    clear_policy_state 1
    append_cycle "$TOTAL_CYCLES" "$cycle_started_at" "$cycle_completed" "$HEALTHY_RECONNECT_MS" "$HEALTHY_HANDSHAKE_AGE" false false false "$public_ip" "$failure_category" "$failure_detail"
    sleep "$CYCLE_SECONDS"
    continue
  fi

  route_ok=true
  sleep "$IDLE_SECONDS"

  if ping -c 3 "$PING_TARGET" >/dev/null 2>&1; then
    ping_ok=true
  else
    TRAFFIC_FAILURES=$((TRAFFIC_FAILURES + 1))
    failure_category="${failure_category:-traffic_probe_failed}"
    failure_detail="${failure_detail:-ping failed}"
  fi

  public_ip="$(curl -fsS --max-time 8 "$IFCONFIG_URL" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | sed 's/[[:space:]]\+$//')" || true
  if [[ -z "$public_ip" ]]; then
    TRAFFIC_FAILURES=$((TRAFFIC_FAILURES + 1))
    if [[ -z "$failure_category" ]]; then
      failure_category="traffic_probe_failed"
      failure_detail="curl ifconfig.me failed"
    fi
  fi

  stop_watchdog
  wg-quick down "$CONFIG_PATH" >/dev/null 2>&1 || true
  clear_policy_state 1
  if cleanup_clean; then
    cleanup_ok=true
  else
    CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
    failure_category="${failure_category:-cleanup_residue}"
    failure_detail="${failure_detail:-policy routing residue remained after disconnect}"
  fi

  if [[ -z "$failure_category" ]]; then
    cycle_completed=true
    SUCCESS_CYCLES=$((SUCCESS_CYCLES + 1))
    SUM_RECONNECT_MS=$((SUM_RECONNECT_MS + HEALTHY_RECONNECT_MS))
  fi

  append_cycle "$TOTAL_CYCLES" "$cycle_started_at" "$cycle_completed" "$HEALTHY_RECONNECT_MS" "$HEALTHY_HANDSHAKE_AGE" "$route_ok" "$cleanup_ok" "$ping_ok" "$public_ip" "$failure_category" "$failure_detail"

  sleep "$CYCLE_SECONDS"
done

ENDED_AT="$(timestamp_utc)"
AVG_RECONNECT_MS=0
SUCCESS_RATE=0
if (( SUCCESS_CYCLES > 0 )); then
  AVG_RECONNECT_MS=$((SUM_RECONNECT_MS / SUCCESS_CYCLES))
fi
if (( TOTAL_CYCLES > 0 )); then
  SUCCESS_RATE=$(awk -v ok="$SUCCESS_CYCLES" -v total="$TOTAL_CYCLES" 'BEGIN { printf "%.4f", ok / total }')
fi

cycles_json="[]"
if [[ -s "$TMP_CYCLES" ]]; then
  cycles_json="[$(paste -sd, "$TMP_CYCLES")]"
fi

cat >"$LOG_FILE" <<JSON
{
  "started_at": "$STARTED_AT",
  "ended_at": "$ENDED_AT",
  "interface": "$IFACE",
  "config_path": "$(json_escape "$CONFIG_PATH")",
  "cycles_completed": $TOTAL_CYCLES,
  "successful_cycles": $SUCCESS_CYCLES,
  "success_rate": $SUCCESS_RATE,
  "avg_reconnect_ms": $AVG_RECONNECT_MS,
  "failure_categories": {
    "connect_failed": $CONNECT_FAILURES,
    "handshake_stale": $HANDSHAKE_FAILURES,
    "route_inconsistent": $ROUTE_FAILURES,
    "cleanup_residue": $CLEANUP_FAILURES,
    "traffic_probe_failed": $TRAFFIC_FAILURES
  },
  "cycles": $cycles_json
}
JSON
