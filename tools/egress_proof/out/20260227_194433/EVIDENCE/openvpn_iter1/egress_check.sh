#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <openvpn|ikev2> <out_dir> [baseline_public_ip]" >&2
  exit 2
fi

PROTO="$1"
OUT_DIR="$2"
BASELINE_PUBLIC_IP="${3:-${BASELINE_PUBLIC_IP:-}}"
mkdir -p "$OUT_DIR"

RAW_IPS_FILE="$OUT_DIR/public_ip_raw.txt"
ROUTE_FILE="$OUT_DIR/route_get.txt"
REPORT_FILE="$OUT_DIR/REPORT.md"
RESULT_FILE="$OUT_DIR/result.env"
TCPDUMP_DEF_FILE="$OUT_DIR/tcpdump_default.txt"
TCPDUMP_TUN_FILE="$OUT_DIR/tcpdump_tunnel.txt"
BOUND_FILE="$OUT_DIR/interface_bound_ip.txt"
STATUS_LOG="$OUT_DIR/status.log"

ENDPOINTS=(
  "https://ifconfig.me"
  "https://api.ipify.org"
  "https://ifconfig.co/ip"
)

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$STATUS_LOG" >&2
}

majority_vote() {
  awk 'NF {count[$1]++} END {best="";bestc=0; for (ip in count) { if (count[ip] > bestc) { best=ip; bestc=count[ip]; } } if (best != "") printf "%s %d\n", best, bestc; }' "$1"
}

fetch_ip() {
  local url="$1"
  curl -4fsS --max-time 6 "$url" 2>/dev/null | tr -d '\r' | tr -d '\n' | sed 's/[[:space:]]*$//' || true
}

collect_ips() {
  : > "$RAW_IPS_FILE"
  for ep in "${ENDPOINTS[@]}"; do
    local ip
    ip="$(fetch_ip "$ep")"
    printf '%s\t%s\n' "$ep" "$ip" >> "$RAW_IPS_FILE"
  done
}

require_cmd() {
  local c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      log "missing_command=$c"
      exit 3
    fi
  done
}

