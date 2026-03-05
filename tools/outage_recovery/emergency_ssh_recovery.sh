#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "This script must be run as root on the VPS console." >&2
  exit 1
fi

detect_host_ip() {
  local detected=""
  detected="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "${detected}" ]]; then
    detected="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  fi
  if [[ -z "${detected}" ]]; then
    detected="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s' "${detected}"
}

is_hetzner_host() {
  local vendor=""
  local board_vendor=""
  vendor="$(tr '[:upper:]' '[:lower:]' < /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  board_vendor="$(tr '[:upper:]' '[:lower:]' < /sys/class/dmi/id/board_vendor 2>/dev/null || true)"
  if [[ -f /etc/hetzner-release ]]; then
    return 0
  fi
  [[ "${vendor}" == *hetzner* || "${board_vendor}" == *hetzner* ]]
}

EXPECTED_IP="${SECUREWAVE_EXPECTED_VPS_IP:-}"
CURRENT_IP="$(detect_host_ip)"
if [[ -n "${EXPECTED_IP}" && -n "${CURRENT_IP}" && "${CURRENT_IP}" != "${EXPECTED_IP}" ]]; then
  echo "Refusing to run: current host IP (${CURRENT_IP}) does not match expected VPS IP (${EXPECTED_IP})." >&2
  exit 1
fi

if ! is_hetzner_host && [[ "${SECUREWAVE_ALLOW_NON_HETZNER_HOST:-0}" != "1" ]]; then
  echo "Refusing to run: this host does not appear to be Hetzner. Set SECUREWAVE_ALLOW_NON_HETZNER_HOST=1 only for intentional local/dev use." >&2
  exit 1
fi

echo "=== SECUREWAVE EMERGENCY SSH RECOVERY START ==="
date -u

SNAP_DIR="/root/securewave_emergency_recovery_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$SNAP_DIR" 2>/dev/null || true
(ip addr || true) > "$SNAP_DIR/ip_addr_before.txt" 2>/dev/null || true
(ip route || true) > "$SNAP_DIR/ip_route_before.txt" 2>/dev/null || true
(ip rule || true) > "$SNAP_DIR/ip_rule_before.txt" 2>/dev/null || true
(iptables -S || true) > "$SNAP_DIR/iptables_filter_before.txt" 2>/dev/null || true
(iptables -t nat -S || true) > "$SNAP_DIR/iptables_nat_before.txt" 2>/dev/null || true
(nft list ruleset || true) > "$SNAP_DIR/nft_ruleset_before.txt" 2>/dev/null || true
(ufw status verbose || true) > "$SNAP_DIR/ufw_before.txt" 2>/dev/null || true
(ss -tulpen || true) > "$SNAP_DIR/ss_before.txt" 2>/dev/null || true
(grep -RinE '^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)[[:space:]]+' \
  /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null || true) > "$SNAP_DIR/sshd_config_before.txt" 2>/dev/null || true

echo
echo "[1] Detecting primary interface..."
PRIMARY_IF="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
if [[ -z "${PRIMARY_IF:-}" ]]; then
  PRIMARY_IF="$(ip -o link show | awk -F': ' '{print $2}' | grep -E -v '^(lo|docker|veth|br-)' | head -n1 || true)"
fi

if [[ -z "${PRIMARY_IF:-}" ]]; then
  echo "ERROR: Could not detect a primary interface"
  exit 1
fi

echo "Primary interface: $PRIMARY_IF"

echo
echo "[2] Ensuring default route exists..."
if ip route show default | grep -q '^default'; then
  echo "Default route exists."
else
  echo "No default route found. Recovering..."

  GATEWAY=""
  GATEWAY="$(ip -4 route show default dev "$PRIMARY_IF" 2>/dev/null | awk '{print $3; exit}' || true)"

  if [[ -z "$GATEWAY" ]]; then
    GATEWAY="$(ip -4 route show dev "$PRIMARY_IF" 2>/dev/null | awk '/via/ {for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}}' || true)"
  fi

  if [[ -z "$GATEWAY" ]]; then
    CIDR="$(ip -4 -o addr show dev "$PRIMARY_IF" scope global | awk '{print $4; exit}' || true)"
    if [[ -n "$CIDR" ]]; then
      if command -v python3 >/dev/null 2>&1; then
        GATEWAY="$(CIDR="$CIDR" python3 - <<'PY'
import ipaddress, os
cidr = os.environ.get('CIDR', '')
if cidr:
    net = ipaddress.ip_interface(cidr).network
    hosts = list(net.hosts())
    if hosts:
        print(hosts[0])
PY
)"
      else
        GATEWAY="$(echo "$CIDR" | awk -F'[./]' '{print $1"."$2"."$3".1"}')"
      fi
    fi
  fi

  if [[ -z "$GATEWAY" ]]; then
    echo "ERROR: Could not auto-detect gateway. Inspect manually: ip route"
    exit 1
  fi

  ip route replace default via "$GATEWAY" dev "$PRIMARY_IF" || true
  echo "Default route restored via $GATEWAY dev $PRIMARY_IF"
fi

echo
echo "[3] Restoring SSH configuration..."
mkdir -p /etc/ssh/sshd_config.d
cp -a /etc/ssh/sshd_config "$SNAP_DIR/sshd_config.backup"

cat > /etc/ssh/sshd_config.d/99-securewave-recovery.conf <<'CFG'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
CFG

sshd -t

echo
echo "[4] Ensuring SSH service is enabled and running..."
if systemctl list-unit-files | grep -q '^ssh\.service'; then
  systemctl enable ssh || true
  systemctl restart ssh || true
elif systemctl list-unit-files | grep -q '^sshd\.service'; then
  systemctl enable sshd || true
  systemctl restart sshd || true
else
  systemctl enable ssh || systemctl enable sshd || true
  systemctl restart ssh || systemctl restart sshd || true
fi

echo
echo "[5] Allowing SSH in firewall (non-destructive)..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow 22/tcp || true
  ufw reload || true
fi

iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
  iptables -I INPUT 2 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

if nft list table inet filter >/dev/null 2>&1; then
  nft insert rule inet filter input tcp dport 22 counter accept || true
fi

echo
echo "[6] Optional forwarding sanity..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

echo
echo "[7] Verifying SSH is reachable locally..."
ss -tulpen | grep -E 'LISTEN.+:22[[:space:]]' || true
sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication) ' || true

echo
echo "=== CURRENT NETWORK STATE ==="
echo "--- ip addr ---"
ip addr || true

echo
echo "--- ip route ---"
ip route || true

echo
echo "--- ip rule ---"
ip rule || true

echo
echo "--- iptables -S ---"
iptables -S || true

echo
echo "--- nft list ruleset ---"
nft list ruleset || true

echo
echo "--- ufw status ---"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose || true
else
  echo "ufw not installed"
fi

echo
echo "Snapshots saved under: $SNAP_DIR"
echo "Test from your local machine: ssh root@$(hostname -I | awk '{print $1}')"
echo "=== SECUREWAVE EMERGENCY SSH RECOVERY COMPLETE ==="
echo "Now test SSH from your local machine."
