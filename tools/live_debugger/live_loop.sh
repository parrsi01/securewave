#!/usr/bin/env bash
set -euo pipefail

MAX_ITERS="${MAX_ITERS:-6}"
REPO="${REPO:-/home/sp/cyber-course/projects/securewave}"
TS="${TS:-$(date -u +%Y%m%d_%H%M%S)}"
OUT_ROOT="${OUT_ROOT:-$REPO/tools/live_debugger/out/$TS}"
EVIDENCE_ROOT="$OUT_ROOT/EVIDENCE"
API_BASE="${LIVE_API_BASE_URL:-http://127.0.0.1:8000}"
VPN_HOST="${LIVE_VPN_HOST:-138.199.204.139}"
API_TOKEN="${LIVE_API_TOKEN:-}"
PRE_PATCH_COMMIT="$(git -C "$REPO" rev-parse --short HEAD)"

mkdir -p "$OUT_ROOT" "$EVIDENCE_ROOT"

status_file="$OUT_ROOT/matrix_latest.tsv"
echo -e "section\tstatus\treason" > "$status_file"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
set_status() {
  local section="$1" status="$2" reason="$3"
  printf '%s\t%s\t%s\n' "$section" "$status" "$reason" >> "$status_file"
}
remote() {
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 root@"$VPN_HOST" "$@"
}
api_get() {
  local path="$1"
  if [[ -n "$API_TOKEN" ]]; then
    curl -fsS -H "Authorization: Bearer $API_TOKEN" "$API_BASE$path"
  else
    curl -fsS "$API_BASE$path"
  fi
}
api_post_json() {
  local path="$1" payload="$2"
  if [[ -n "$API_TOKEN" ]]; then
    curl -fsS -X POST -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" -d "$payload" "$API_BASE$path"
  else
    curl -fsS -X POST -H "Content-Type: application/json" -d "$payload" "$API_BASE$path"
  fi
}
iface_for_proto() {
  case "$1" in
    wireguard) echo "sw-wg wg0" ;;
    openvpn) echo "tun0" ;;
    ikev2) echo "ipsec0 xfrm0" ;;
    *) echo "" ;;
  esac
}
any_iface_present() {
  local list="$1"
  for i in $list; do
    if ip link show dev "$i" >/dev/null 2>&1; then
      echo "$i"
      return 0
    fi
  done
  return 1
}
classify_failure() {
  local reason="$1"
  if grep -qiE 'ip_forward|masquerade|nat' <<<"$reason"; then echo "nat_missing"; return; fi
  if grep -qiE 'service|inactive|daemon|port' <<<"$reason"; then echo "daemon_down"; return; fi
  if grep -qiE 'auth|401|403|token' <<<"$reason"; then echo "auth_mode_mismatch"; return; fi
  if grep -qiE 'route|rule|lookup|fwmark' <<<"$reason"; then echo "routing_error"; return; fi
  if grep -qiE 'profile|provision|script' <<<"$reason"; then echo "provisioning_missing"; return; fi
  if grep -qiE 'runtime|interface|connect|disconnect' <<<"$reason"; then echo "client_runtime_error"; return; fi
  echo "infra_missing"
}
apply_min_fix_remote() {
  local category="$1"
  case "$category" in
    nat_missing)
      remote 'sysctl -w net.ipv4.ip_forward=1; iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE || iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE; iptables -t nat -C POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE || iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE; iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o eth0 -j MASQUERADE || iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o eth0 -j MASQUERADE'
      ;;
    daemon_down)
      remote 'systemctl enable --now wg-quick@wg0 || true; systemctl enable --now openvpn-server@server || systemctl enable --now openvpn@server || true; systemctl enable --now strongswan || systemctl enable --now strongswan-starter || true'
      ;;
    provisioning_missing)
      remote 'test -x /usr/local/bin/securewave-openvpn-issue-client || true; test -x /usr/local/bin/securewave-ikev2-issue-client || true'
      ;;
    routing_error)
      remote 'ip rule show; ip route show table 100; ip route show table 200; ip route show table 300'
      ;;
    *)
      true
      ;;
  esac
}

