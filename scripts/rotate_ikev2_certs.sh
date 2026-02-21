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

CA_DIR="/etc/securewave/secrets/ikev2/ca"
SERVER_KEY="/etc/securewave/secrets/ikev2/server-key.pem"
SERVER_CERT="/etc/securewave/secrets/ikev2/server-cert.pem"
OPENSSL_CNF="${CA_DIR}/openssl.cnf"
SERVER_IDENTITY="${IKEV2_SERVER_IDENTITY:-$(hostname -f 2>/dev/null || hostname)}"
SERVER_CERT_DAYS="${IKEV2_SERVER_CERT_DAYS:-825}"
BACKUP_DIR="/var/backups/securewave"
TS="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ ! -f "${OPENSSL_CNF}" ]]; then
  echo "IKEv2 PKI config missing. Run scripts/provision_ikev2.sh first." >&2
  exit 3
fi

install -d -m 700 "${BACKUP_DIR}"
tar -C / -czf "${BACKUP_DIR}/ikev2-pki-${TS}.tar.gz" \
  "etc/securewave/secrets/ikev2/ca" \
  "etc/securewave/secrets/ikev2/server-key.pem" \
  "etc/securewave/secrets/ikev2/server-cert.pem"

rm -f "${CA_DIR}/ca-key.pem" "${CA_DIR}/ca-cert.pem" "${CA_DIR}/ca-crl.pem" "${SERVER_KEY}" "${SERVER_CERT}"
rm -f "${CA_DIR}/index.txt" "${CA_DIR}/serial" "${CA_DIR}/crlnumber"
install -d -m 700 "${CA_DIR}/newcerts" "${CA_DIR}/private" "${CA_DIR}/csr"
: > "${CA_DIR}/index.txt"
echo 1000 > "${CA_DIR}/serial"
echo 1000 > "${CA_DIR}/crlnumber"

openssl genrsa -out "${CA_DIR}/ca-key.pem" 4096
openssl req -x509 -new -nodes -key "${CA_DIR}/ca-key.pem" -sha256 -days 3650 \
  -subj "/CN=SecureWave IKEv2 CA" -out "${CA_DIR}/ca-cert.pem"
openssl genrsa -out "${SERVER_KEY}" 4096
openssl req -new -key "${SERVER_KEY}" -out "${CA_DIR}/csr/server.csr.pem" -subj "/CN=${SERVER_IDENTITY}"
openssl ca -batch -config "${OPENSSL_CNF}" -days "${SERVER_CERT_DAYS}" -notext \
  -in "${CA_DIR}/csr/server.csr.pem" -out "${SERVER_CERT}"
openssl ca -gencrl -config "${OPENSSL_CNF}" -out "${CA_DIR}/ca-crl.pem"

cp -f "${CA_DIR}/ca-cert.pem" /etc/ipsec.d/cacerts/securewave-ikev2-ca-cert.pem
cp -f "${SERVER_CERT}" /etc/ipsec.d/certs/securewave-ikev2-server-cert.pem
cp -f "${SERVER_KEY}" /etc/ipsec.d/private/securewave-ikev2-server-key.pem
cp -f "${CA_DIR}/ca-crl.pem" /etc/ipsec.d/crls/securewave-ikev2-ca-crl.pem
chmod 600 /etc/ipsec.d/private/securewave-ikev2-server-key.pem

if systemctl list-unit-files | grep -q '^strongswan-starter'; then
  systemctl restart strongswan-starter
else
  systemctl restart strongswan
fi

echo "IKEv2 certificate rotation completed."
echo "Backup: ${BACKUP_DIR}/ikev2-pki-${TS}.tar.gz"
echo "BREAK GLASS: restore previous PKI with:"
echo "  tar -C / -xzf ${BACKUP_DIR}/ikev2-pki-${TS}.tar.gz"
echo "  systemctl restart strongswan-starter || systemctl restart strongswan"
