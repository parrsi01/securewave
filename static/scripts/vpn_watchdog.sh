#!/usr/bin/env bash
set -euo pipefail

IFACE="${1:-sw-wg}"
CONFIG_PATH="${2:-$HOME/.config/securewave/sw-wg.conf}"
TABLE_ID="${TABLE_ID:-51820}"
FWMARK="${FWMARK:-51820}"
POLICY_PRIORITY="${POLICY_PRIORITY:-32764}"
SUPPRESS_PRIORITY="${SUPPRESS_PRIORITY:-32765}"
HANDSHAKE_MAX_AGE="${HANDSHAKE_MAX_AGE:-30}"
POLL_SECONDS="${POLL_SECONDS:-3}"
PING_TARGET="${PING_TARGET:-1.1.1.1}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR%/scripts}/logs"
LOG_FILE="${LOG_DIR}/vpn_health.json"
DEBUG_LOG_FILE="${LOG_DIR}/vpn_watchdog_debug.jsonl"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0 ${IFACE@Q} ${CONFIG_PATH@Q}" >&2
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_prereqs() {
  local missing=0
  for bin in ip wg wg-quick nmcli date awk grep; do
    if ! command_exists "$bin"; then
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

interface_exists() {
  ip link show "$IFACE" >/dev/null 2>&1
}

networkmanager_isolated() {
  nmcli -t -f DEVICE,STATE device status 2>/dev/null |
    grep -q "^${IFACE}:unmanaged$"
}

apply_nm_isolation() {
  nmcli device set "$IFACE" managed no >/dev/null 2>&1 || true
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

route_valid() {
  local policy_count suppress_count
  policy_count="$(policy_rule_count)"
  suppress_count="$(main_suppress_count)"
  (( policy_count == 1 )) && (( suppress_count == 1 )) && table_route_present
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
  local latest epoch now
  latest="$(
    wg show "$IFACE" latest-handshakes 2>/dev/null |
      awk 'BEGIN { latest = 0 } { if ($2 > latest) latest = $2 } END { print latest }'
  )"
  [[ -n "$latest" && "$latest" != "0" ]] || return 1
  now="$(date +%s)"
  epoch=$(( now - latest ))
  if (( epoch < 0 )); then
    epoch=0
  fi
  printf '%s\n' "$epoch"
}

data_path_reachable() {
  ping -I "$IFACE" -c 1 -W 2 "$PING_TARGET" >/dev/null 2>&1
}

write_health() {
  local action="$1"
  local status="$2"
  local iface_present="$3"
  local nm_isolated="$4"
  local fwmark_ok="$5"
  local routing_ok="$6"
  local handshake_age="$7"
  local handshake_ok="$8"
  local current_downtime_ms="$9"
  mkdir -p "$LOG_DIR"
  cat >"$LOG_FILE" <<JSON
{
  "timestamp": "$(timestamp_utc)",
  "interface": "${IFACE}",
  "status": "${status}",
  "action": "${action}",
  "networkmanager_unmanaged": ${nm_isolated},
  "interface_present": ${iface_present},
  "fwmark_configured": ${fwmark_ok},
  "policy_routing_present": ${routing_ok},
  "handshake_age_seconds": ${handshake_age},
  "handshake_recent": ${handshake_ok},
  "reconnect_attempts": ${RECONNECT_ATTEMPTS},
  "route_resets": ${ROUTE_RESETS},
  "critical_resets": ${CRITICAL_RESETS},
  "last_downtime_ms": ${LAST_DOWNTIME_MS},
  "current_downtime_ms": ${current_downtime_ms},
  "total_downtime_ms": ${TOTAL_DOWNTIME_MS}
}
JSON
}

append_debug_event() {
  local action="$1"
  local status="$2"
  local iface_present="$3"
  local nm_isolated="$4"
  local fwmark_ok="$5"
  local routing_ok="$6"
  local handshake_age="$7"
  local handshake_ok="$8"
  local event_key="${status}|${action}|${iface_present}|${nm_isolated}|${fwmark_ok}|${routing_ok}|${handshake_ok}"

  if [[ "$event_key" == "$LAST_EVENT_KEY" && "$status" == "healthy" ]]; then
    return
  fi

  LAST_EVENT_KEY="$event_key"
  mkdir -p "$LOG_DIR"
  printf '%s\n' \
    "{\"timestamp\":\"$(timestamp_utc)\",\"status\":\"${status}\",\"action\":\"${action}\",\"interface_present\":${iface_present},\"networkmanager_unmanaged\":${nm_isolated},\"fwmark_configured\":${fwmark_ok},\"policy_routing_present\":${routing_ok},\"handshake_age_seconds\":${handshake_age},\"handshake_recent\":${handshake_ok}}" \
    >>"$DEBUG_LOG_FILE"
}

restart_tunnel() {
  RECONNECT_ATTEMPTS=$((RECONNECT_ATTEMPTS + 1))
  wg-quick down "$CONFIG_PATH" >/dev/null 2>&1 || true
  clear_policy_state 1
  wg-quick up "$CONFIG_PATH"
  apply_nm_isolation
  apply_policy_routing
}

critical_repair() {
  CRITICAL_RESETS=$((CRITICAL_RESETS + 1))
  systemctl restart NetworkManager >/dev/null 2>&1 ||
    nmcli general reload >/dev/null 2>&1 ||
    true
  apply_nm_isolation
  restart_tunnel
}

require_root
ensure_prereqs

ROUTE_RESETS=0
RECONNECT_ATTEMPTS=0
CRITICAL_RESETS=0
TOTAL_DOWNTIME_MS=0
LAST_DOWNTIME_MS=0
DOWNTIME_STARTED_AT=0
CONSECUTIVE_HARD_FAILURES=0
LAST_EVENT_KEY=""

while true; do
  iface_present=false
  nm_isolated=false
  fwmark_ok=false
  routing_ok=false
  handshake_ok=false
  probe_ok=false
  handshake_age=-1
  status="recovering"
  action="observe"

  if interface_exists; then
    iface_present=true
    if networkmanager_isolated; then
      nm_isolated=true
    fi
    if fwmark_valid; then
      fwmark_ok=true
    fi
    if route_valid; then
      routing_ok=true
    fi
    if age="$(latest_handshake_age 2>/dev/null)"; then
      handshake_age="$age"
      if (( age < HANDSHAKE_MAX_AGE )); then
        handshake_ok=true
      fi
    fi
    if [[ "$nm_isolated" == true && "$fwmark_ok" == true && "$routing_ok" == true && "$handshake_ok" != true ]]; then
      if data_path_reachable; then
        probe_ok=true
      fi
    fi
  fi

  if [[ "$iface_present" == true && "$nm_isolated" == true && "$fwmark_ok" == true && "$routing_ok" == true && ( "$handshake_ok" == true || "$probe_ok" == true ) ]]; then
    status="healthy"
    action="healthy"
    CONSECUTIVE_HARD_FAILURES=0
    if (( DOWNTIME_STARTED_AT > 0 )); then
      LAST_DOWNTIME_MS=$(( $(now_ms) - DOWNTIME_STARTED_AT ))
      TOTAL_DOWNTIME_MS=$(( TOTAL_DOWNTIME_MS + LAST_DOWNTIME_MS ))
      DOWNTIME_STARTED_AT=0
    fi
    write_health "$action" "$status" "$iface_present" "$nm_isolated" "$fwmark_ok" "$routing_ok" "$handshake_age" "$handshake_ok" 0
    append_debug_event "$action" "$status" "$iface_present" "$nm_isolated" "$fwmark_ok" "$routing_ok" "$handshake_age" "$handshake_ok"
    sleep "$POLL_SECONDS"
    continue
  fi

  if (( DOWNTIME_STARTED_AT == 0 )); then
    DOWNTIME_STARTED_AT="$(now_ms)"
  fi
  current_downtime_ms=$(( $(now_ms) - DOWNTIME_STARTED_AT ))

  if [[ "$iface_present" == true && ( "$routing_ok" != true || "$fwmark_ok" != true || "$nm_isolated" != true ) ]]; then
    action="reapply_policy_routing"
    apply_nm_isolation
    apply_policy_routing
    ROUTE_RESETS=$((ROUTE_RESETS + 1))
    CONSECUTIVE_HARD_FAILURES=0
  else
    action="restart_tunnel"
    if restart_tunnel; then
      CONSECUTIVE_HARD_FAILURES=0
    else
      CONSECUTIVE_HARD_FAILURES=$((CONSECUTIVE_HARD_FAILURES + 1))
    fi
  fi

  if (( CONSECUTIVE_HARD_FAILURES >= 2 )); then
    action="critical_repair"
    critical_repair || true
    CONSECUTIVE_HARD_FAILURES=0
  fi

  write_health "$action" "$status" "$iface_present" "$nm_isolated" "$fwmark_ok" "$routing_ok" "$handshake_age" "$handshake_ok" "$current_downtime_ms"
  append_debug_event "$action" "$status" "$iface_present" "$nm_isolated" "$fwmark_ok" "$routing_ok" "$handshake_age" "$handshake_ok"
  sleep "$POLL_SECONDS"
done
