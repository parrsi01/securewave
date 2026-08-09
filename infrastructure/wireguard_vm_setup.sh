#!/usr/bin/env bash
set -euo pipefail

# Provision the one SecureWave WireGuard target on a fresh Ubuntu Hetzner VM.
# Run as root. Peer changes are made later over the backend's pinned SSH path;
# this script does not install an HTTP management API.

[[ "$(id -u)" == "0" ]] || { echo "Run as root." >&2; exit 1; }

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_PORT="${WG_PORT:-51820}"
WG_NETWORK="${WG_NETWORK:-10.8.0.0/24}"
WG_ADDRESS="${WG_ADDRESS:-10.8.0.1/24}"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  wireguard wireguard-tools iptables

install -d -m 0700 /etc/wireguard
install -d -m 0755 /etc/sysctl.d

cat >/etc/sysctl.d/99-securewave-wireguard.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system >/dev/null

private_key=/etc/wireguard/${WG_INTERFACE}.private
public_key=/etc/wireguard/${WG_INTERFACE}.public
if [[ ! -s "$private_key" ]]; then
  umask 077
  wg genkey >"$private_key"
fi
if [[ ! -s "$public_key" ]]; then
  wg pubkey <"$private_key" >"$public_key"
fi

uplink="$(ip route show default | awk 'NR == 1 {print $5}')"
[[ -n "$uplink" ]] || { echo "Could not determine the default network interface." >&2; exit 1; }

config=/etc/wireguard/${WG_INTERFACE}.conf
if [[ ! -f "$config" ]]; then
  umask 077
  cat >"$config" <<EOF
[Interface]
PrivateKey = $(<"$private_key")
Address = $WG_ADDRESS
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -s $WG_NETWORK -o $uplink -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -s $WG_NETWORK -o $uplink -j MASQUERADE
EOF
fi
chmod 600 "$config" "$private_key"

systemctl enable --now "wg-quick@${WG_INTERFACE}"
echo "WireGuard target ready: interface=${WG_INTERFACE} port=${WG_PORT}/udp public_key=$(<"$public_key")"
echo "Record the public key and endpoint in the backend target configuration."