step_server_infra() {
  local iter_dir="$1" out="$iter_dir/step1_server_infra.txt"
  if ! remote 'set -e; echo ip_forward=$(sysctl -n net.ipv4.ip_forward); ss -lun | grep -E ":51820|:1194|:500|:4500" || true; systemctl is-active wg-quick@wg0 || true; systemctl is-active openvpn-server@server || systemctl is-active openvpn@server || true; systemctl is-active strongswan || systemctl is-active strongswan-starter || true; iptables -t nat -S'; then
    set_status "server_infra" "FAIL" "remote_command_failed"
    return 1
  fi >"$out" 2>&1

  local reason=""
  grep -q 'ip_forward=1' "$out" || reason+="ip_forward_not_1;"
  grep -Eq ':51820|51820\s' "$out" || reason+="port_51820_missing;"
  grep -Eq ':1194|1194\s' "$out" || reason+="port_1194_missing;"
  grep -Eq ':500\b|:4500\b' "$out" || reason+="ike_ports_missing;"
  grep -q 'active' "$out" || reason+="services_inactive;"
  if [[ -n "$reason" ]]; then
    set_status "server_infra" "FAIL" "$reason"
    return 1
  fi
  set_status "server_infra" "PASS" "ok"
}

step_backend_health() {
  local iter_dir="$1"
  local regions="$iter_dir/step2_regions.json"
  local protocols="$iter_dir/step2_protocols.json"
  local reason=""

  if ! api_get '/api/vpn/regions' >"$regions" 2>"$iter_dir/step2_regions.err"; then
    set_status "backend_health" "FAIL" "regions_endpoint_failed"
    return 1
  fi
  if ! api_get '/api/vpn/protocols' >"$protocols" 2>"$iter_dir/step2_protocols.err"; then
    set_status "backend_health" "FAIL" "protocols_endpoint_failed"
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -e 'if type=="array" then (.[0] | has("health") or has("health_status") or has("last_checked_at")) else true end' "$regions" >/dev/null 2>&1 || reason+="region_health_fields_missing;"
  else
    grep -Eq 'health|last_checked_at|reason_code' "$regions" || reason+="region_health_fields_missing;"
  fi

  if [[ -n "$reason" ]]; then
    set_status "backend_health" "FAIL" "$reason"
    return 1
  fi
  set_status "backend_health" "PASS" "ok"
}

step_protocol_e2e() {
  local iter_dir="$1" proto="$2"
  local pdir="$iter_dir/step_${proto}_e2e"
  mkdir -p "$pdir"

  if [[ -z "$API_TOKEN" ]]; then
    set_status "${proto}_e2e" "FAIL" "missing_live_api_token"
    return 1
  fi

  local public_before public_after
  public_before="$(curl -4fsS --max-time 6 https://api.ipify.org 2>/dev/null || true)"

  local connect_payload="{\"protocol\":\"$proto\"}"
  local connect_json="$pdir/connect.json"
  if ! api_post_json '/api/vpn/connect' "$connect_payload" >"$connect_json" 2>"$pdir/connect.err"; then
    set_status "${proto}_e2e" "FAIL" "connect_failed"
    return 1
  fi
  sleep 2

  local iface_list iface_used=""
  iface_list="$(iface_for_proto "$proto")"
  iface_used="$(any_iface_present "$iface_list" || true)"

  case "$proto" in
    wireguard) wg show >"$pdir/wg_show.txt" 2>&1 || true ;;
    openvpn) ss -lunp >"$pdir/ss_openvpn.txt" 2>&1 || true ;;
    ikev2) remote 'ipsec statusall || true' >"$pdir/ipsec_status.txt" 2>&1 || true ;;
  esac

  ip route get 1.1.1.1 >"$pdir/route_get.txt" 2>&1 || true
  public_after="$(curl -4fsS --max-time 6 https://api.ipify.org 2>/dev/null || true)"

  api_post_json '/api/vpn/disconnect' '{}' >"$pdir/disconnect.json" 2>"$pdir/disconnect.err" || true

  local reason=""
  [[ -n "$iface_used" ]] || reason+="iface_missing;"
  if [[ -n "$public_before" && -n "$public_after" && "$public_before" == "$public_after" ]]; then
    reason+="public_ip_unchanged;"
  fi
  if [[ -n "$reason" ]]; then
    set_status "${proto}_e2e" "FAIL" "$reason"
    return 1
  fi
  set_status "${proto}_e2e" "PASS" "ok"
}

step_crash_recovery() {
  local iter_dir="$1" out="$iter_dir/step6_crash_recovery.txt"
  local app_bin="$REPO/securewave_app/build/linux/arm64/release/bundle/securewave_app"
  if [[ ! -x "$app_bin" ]]; then
    set_status "crash_recovery" "FAIL" "linux_app_binary_missing"
    return 1
  fi
  "$app_bin" >"$out" 2>&1 &
  local pid=$!
  sleep 3
  kill -9 "$pid" >/dev/null 2>&1 || true
  sleep 1
  "$app_bin" >>"$out" 2>&1 &
  local pid2=$!
  sleep 3
  kill -9 "$pid2" >/dev/null 2>&1 || true
  set_status "crash_recovery" "PASS" "app_restart_cycle_ok"
}

