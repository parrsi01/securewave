#!/usr/bin/env bash
# SecureWave — idempotent server-side VPN routing isolation.
#
# Usage:
#   setup_vpn_routing.sh setup                  — configure all protocols
#   setup_vpn_routing.sh teardown <proto>        — remove one protocol only
#   setup_vpn_routing.sh setup <proto>           — (re-)configure one protocol
#
# Protocol → table → fwmark → chain:
#   wireguard  → 100 → 0x64  → WG_NAT
#   openvpn    → 200 → 0xc8  → OVPN_NAT
#   ikev2      → 300 → 0x12c → IKEV2_NAT
#
# Guarantees:
#   - net.ipv4.ip_forward is NEVER disabled on teardown.
#   - Shared chains (POSTROUTING, FORWARD, mangle PREROUTING) are NEVER flushed.
#   - Global default route (table main) is NEVER modified.
#   - Teardown removes only the named protocol's state.
set -euo pipefail
[[ "${EUID}" -ne 0 ]] && { echo "Run as root." >&2; exit 1; }

EGRESS_IFACE="${EGRESS_IFACE:-$(ip -4 route show default | awk '{print $5; exit}')}"
DEFAULT_VIA="${DEFAULT_VIA:-$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')}"
WG_CIDR="${WG_CIDR:-10.8.0.0/24}"
OVPN_CIDR="${OVPN_CIDR:-10.44.0.0/24}"
IKEV2_CIDR="${IKEV2_CIDR:-10.45.0.0/24}"
WG_IFACE="${WG_IFACE:-wg0}"
OVPN_IFACE="${OVPN_IFACE:-tun0}"
IKEV2_IFACE="${IKEV2_IFACE:-ipsec0}"

[[ -z "${EGRESS_IFACE}" ]] && { echo "Cannot detect egress interface. Set EGRESS_IFACE." >&2; exit 1; }

ACTION="${1:-setup}"

# ── helpers ──────────────────────────────────────────────────────────────────

run_q() { "$@" 2>/dev/null || true; }

ensure_ip_forward() {
  # Written to sysctl.d so it survives reboots.
  # Never touched on teardown.
  cat > /etc/sysctl.d/99-securewave-vpn.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
  echo "[vpn-routing] ip_forward=1 confirmed (persisted in sysctl.d)"
}

setup_proto() {
  local proto="$1" table="$2" mark="$3" iface="$4" cidr="$5" chain="$6"
  echo "[vpn-routing] setup proto=${proto} table=${table} mark=${mark} iface=${iface}"

  # 1. Route: protocol-owned table only. Never touches main/default.
  run_q ip -4 route replace "${cidr}" dev "${iface}" table "${table}"
  if [[ -n "${DEFAULT_VIA}" ]]; then
    run_q ip -4 route replace default via "${DEFAULT_VIA}" dev "${EGRESS_IFACE}" table "${table}"
  else
    run_q ip -4 route replace default dev "${EGRESS_IFACE}" table "${table}"
  fi

  # 2. Policy rule: fwmark → dedicated table.
  if ! ip rule show | grep -qF "fwmark ${mark} lookup ${table}"; then
    ip rule add fwmark "${mark}" table "${table}" priority 200
    echo "[vpn-routing]   added ip rule fwmark ${mark} -> table ${table}"
  else
    echo "[vpn-routing]   ip rule already present"
  fi

  # 3. Mangle: mark ingress on VPN interface (idempotent).
  if ! iptables -t mangle -C PREROUTING \
       -i "${iface}" -j MARK --set-mark "${mark}" 2>/dev/null; then
    iptables -t mangle -A PREROUTING \
      -i "${iface}" -j MARK --set-mark "${mark}"
    echo "[vpn-routing]   mangle mark added"
  fi

  # 4. NAT: isolated chain. Flush only own chain; never flush POSTROUTING.
  iptables -t nat -N "${chain}" 2>/dev/null || true
  iptables -t nat -F "${chain}"
  iptables -t nat -A "${chain}" \
    -s "${cidr}" -o "${EGRESS_IFACE}" -j MASQUERADE
  if ! iptables -t nat -C POSTROUTING -j "${chain}" 2>/dev/null; then
    iptables -t nat -A POSTROUTING -j "${chain}"
    echo "[vpn-routing]   POSTROUTING -> ${chain} jump added"
  fi

  # 5. FORWARD: scoped to this interface pair only.
  if ! iptables -C FORWARD \
       -i "${iface}" -o "${EGRESS_IFACE}" -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i "${iface}" -o "${EGRESS_IFACE}" -j ACCEPT
  fi
  if ! iptables -C FORWARD \
       -i "${EGRESS_IFACE}" -o "${iface}" \
       -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    iptables -A FORWARD -i "${EGRESS_IFACE}" -o "${iface}" \
      -m state --state RELATED,ESTABLISHED -j ACCEPT
  fi

  echo "[vpn-routing] setup done: ${proto}"
}

