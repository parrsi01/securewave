#!/usr/bin/env bash
set -euo pipefail

MAX_ITERS="${MAX_ITERS:-4}"
REPO="${REPO:-/home/sp/cyber-course/projects/securewave}"
VPS_HOST="${VPS_HOST:-138.199.204.139}"
OUT_DIR="${1:-${OUT_DIR:-$REPO/tools/egress_proof/out/$(date -u +%Y%m%d_%H%M%S)}}"
EVID_DIR="$OUT_DIR/EVIDENCE"
PATCH_DIR="$OUT_DIR/PATCHES"
REPORT_DIR="$OUT_DIR/REPORTS"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8)
SCP_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=8)
SSH_CMD_TIMEOUT="${SSH_CMD_TIMEOUT:-240}"

mkdir -p "$EVID_DIR" "$PATCH_DIR" "$REPORT_DIR"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

majority_vote_stream() {
  awk 'NF {count[$1]++} END {best="";bestc=0; for (ip in count) if (count[ip] > bestc) {best=ip; bestc=count[ip]} if (best != "") print best, bestc; }'
}

collect_local_baseline_ip() {
  local f="$EVID_DIR/baseline_public_ip_raw.txt"
  : > "$f"
  for ep in https://ifconfig.me https://api.ipify.org https://ifconfig.co/ip; do
    local ip
    ip="$(curl -4fsS --max-time 6 "$ep" 2>/dev/null | tr -d '\n\r' || true)"
    printf '%s\t%s\n' "$ep" "$ip" >> "$f"
  done
  awk -F'\t' '{print $2}' "$f" | sed '/^$/d' | majority_vote_stream | awk '{print $1}'
}

remote_cmd() {
  timeout "${SSH_CMD_TIMEOUT}s" ssh "${SSH_OPTS[@]}" root@"$VPS_HOST" "$@"
}

capture_remote_file() {
  local path="$1"
  local out="$2"
  remote_cmd "test -f '$path' && cat '$path' || true" > "$out"
}

ensure_remote_reachable() {
  remote_cmd "echo REMOTE_OK $(hostname)"
}

apply_openvpn_fix() {
  local iter="$1"
  local reason="$2"
  local before="$PATCH_DIR/openvpn_server_before_iter${iter}.conf"
  local after="$PATCH_DIR/openvpn_server_after_iter${iter}.conf"
  capture_remote_file "/etc/openvpn/server/server.conf" "$before"

  remote_cmd "bash -s" <<'REMOTE'
set -euo pipefail
TS="$(date -u +%Y%m%d_%H%M%S)"
BACKUP_DIR="/root/securewave-egress-backups/openvpn-${TS}"
mkdir -p "$BACKUP_DIR"
cp -a /etc/openvpn/server/server.conf "$BACKUP_DIR/server.conf.bak"

add_line_if_missing() {
  local line="$1"
  grep -Fqx "$line" /etc/openvpn/server/server.conf || echo "$line" >> /etc/openvpn/server/server.conf
}

add_line_if_missing 'push "redirect-gateway def1 bypass-dhcp"'
add_line_if_missing 'push "dhcp-option DNS 1.1.1.1"'
add_line_if_missing 'push "dhcp-option DNS 8.8.8.8"'

sysctl -w net.ipv4.ip_forward=1 >/dev/null
OUT_IF="$(ip -4 route show default | awk '{print $5; exit}')"
[ -n "$OUT_IF" ] || OUT_IF="eth0"
iptables -t nat -C POSTROUTING -s 10.9.0.0/24 -o "$OUT_IF" -j MASQUERADE >/dev/null 2>&1 || \
  iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o "$OUT_IF" -j MASQUERADE

systemctl restart openvpn-server@server || systemctl restart openvpn@server
if ! systemctl is-active --quiet openvpn-server@server && ! systemctl is-active --quiet openvpn@server; then
  cp -a "$BACKUP_DIR/server.conf.bak" /etc/openvpn/server/server.conf
  systemctl restart openvpn-server@server || systemctl restart openvpn@server || true
  echo "ROLLED_BACK=1"
else
  echo "ROLLED_BACK=0"
fi

echo "BACKUP_DIR=$BACKUP_DIR"
REMOTE

  capture_remote_file "/etc/openvpn/server/server.conf" "$after"
  diff -u "$before" "$after" > "$PATCH_DIR/openvpn_iter${iter}.diff" || true
}