cleanup() {
  set +e
  if [[ -n "${OPENVPN_PID:-}" ]]; then
    kill "$OPENVPN_PID" >/dev/null 2>&1 || true
    sleep 1
  fi
  if [[ -n "${OPENVPN_WORK:-}" ]]; then
    [[ -f "$OPENVPN_WORK/client.pid" ]] && kill "$(cat "$OPENVPN_WORK/client.pid")" >/dev/null 2>&1 || true
    [[ -n "${OPENVPN_TUN_IF:-}" ]] && ip link del "$OPENVPN_TUN_IF" >/dev/null 2>&1 || true
    [[ -n "${SSH_CLIENT_IP:-}" && -n "${SSH_DEFAULT_GW:-}" && -n "${DEF_IF:-}" ]] && ip route del "${SSH_CLIENT_IP}/32" via "$SSH_DEFAULT_GW" dev "$DEF_IF" >/dev/null 2>&1 || true
    rm -rf "$OPENVPN_WORK"
  fi
  if [[ -n "${IKEV2_WORK:-}" ]]; then
    touch "$IKEV2_WORK/stop" >/dev/null 2>&1 || true
    [[ -n "${IKEV2_HELPER_PID:-}" ]] && kill "$IKEV2_HELPER_PID" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$IKEV2_WORK"
  fi
  [[ -n "${TCPDUMP_DEF_PID:-}" ]] && kill "$TCPDUMP_DEF_PID" >/dev/null 2>&1 || true
  [[ -n "${TCPDUMP_TUN_PID:-}" ]] && kill "$TCPDUMP_TUN_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

start_openvpn_selftest() {
  OPENVPN_WORK="/tmp/sw-egress-openvpn-$$"
  OPENVPN_TUN_IF="tun-egress-proof"
  mkdir -p "$OPENVPN_WORK"

  local ca_cert ca_key tls_crypt
  ca_cert="/etc/openvpn/server/ca.crt"
  ca_key="/etc/openvpn/pki/ca.key"
  tls_crypt="/etc/openvpn/server/tls-crypt.key"
  if [[ ! -f "$ca_cert" || ! -f "$ca_key" || ! -f "$tls_crypt" ]]; then
    log "openvpn_selftest_missing_material"
    return 1
  fi

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    SSH_CLIENT_IP="$(awk '{print $1}' <<<"$SSH_CONNECTION")"
    SSH_DEFAULT_GW="$(ip route show default | awk '{print $3; exit}')"
    if [[ -n "$SSH_CLIENT_IP" && -n "$SSH_DEFAULT_GW" && -n "${DEF_IF:-}" ]]; then
      ip route replace "${SSH_CLIENT_IP}/32" via "$SSH_DEFAULT_GW" dev "$DEF_IF" || true
      log "openvpn_failsafe_route_added=${SSH_CLIENT_IP}/32"
    fi
  fi

  openssl genrsa -out "$OPENVPN_WORK/client.key" 2048 >/dev/null 2>&1
  openssl req -new -key "$OPENVPN_WORK/client.key" -subj "/CN=sw-egress-client" -out "$OPENVPN_WORK/client.csr" >/dev/null 2>&1
  openssl x509 -req -in "$OPENVPN_WORK/client.csr" -CA "$ca_cert" -CAkey "$ca_key" -CAcreateserial -out "$OPENVPN_WORK/client.crt" -days 2 -sha256 >/dev/null 2>&1

  cat > "$OPENVPN_WORK/client.ovpn" <<CONF
client
dev ${OPENVPN_TUN_IF}
proto udp
remote 127.0.0.1 1194
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
verb 3
redirect-gateway def1
<ca>
$(cat "$ca_cert")
</ca>
<cert>
$(cat "$OPENVPN_WORK/client.crt")
</cert>
<key>
$(cat "$OPENVPN_WORK/client.key")
</key>
<tls-crypt>
$(cat "$tls_crypt")
</tls-crypt>
CONF

  openvpn --config "$OPENVPN_WORK/client.ovpn" --daemon --writepid "$OPENVPN_WORK/client.pid" --log "$OPENVPN_WORK/client.log" || return 1
  OPENVPN_PID="$(cat "$OPENVPN_WORK/client.pid" 2>/dev/null || true)"

  local i
  for i in $(seq 1 20); do
    if grep -q 'Initialization Sequence Completed' "$OPENVPN_WORK/client.log" 2>/dev/null; then
      log "openvpn_selftest_connected"
      return 0
    fi
    sleep 1
  done
  log "openvpn_selftest_failed"
  tail -n 80 "$OPENVPN_WORK/client.log" >> "$STATUS_LOG" 2>/dev/null || true
  return 1
}

start_ikev2_selftest() {
  require_cmd python3
  IKEV2_WORK="/tmp/sw-egress-ikev2-$$"
  mkdir -p "$IKEV2_WORK"

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    SSH_CLIENT_IP="$(awk '{print $1}' <<<"$SSH_CONNECTION")"
    SSH_DEFAULT_GW="$(ip route show default | awk '{print $3; exit}')"
    if [[ -n "$SSH_CLIENT_IP" && -n "$SSH_DEFAULT_GW" && -n "${DEF_IF:-}" ]]; then
      ip route replace "${SSH_CLIENT_IP}/32" via "$SSH_DEFAULT_GW" dev "$DEF_IF" || true
      log "ikev2_failsafe_route_added=${SSH_CLIENT_IP}/32"
    fi
  fi

  cat > "$IKEV2_WORK/run_ikev2.py" <<'PY'
import base64
import os
import pexpect
import subprocess
import sys
import time

work = sys.argv[1]
status_path = os.path.join(work, "status")
log_path = os.path.join(work, "log.txt")
stop_path = os.path.join(work, "stop")

user = f"sw_egress_{int(time.time())}"
password = "SwSelfTest!234"

with open(log_path, "w", encoding="utf-8") as log:
    def w(msg: str):
        log.write(msg + "\n")
        log.flush()

    pw_b64 = base64.b64encode(password.encode()).decode()
    subprocess.run([
        "/usr/local/bin/securewave-ikev2-upsert-user",
        "--username", user,
        "--password-b64", pw_b64,
        "--output", "json",
    ], check=False, stdout=log, stderr=log)

    cmd = (
        "charon-cmd --debug 1 --profile ikev2-eap "
        "--host 127.0.0.1 --identity 127.0.0.1 "
        f"--eap-identity {user} "
        "--remote-identity 138.199.204.139 "
        "--cert /etc/ipsec.d/cacerts/ca-cert.pem "
        "--local-ts 0.0.0.0/0 --remote-ts 0.0.0.0/0"
    )
    child = pexpect.spawn(cmd, encoding="utf-8", timeout=45)
    established = False
    start = time.time()

    while True:
        if os.path.exists(stop_path):
            break
        if time.time() - start > 70:
            break
        idx = child.expect([
            r"EAP password:",
            r"CHILD_SA .* established",
            r"IKE_SA .* established",
            pexpect.EOF,
            pexpect.TIMEOUT,
        ])
        chunk = child.before or ""
        if chunk:
            log.write(chunk)
            log.flush()
        if idx == 0:
            child.sendline(password)
            continue
        if idx in (1, 2):
            established = True
            with open(status_path, "w", encoding="utf-8") as sf:
                sf.write("ESTABLISHED\n")
            continue
        if idx == 3:
            break
        if idx == 4:
            continue

    try:
        child.sendcontrol("c")
    except Exception:
        pass

    if not established:
        with open(status_path, "w", encoding="utf-8") as sf:
            sf.write("FAILED\n")
PY

  python3 "$IKEV2_WORK/run_ikev2.py" "$IKEV2_WORK" >/dev/null 2>&1 &
  IKEV2_HELPER_PID="$!"

  local i state
  for i in $(seq 1 50); do
    state="$(cat "$IKEV2_WORK/status" 2>/dev/null || true)"
    if [[ "$state" == "ESTABLISHED" ]]; then
      log "ikev2_selftest_connected"
      return 0
    fi
    if [[ "$state" == "FAILED" ]]; then
      log "ikev2_selftest_failed"
      cat "$IKEV2_WORK/log.txt" >> "$STATUS_LOG" 2>/dev/null || true
      return 1
    fi
    sleep 1
  done
  log "ikev2_selftest_timeout"
  cat "$IKEV2_WORK/log.txt" >> "$STATUS_LOG" 2>/dev/null || true
  return 1
}

require_cmd ip curl tcpdump awk grep sed

DEF_IF="$(ip route show default | awk '{print $5; exit}')"
DEF_GW="$(ip route show default | awk '{print $3; exit}')"
log "protocol=$PROTO def_if=$DEF_IF def_gw=$DEF_GW"

TUN_IF=""
TUNNEL_UP="false"
XFRM_DEFAULT="false"

if [[ "$PROTO" == "openvpn" ]]; then
  TUN_IF="$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^tun[[:alnum:]_.-]*$' | head -n1 || true)"
  if [[ -n "$TUN_IF" ]]; then
    TUNNEL_UP="true"
  elif [[ "${OPENVPN_SELFTEST_AUTO:-1}" == "1" && "$(id -u)" -eq 0 ]]; then
    start_openvpn_selftest && TUNNEL_UP="true"
    TUN_IF="${OPENVPN_TUN_IF:-$TUN_IF}"
  fi
elif [[ "$PROTO" == "ikev2" ]]; then
  if ipsec statusall 2>/dev/null | grep -Eq 'Security Associations \([1-9]'; then
    TUNNEL_UP="true"
  elif [[ "${IKEV2_SELFTEST_AUTO:-1}" == "1" && "$(id -u)" -eq 0 ]]; then
    start_ikev2_selftest && TUNNEL_UP="true"
  fi
  if ip xfrm policy 2>/dev/null | grep -q 'dst 0.0.0.0/0'; then
    XFRM_DEFAULT="true"
  fi
  if ip link show dev ipsec0 >/dev/null 2>&1; then
    TUN_IF="ipsec0"
  fi
else
  echo "Unsupported protocol: $PROTO" >&2
  exit 2
fi

collect_ips
VPN_IPS_ONLY="$OUT_DIR/public_ips_only.txt"
awk -F'\t' '{print $2}' "$RAW_IPS_FILE" | sed '/^$/d' > "$VPN_IPS_ONLY"
VPN_MAJ="$(majority_vote "$VPN_IPS_ONLY" || true)"
VPN_PUBLIC_IP="$(awk '{print $1}' <<<"$VPN_MAJ")"
VPN_PUBLIC_VOTES="$(awk '{print $2}' <<<"$VPN_MAJ")"

if [[ -z "$BASELINE_PUBLIC_IP" ]]; then
  BASELINE_PUBLIC_IP="$(head -n1 "$VPN_IPS_ONLY" 2>/dev/null || true)"
fi

{
  echo "=== ip route get 1.1.1.1 ==="
  ip route get 1.1.1.1 || true
  echo "=== ip route get 8.8.8.8 ==="
  ip route get 8.8.8.8 || true
} > "$ROUTE_FILE"

ROUTE_DEV="$(awk '/^1\.1\.1\.1/ {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}' "$ROUTE_FILE")"
ROUTE_SRC="$(awk '/^1\.1\.1\.1/ {for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' "$ROUTE_FILE")"

BOUND_IP=""
if [[ "$PROTO" == "openvpn" && -n "$TUN_IF" ]]; then
  BOUND_IP="$(curl --interface "$TUN_IF" -4fsS --max-time 8 https://api.ipify.org 2>/dev/null | tr -d '\n\r' || true)"
elif [[ "$PROTO" == "ikev2" && -n "$TUN_IF" ]]; then
  BOUND_IP="$(curl --interface "$TUN_IF" -4fsS --max-time 8 https://api.ipify.org 2>/dev/null | tr -d '\n\r' || true)"
fi
printf '%s\n' "$BOUND_IP" > "$BOUND_FILE"

: > "$TCPDUMP_DEF_FILE"
: > "$TCPDUMP_TUN_FILE"
set +e
timeout 7 tcpdump -ni "$DEF_IF" '(host 1.1.1.1 or host 8.8.8.8 or port 53 or udp port 4500 or esp)' -c 80 > "$TCPDUMP_DEF_FILE" 2>&1 &
TCPDUMP_DEF_PID="$!"
if [[ -n "$TUN_IF" ]]; then
  timeout 7 tcpdump -ni "$TUN_IF" '(host 1.1.1.1 or host 8.8.8.8 or port 53)' -c 80 > "$TCPDUMP_TUN_FILE" 2>&1 &
  TCPDUMP_TUN_PID="$!"
fi
sleep 1
curl -4fsS --max-time 6 https://api.ipify.org >/dev/null 2>&1 || true
curl -4fsS --max-time 6 https://ifconfig.co/ip >/dev/null 2>&1 || true
wait "$TCPDUMP_DEF_PID" 2>/dev/null || true
if [[ -n "${TCPDUMP_TUN_PID:-}" ]]; then
  wait "$TCPDUMP_TUN_PID" 2>/dev/null || true
fi
set -e

DEF_ESP_COUNT="$(grep -Eci ' esp |\.4500| proto 50' "$TCPDUMP_DEF_FILE" || true)"
DEF_PLAIN_COUNT="$(grep -Eci 'IP [0-9].*\.[0-9]+ > [0-9].*\.[0-9]+:' "$TCPDUMP_DEF_FILE" || true)"
TUN_COUNT="$(grep -Eci 'IP [0-9]' "$TCPDUMP_TUN_FILE" || true)"

ROUTE_VPN="false"
if [[ "$PROTO" == "openvpn" ]]; then
  [[ -n "$ROUTE_DEV" && "$ROUTE_DEV" =~ ^tun ]] && ROUTE_VPN="true"
else
  if [[ -n "$ROUTE_DEV" && "$ROUTE_DEV" == "ipsec0" ]]; then
    ROUTE_VPN="true"
  elif [[ "$XFRM_DEFAULT" == "true" && "$DEF_ESP_COUNT" -gt 0 && "$DEF_PLAIN_COUNT" -eq 0 ]]; then
    ROUTE_VPN="true"
  fi
fi

TCPDUMP_VPN="false"
if [[ "$PROTO" == "openvpn" ]]; then
  [[ "$TUN_COUNT" -gt 0 ]] && TCPDUMP_VPN="true"
else
  [[ "$DEF_ESP_COUNT" -gt 0 && "$DEF_PLAIN_COUNT" -eq 0 ]] && TCPDUMP_VPN="true"
fi

PUBLIC_CHANGED="false"
if [[ -n "$BASELINE_PUBLIC_IP" && -n "$VPN_PUBLIC_IP" && "$BASELINE_PUBLIC_IP" != "$VPN_PUBLIC_IP" ]]; then
  PUBLIC_CHANGED="true"
fi

BOUND_CHANGED="false"
if [[ -n "$BASELINE_PUBLIC_IP" && -n "$BOUND_IP" && "$BASELINE_PUBLIC_IP" != "$BOUND_IP" ]]; then
  BOUND_CHANGED="true"
fi

REASON_CODE=""
VERDICT="FAIL"
if [[ "$TUNNEL_UP" != "true" ]]; then
  if [[ "$PROTO" == "openvpn" ]]; then
    REASON_CODE="openvpn_missing_redirect_gateway"
  else
    REASON_CODE="ipsec_policy_not_routing_default"
  fi
elif [[ "$ROUTE_VPN" != "true" && "$TCPDUMP_VPN" != "true" ]]; then
  if [[ "$PROTO" == "openvpn" ]]; then
    if grep -q 'redirect-gateway' /etc/openvpn/server/server.conf 2>/dev/null; then
      REASON_CODE="route_metric_prefers_physical"
    else
      REASON_CODE="openvpn_missing_redirect_gateway"
    fi
  else
    if [[ "$XFRM_DEFAULT" != "true" ]]; then
      REASON_CODE="ipsec_policy_not_routing_default"
    else
      REASON_CODE="split_tunnel_routes"
    fi
  fi
elif [[ "$PUBLIC_CHANGED" != "true" && "$BOUND_CHANGED" != "true" ]]; then
  if [[ "$PROTO" == "openvpn" ]]; then
    REASON_CODE="dns_only_no_default_route"
  else
    REASON_CODE="nm_managed_routes_not_applied"
  fi
else
  VERDICT="PASS"
  REASON_CODE="ok"
fi

{
  echo "PROTO=$PROTO"
  echo "VERDICT=$VERDICT"
  echo "REASON_CODE=$REASON_CODE"
  echo "DEF_IF=$DEF_IF"
  echo "DEF_GW=$DEF_GW"
  echo "TUN_IF=$TUN_IF"
  echo "TUNNEL_UP=$TUNNEL_UP"
  echo "ROUTE_DEV=$ROUTE_DEV"
  echo "ROUTE_SRC=$ROUTE_SRC"
  echo "ROUTE_VPN=$ROUTE_VPN"
  echo "TCPDUMP_VPN=$TCPDUMP_VPN"
  echo "DEF_ESP_COUNT=$DEF_ESP_COUNT"
  echo "DEF_PLAIN_COUNT=$DEF_PLAIN_COUNT"
  echo "TUN_COUNT=$TUN_COUNT"
  echo "BASELINE_PUBLIC_IP=$BASELINE_PUBLIC_IP"
  echo "VPN_PUBLIC_IP=$VPN_PUBLIC_IP"
  echo "VPN_PUBLIC_VOTES=$VPN_PUBLIC_VOTES"
  echo "BOUND_IP=$BOUND_IP"
  echo "PUBLIC_CHANGED=$PUBLIC_CHANGED"
  echo "BOUND_CHANGED=$BOUND_CHANGED"
} > "$RESULT_FILE"

cat > "$REPORT_FILE" <<MD
# Egress Check Report

- Protocol: \
  \
  \
  **$PROTO**
- Baseline public IP: **$BASELINE_PUBLIC_IP**
- VPN-on public IP (majority): **$VPN_PUBLIC_IP** (votes=$VPN_PUBLIC_VOTES)
- Interface-bound IP: **$BOUND_IP**
- Tunnel up: **$TUNNEL_UP**
- Route decision dev/src: **$ROUTE_DEV / $ROUTE_SRC**
- Route indicates VPN path: **$ROUTE_VPN**
- Tcpdump indicates VPN path: **$TCPDUMP_VPN**
- Default-if ESP/UDP4500 hits: **$DEF_ESP_COUNT**
- Default-if plain IP hits: **$DEF_PLAIN_COUNT**
- Tunnel-if hits: **$TUN_COUNT**
- VERDICT: **$VERDICT**
- REASON_CODE: **$REASON_CODE**

## Raw Artifacts
- Public IP raw: public_ip_raw.txt
- Route get: route_get.txt
- Default iface tcpdump: tcpdump_default.txt
- Tunnel iface tcpdump: tcpdump_tunnel.txt
- Result env: result.env
- Status log: status.log
MD

log "verdict=$VERDICT reason=$REASON_CODE"