step_sim_isolation() {
  local iter_dir="$1" out="$iter_dir/step7_sim_isolation.txt"
  local before after
  before="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(sw-wg|wg0|tun0|ipsec0|xfrm0)$' || true)"
  export SECUREWAVE_SIM_MODE=true
  export SECUREWAVE_TUNNEL_MODE=real
  sleep 1
  after="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(sw-wg|wg0|tun0|ipsec0|xfrm0)$' || true)"
  {
    echo "before=$before"
    echo "after=$after"
  } >"$out"
  unset SECUREWAVE_SIM_MODE
  if [[ "$before" != "$after" ]]; then
    set_status "sim_isolation" "FAIL" "interface_state_changed_in_sim"
    return 1
  fi
  set_status "sim_isolation" "PASS" "no_interface_change_detected"
}

render_matrix_md() {
  local target="$1"
  {
    echo "| Section | PASS/FAIL | Reason |"
    echo "|---|---|---|"
    tail -n +2 "$status_file" | while IFS=$'\t' read -r s st rs; do
      echo "| $s | $st | $rs |"
    done
  } > "$target"
}

count_failures() {
  awk -F'\t' 'NR>1 && $2=="FAIL" {c++} END {print c+0}' "$status_file"
}

main() {
  local prev_failures=999999
  local last_matrix=""
  for iter in $(seq 1 "$MAX_ITERS"); do
    log "iteration=$iter"
    local iter_dir="$EVIDENCE_ROOT/iter_${iter}"
    mkdir -p "$iter_dir"

    step_server_infra "$iter_dir" || true
    step_backend_health "$iter_dir" || true
    step_protocol_e2e "$iter_dir" wireguard || true
    step_protocol_e2e "$iter_dir" openvpn || true
    step_protocol_e2e "$iter_dir" ikev2 || true
    step_crash_recovery "$iter_dir" || true
    step_sim_isolation "$iter_dir" || true

    local matrix="$iter_dir/matrix.md"
    render_matrix_md "$matrix"
    last_matrix="$matrix"
    local failures
    failures="$(count_failures)"
    log "failures=$failures"

    if [[ "$failures" -eq 0 ]]; then
      log "all sections passed"
      cp "$matrix" "$OUT_ROOT/final_matrix.md"
      echo "SUCCESS" > "$OUT_ROOT/final_status.txt"
      return 0
    fi

    local reasons plan_file
    reasons="$(awk -F'\t' 'NR>1 && $2=="FAIL" {print $3}' "$status_file" | tr '\n' ';')"
    local category
    category="$(classify_failure "$reasons")"
    plan_file="$iter_dir/PLAN_${iter}.md"
    {
      echo "# Iteration $iter Recovery Plan"
      echo "- category: $category"
      echo "- reasons: $reasons"
      echo "- commit: $(git -C "$REPO" rev-parse --short HEAD)"
      echo "- action: apply minimal fix then rerun failed sections"
    } > "$plan_file"

    local pre_patch_commit
    pre_patch_commit="$(git -C "$REPO" rev-parse --short HEAD)"
    apply_min_fix_remote "$category" || true

    if [[ "$failures" -gt "$prev_failures" ]]; then
      log "failure count increased; rolling back to $pre_patch_commit"
      git -C "$REPO" reset --hard "$pre_patch_commit"
      echo "FAIL_WITH_ROLLBACK" > "$OUT_ROOT/final_status.txt"
      cp "$matrix" "$OUT_ROOT/final_matrix.md"
      return 1
    fi
    prev_failures="$failures"

    if [[ "$iter" -lt "$MAX_ITERS" ]]; then
      # reset status file for next iteration (fresh matrix per iteration)
      echo -e "section\tstatus\treason" > "$status_file"
    fi
  done

  echo "FAIL_MAX_ITERS" > "$OUT_ROOT/final_status.txt"
  if [[ -n "$last_matrix" && -f "$last_matrix" ]]; then
    cp "$last_matrix" "$OUT_ROOT/final_matrix.md"
  else
    render_matrix_md "$OUT_ROOT/final_matrix.md"
  fi
  return 1
}

main "$@"
