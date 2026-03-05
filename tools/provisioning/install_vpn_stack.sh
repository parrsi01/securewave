#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds tee apt-get systemctl sysctl ip iptables awk grep install mkdir
require_root
require_hetzner_host
begin_script_log "install_vpn_stack"

PACKAGES=(
  wireguard
  wireguard-tools
  openvpn
  strongswan
  strongswan-pki
  iptables
  nftables
  curl
  jq
  fail2ban
)

SECUREWAVE_VPN_CIDRS="${SECUREWAVE_VPN_CIDRS:-10.8.0.0/24 10.10.0.0/24 10.14.0.0/24}"
UPLINK_IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"

ensure_iptables_rule() {
  local table="$1"
  shift

  if ! iptables -t "${table}" -C "$@" >/dev/null 2>&1; then
    iptables -t "${table}" -A "$@"
  fi
}

if [[ -z "${UPLINK_IFACE}" ]]; then
  error_line "Unable to detect the primary uplink interface."
  exit 1
fi

log_line "Installing VPN stack packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends "${PACKAGES[@]}"

log_line "Ensuring SecureWave configuration directories exist"
install -d -m 750 /etc/securewave
install -d -m 750 /etc/securewave/wireguard
install -d -m 750 /etc/securewave/openvpn
install -d -m 750 /etc/securewave/ikev2

log_line "Enabling IP forwarding"
cat > /etc/sysctl.d/99-securewave-forwarding.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system >/dev/null

log_line "Applying additive NAT and forwarding rules on ${UPLINK_IFACE}"
ensure_iptables_rule filter FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
for cidr in ${SECUREWAVE_VPN_CIDRS}; do
  ensure_iptables_rule nat POSTROUTING -s "${cidr}" -o "${UPLINK_IFACE}" -j MASQUERADE
  ensure_iptables_rule filter FORWARD -s "${cidr}" -j ACCEPT
done

if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
elif command -v iptables-save >/dev/null 2>&1; then
  install -d -m 755 /etc/iptables
  iptables-save > /etc/iptables/rules.v4
fi

log_line "Enabling long-lived services"
for unit in fail2ban nftables; do
  if unit_file_exists "${unit}"; then
    systemctl enable --now "${unit}.service"
  fi
done

for unit in strongswan-starter strongswan ipsec; do
  if unit_file_exists "${unit}"; then
    systemctl enable --now "${unit}.service"
    break
  fi
done

if [[ -f /etc/wireguard/wg0.conf ]] && unit_file_exists 'wg-quick@'; then
  systemctl enable wg-quick@wg0.service
fi

if [[ -f /etc/openvpn/server/server.conf ]] && unit_file_exists 'openvpn-server@'; then
  systemctl enable openvpn-server@server.service
fi

log_line "Provisioning complete"
log_line "Packages installed: ${PACKAGES[*]}"
log_line "VPN CIDRs: ${SECUREWAVE_VPN_CIDRS}"
log_line "Log file: ${LOG_FILE}"
