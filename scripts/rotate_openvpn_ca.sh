#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

if [[ "${SECUREWAVE_ROTATE_CONFIRM:-}" != "YES" ]]; then
  echo "Refusing to rotate without SECUREWAVE_ROTATE_CONFIRM=YES" >&2
  exit 2
fi

EASYRSA_DIR="/etc/securewave/secrets/openvpn/easy-rsa"
SERVER_CN="${OPENVPN_SERVER_CN:-securewave-openvpn-server}"
BACKUP_DIR="/var/backups/securewave"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ ! -x "${EASYRSA_DIR}/easyrsa" ]]; then
  echo "easy-rsa not found at ${EASYRSA_DIR}. Run scripts/provision_openvpn.sh first." >&2
  exit 3
fi

install -d -m 700 "${BACKUP_DIR}"
tar -C / -czf "${BACKUP_DIR}/openvpn-pki-${TS}.tar.gz" "etc/securewave/secrets/openvpn/easy-rsa/pki"

cd "${EASYRSA_DIR}"
rm -rf "${EASYRSA_DIR}/pki"
./easyrsa --batch init-pki
./easyrsa --batch build-ca nopass
./easyrsa --batch build-server-full "${SERVER_CN}" nopass
./easyrsa --batch gen-crl

systemctl restart openvpn-server@securewave || true
if systemctl list-unit-files | grep -q '^openvpn-server@securewave-tcp443'; then
  systemctl restart openvpn-server@securewave-tcp443 || true
fi

echo "OpenVPN CA rotation completed."
echo "Backup: ${BACKUP_DIR}/openvpn-pki-${TS}.tar.gz"
echo "BREAK GLASS: restore previous PKI with:"
echo "  tar -C / -xzf ${BACKUP_DIR}/openvpn-pki-${TS}.tar.gz"
echo "  systemctl restart openvpn-server@securewave"