apply_ikev2_fix() {
  local iter="$1"
  local reason="$2"
  local before="$PATCH_DIR/ipsec_before_iter${iter}.conf"
  local after="$PATCH_DIR/ipsec_after_iter${iter}.conf"
  capture_remote_file "/etc/ipsec.conf" "$before"

  remote_cmd "bash -s" <<'REMOTE'
set -euo pipefail
TS="$(date -u +%Y%m%d_%H%M%S)"
BACKUP_DIR="/root/securewave-egress-backups/ikev2-${TS}"
mkdir -p "$BACKUP_DIR"
cp -a /etc/ipsec.conf "$BACKUP_DIR/ipsec.conf.bak"

if ! grep -q '^  leftsubnet=0.0.0.0/0' /etc/ipsec.conf; then
  awk '
    /^conn securewave-ikev2-eap$/ {print; in_conn=1; next}
    in_conn && /^  leftid=/ {print "  leftsubnet=0.0.0.0/0"; print; in_conn=0; next}
    {print}
  ' /etc/ipsec.conf > /etc/ipsec.conf.tmp && mv /etc/ipsec.conf.tmp /etc/ipsec.conf
fi

grep -q '^  rightsourceip=' /etc/ipsec.conf || echo '  rightsourceip=10.10.0.10-10.10.0.250' >> /etc/ipsec.conf

test -f /etc/sysctl.d/100-securewave-vpn-override.conf || cat >/etc/sysctl.d/100-securewave-vpn-override.conf <<CONF
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
CONF
sysctl -p /etc/sysctl.d/100-securewave-vpn-override.conf >/dev/null || true

OUT_IF="$(ip -4 route show default | awk '{print $5; exit}')"
[ -n "$OUT_IF" ] || OUT_IF="eth0"
iptables -C FORWARD -m policy --pol ipsec --dir in -j ACCEPT >/dev/null 2>&1 || iptables -A FORWARD -m policy --pol ipsec --dir in -j ACCEPT
iptables -C FORWARD -m policy --pol ipsec --dir out -j ACCEPT >/dev/null 2>&1 || iptables -A FORWARD -m policy --pol ipsec --dir out -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.10.0.0/24 -o "$OUT_IF" -j MASQUERADE >/dev/null 2>&1 || iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o "$OUT_IF" -j MASQUERADE

systemctl restart strongswan || systemctl restart strongswan-starter
if ! systemctl is-active --quiet strongswan && ! systemctl is-active --quiet strongswan-starter; then
  cp -a "$BACKUP_DIR/ipsec.conf.bak" /etc/ipsec.conf
  systemctl restart strongswan || systemctl restart strongswan-starter || true
  echo "ROLLED_BACK=1"
else
  echo "ROLLED_BACK=0"
fi

echo "BACKUP_DIR=$BACKUP_DIR"
REMOTE

  capture_remote_file "/etc/ipsec.conf" "$after"
  diff -u "$before" "$after" > "$PATCH_DIR/ikev2_iter${iter}.diff" || true
}

run_remote_egress_check() {
  local proto="$1"
  local iter="$2"
  local baseline_ip="$3"
  local remote_dir="/tmp/sw-egress-${proto}-iter${iter}-$$"
  local local_dir="$EVID_DIR/${proto}_iter${iter}"
  mkdir -p "$local_dir"

  remote_cmd "mkdir -p '$remote_dir'"
  timeout "${SSH_CMD_TIMEOUT}s" scp "${SCP_OPTS[@]}" "$REPO/tools/egress_proof/egress_check.sh" root@"$VPS_HOST":"$remote_dir/egress_check.sh" >/dev/null

  if ! remote_cmd "chmod +x '$remote_dir/egress_check.sh' && BASELINE_PUBLIC_IP='$baseline_ip' OPENVPN_SELFTEST_AUTO=1 IKEV2_SELFTEST_AUTO=1 '$remote_dir/egress_check.sh' '$proto' '$remote_dir'"; then
    echo "CHECK_EXEC_FAILED=1" > "$local_dir/result.env"
  fi

  timeout "${SSH_CMD_TIMEOUT}s" scp "${SCP_OPTS[@]}" root@"$VPS_HOST":"$remote_dir/*" "$local_dir/" >/dev/null || true
  remote_cmd "rm -rf '$remote_dir'" || true
}