teardown_proto() {
  local proto="$1" table="$2" mark="$3" iface="$4" cidr="$5" chain="$6"
  echo "[vpn-routing] teardown proto=${proto}"

  # 1. Flush protocol-owned table only. Never touches main or other tables.
  run_q ip -4 route flush table "${table}"

  # 2. Remove this protocol's policy rule only (loop clears duplicates).
  for _i in 1 2 3 4; do
    ip rule del fwmark "${mark}" table "${table}" 2>/dev/null || break
  done

  # 3. Remove mangle mark for this interface only.
  run_q iptables -t mangle -D PREROUTING \
    -i "${iface}" -j MARK --set-mark "${mark}"

  # 4. Remove jump; flush + delete own chain. Never touch other chains.
  run_q iptables -t nat -D POSTROUTING -j "${chain}"
  run_q iptables -t nat -F "${chain}"
  run_q iptables -t nat -X "${chain}"

  # 5. Remove FORWARD rules for this interface pair only.
  run_q iptables -D FORWARD -i "${iface}" -o "${EGRESS_IFACE}" -j ACCEPT
  run_q iptables -D FORWARD \
    -i "${EGRESS_IFACE}" -o "${iface}" \
    -m state --state RELATED,ESTABLISHED -j ACCEPT

  # ip_forward intentionally NOT touched.
  echo "[vpn-routing] teardown done: ${proto} (ip_forward unchanged)"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

case "${ACTION}" in
  setup)
    TARGET="${2:-all}"
    [[ "${TARGET}" == "all" || "${TARGET}" == "wireguard" ]] && \
      setup_proto wireguard 100 0x64  "${WG_IFACE}"    "${WG_CIDR}"   WG_NAT
    [[ "${TARGET}" == "all" || "${TARGET}" == "openvpn" ]] && \
      setup_proto openvpn   200 0xc8  "${OVPN_IFACE}"  "${OVPN_CIDR}" OVPN_NAT
    [[ "${TARGET}" == "all" || "${TARGET}" == "ikev2" ]] && \
      setup_proto ikev2     300 0x12c "${IKEV2_IFACE}" "${IKEV2_CIDR}" IKEV2_NAT
    [[ "${TARGET}" == "all" ]] && ensure_ip_forward
    echo "[vpn-routing] setup complete"
    ;;
  teardown)
    PROTO="${2:-}"
    case "${PROTO}" in
      wireguard) teardown_proto wireguard 100 0x64  "${WG_IFACE}"    "${WG_CIDR}"   WG_NAT ;;
      openvpn)   teardown_proto openvpn   200 0xc8  "${OVPN_IFACE}"  "${OVPN_CIDR}" OVPN_NAT ;;
      ikev2)     teardown_proto ikev2     300 0x12c "${IKEV2_IFACE}" "${IKEV2_CIDR}" IKEV2_NAT ;;
      *) echo "Usage: $0 teardown <wireguard|openvpn|ikev2>" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "Usage: $0 [setup [proto|all] | teardown <proto>]" >&2
    exit 1
    ;;
esac