write_matrix() {
  local matrix="$OUT_DIR/final_matrix.md"
  {
    echo "| Protocol | Negotiation | Egress Proof | PASS/FAIL | Reason |"
    echo "|---|---|---|---|---|"
    for p in openvpn ikev2; do
      local rf="$EVID_DIR/${p}_final_result.env"
      if [[ -f "$rf" ]]; then
        # shellcheck disable=SC1090
        source "$rf"
        echo "| $p | ${NEGOTIATION:-unknown} | ${EGRESS_PROOF:-unknown} | ${FINAL_VERDICT:-FAIL} | ${FINAL_REASON:-unknown} |"
      else
        echo "| $p | unknown | unknown | FAIL | missing_result |"
      fi
    done
  } > "$matrix"
}

main() {
  ensure_remote_reachable >/dev/null

  local baseline_ip
  baseline_ip="$(collect_local_baseline_ip || true)"
  printf '%s\n' "$baseline_ip" > "$EVID_DIR/baseline_public_ip.txt"
  log "baseline_public_ip=$baseline_ip"

  local proto
  for proto in openvpn ikev2; do
    local verdict="FAIL"
    local reason="max_iters_reached"
    local negotiation="false"
    local egress="false"

    local iter
    for iter in $(seq 1 "$MAX_ITERS"); do
      log "protocol=$proto iter=$iter running_check"
      run_remote_egress_check "$proto" "$iter" "$baseline_ip"

      local rf="$EVID_DIR/${proto}_iter${iter}/result.env"
      if [[ -f "$rf" ]]; then
        # shellcheck disable=SC1090
        source "$rf"
      else
        VERDICT="FAIL"
        REASON_CODE="check_output_missing"
        TUNNEL_UP="false"
        ROUTE_VPN="false"
        TCPDUMP_VPN="false"
      fi

      negotiation="$TUNNEL_UP"
      if [[ "$ROUTE_VPN" == "true" || "$TCPDUMP_VPN" == "true" ]]; then
        egress="true"
      else
        egress="false"
      fi

      if [[ "$VERDICT" == "PASS" ]]; then
        verdict="PASS"
        reason="ok"
        log "protocol=$proto iter=$iter PASS"
        break
      fi

      reason="$REASON_CODE"
      log "protocol=$proto iter=$iter FAIL reason=$reason"

      if [[ "$iter" -ge "$MAX_ITERS" ]]; then
        break
      fi

      log "protocol=$proto iter=$iter applying_fix"
      if [[ "$proto" == "openvpn" ]]; then
        apply_openvpn_fix "$iter" "$reason" > "$EVID_DIR/${proto}_iter${iter}/fix.log" 2>&1 || true
      else
        apply_ikev2_fix "$iter" "$reason" > "$EVID_DIR/${proto}_iter${iter}/fix.log" 2>&1 || true
      fi

      if ! ensure_remote_reachable >/dev/null; then
        log "protocol=$proto connectivity_regression rollback_required"
        verdict="FAIL"
        reason="connectivity_regression"
        break
      fi
    done

    {
      echo "FINAL_VERDICT=$verdict"
      echo "FINAL_REASON=$reason"
      echo "NEGOTIATION=$negotiation"
      echo "EGRESS_PROOF=$egress"
    } > "$EVID_DIR/${proto}_final_result.env"
  done

  write_matrix

  local rep="$REPORT_DIR/egress_proof_runner_summary.md"
  {
    echo "# Egress Proof Runner Summary"
    echo
    echo "- VPS host: $VPS_HOST"
    echo "- Baseline public IP: $(cat "$EVID_DIR/baseline_public_ip.txt" 2>/dev/null || true)"
    echo "- Max iterations: $MAX_ITERS"
    echo "- Matrix: $OUT_DIR/final_matrix.md"
    echo
    cat "$OUT_DIR/final_matrix.md"
  } > "$rep"

  log "completed out_dir=$OUT_DIR"
}

main "$@"
