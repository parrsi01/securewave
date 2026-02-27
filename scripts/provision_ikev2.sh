#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

IKEV2_SERVER_IDENTITY="${IKEV2_SERVER_IDENTITY:-$(hostname -f 2>/dev/null || hostname)}"
IKEV2_POOL_CIDR="${IKEV2_POOL_CIDR:-10.45.0.0/24}"
IKEV2_INTERFACE="${IKEV2_INTERFACE:-$(ip -4 route list default | awk '{print $5; exit}') }"
IKEV2_DNS_1="${IKEV2_DNS_1:-94.140.14.14}"
IKEV2_DNS_2="${IKEV2_DNS_2:-94.140.15.15}"
IKEV2_SERVER_CERT_DAYS="${IKEV2_SERVER_CERT_DAYS:-825}"
IKEV2_CLIENT_CERT_DAYS="${IKEV2_CLIENT_CERT_DAYS:-30}"

if [[ -z "${IKEV2_INTERFACE}" ]]; then
  echo "Could not determine egress interface. Set IKEV2_INTERFACE." >&2
  exit 1
fi

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y strongswan strongswan-pki openssl jq ufw python3

install -d -m 700 /etc/securewave/secrets
install -d -m 700 /etc/securewave/secrets/ikev2
install -d -m 700 /etc/securewave/secrets/ikev2/ca
install -d -m 700 /etc/securewave/secrets/ikev2/clients
install -d -m 755 /etc/securewave/ikev2
install -d -m 755 /etc/ipsec.d/private /etc/ipsec.d/certs /etc/ipsec.d/cacerts /etc/ipsec.d/crls

TOKEN_SECRET_FILE="/etc/securewave/secrets/provisioning_token_secret"
if [[ ! -s "${TOKEN_SECRET_FILE}" ]]; then
  umask 077
  openssl rand -hex 32 > "${TOKEN_SECRET_FILE}"
  chmod 600 "${TOKEN_SECRET_FILE}"
fi

if [[ ! -x /usr/local/bin/securewave-validate-provisioning-token ]]; then
  cat > /usr/local/bin/securewave-validate-provisioning-token <<'PY'
#!/usr/bin/env python3
import argparse
import base64
import hashlib
import hmac
import json
import os
import sys
import time


def b64u_decode(value: str) -> bytes:
    pad = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode((value + pad).encode("ascii"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", required=True)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--protocol", required=True)
    args = parser.parse_args()

    secret = (os.getenv("SECUREWAVE_PROVISIONING_TOKEN_SECRET") or "").strip()
    if not secret:
      try:
        with open("/etc/securewave/secrets/provisioning_token_secret", "r", encoding="utf-8") as handle:
          secret = handle.read().strip()
      except OSError:
        secret = ""
    if not secret:
      print("missing_secret", file=sys.stderr)
      return 2

    try:
      body, sig = args.token.split(".", 1)
    except ValueError:
      print("invalid_token_format", file=sys.stderr)
      return 3

    expected = hmac.new(secret.encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest()
    try:
      actual = b64u_decode(sig)
    except Exception:
      print("invalid_token_signature_encoding", file=sys.stderr)
      return 4

    if not hmac.compare_digest(expected, actual):
      print("invalid_token_signature", file=sys.stderr)
      return 5

    try:
      payload = json.loads(b64u_decode(body).decode("utf-8"))
    except Exception:
      print("invalid_token_payload", file=sys.stderr)
      return 6

    if payload.get("sub") != args.subject:
      print("subject_mismatch", file=sys.stderr)
      return 7
    if payload.get("proto") != args.protocol:
      print("protocol_mismatch", file=sys.stderr)
      return 8

    now = int(time.time())
    exp = int(payload.get("exp", 0))
    iat = int(payload.get("iat", 0))
    if exp <= now or iat > now + 60:
      print("token_expired_or_invalid", file=sys.stderr)
      return 9

    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod 700 /usr/local/bin/securewave-validate-provisioning-token
fi

CA_DIR="/etc/securewave/secrets/ikev2/ca"
OPENSSL_CNF="${CA_DIR}/openssl.cnf"

if [[ ! -f "${OPENSSL_CNF}" ]]; then
  cat > "${OPENSSL_CNF}" <<CONF
[ ca ]
default_ca = securewave_ca

[ securewave_ca ]
dir               = ${CA_DIR}
certs             = \$dir/certs
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
crlnumber         = \$dir/crlnumber
certificate       = \$dir/ca-cert.pem
private_key       = \$dir/ca-key.pem
default_md        = sha256
default_days      = 3650
policy            = policy_loose
x509_extensions   = usr_cert
copy_extensions   = copy

[ policy_loose ]
commonName = supplied

[ req ]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only

[ req_distinguished_name ]
commonName = Common Name
commonName_max = 96

[ usr_cert ]
basicConstraints=CA:FALSE
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
extendedKeyUsage=clientAuth,serverAuth

[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
CONF
fi

install -d -m 700 "${CA_DIR}/certs" "${CA_DIR}/newcerts" "${CA_DIR}/private" "${CA_DIR}/csr"
: > "${CA_DIR}/index.txt"
[[ -f "${CA_DIR}/serial" ]] || echo 1000 > "${CA_DIR}/serial"
[[ -f "${CA_DIR}/crlnumber" ]] || echo 1000 > "${CA_DIR}/crlnumber"
chmod 600 "${CA_DIR}/serial" "${CA_DIR}/crlnumber" "${CA_DIR}/index.txt"

if [[ ! -f "${CA_DIR}/ca-key.pem" ]]; then
  openssl genrsa -out "${CA_DIR}/ca-key.pem" 4096
  chmod 600 "${CA_DIR}/ca-key.pem"
fi

if [[ ! -f "${CA_DIR}/ca-cert.pem" ]]; then
  openssl req -x509 -new -nodes -key "${CA_DIR}/ca-key.pem" -sha256 -days 3650 \
    -subj "/CN=SecureWave IKEv2 CA" -out "${CA_DIR}/ca-cert.pem"
  chmod 644 "${CA_DIR}/ca-cert.pem"
fi

SERVER_KEY="/etc/securewave/secrets/ikev2/server-key.pem"
SERVER_CSR="${CA_DIR}/csr/server.csr.pem"
SERVER_CERT="/etc/securewave/secrets/ikev2/server-cert.pem"

if [[ ! -f "${SERVER_KEY}" ]]; then
  openssl genrsa -out "${SERVER_KEY}" 4096
  chmod 600 "${SERVER_KEY}"
fi

if [[ ! -f "${SERVER_CERT}" ]]; then
  openssl req -new -key "${SERVER_KEY}" -out "${SERVER_CSR}" -subj "/CN=${IKEV2_SERVER_IDENTITY}"
  openssl ca -batch -config "${OPENSSL_CNF}" -days "${IKEV2_SERVER_CERT_DAYS}" -notext \
    -in "${SERVER_CSR}" -out "${SERVER_CERT}"
  chmod 644 "${SERVER_CERT}"
fi

openssl ca -gencrl -config "${OPENSSL_CNF}" -out "${CA_DIR}/ca-crl.pem" >/dev/null 2>&1 || true
cp -f "${CA_DIR}/ca-cert.pem" /etc/ipsec.d/cacerts/securewave-ikev2-ca-cert.pem
cp -f "${SERVER_CERT}" /etc/ipsec.d/certs/securewave-ikev2-server-cert.pem
cp -f "${SERVER_KEY}" /etc/ipsec.d/private/securewave-ikev2-server-key.pem
cp -f "${CA_DIR}/ca-crl.pem" /etc/ipsec.d/crls/securewave-ikev2-ca-crl.pem || true
chmod 600 /etc/ipsec.d/private/securewave-ikev2-server-key.pem
chmod 644 /etc/ipsec.d/certs/securewave-ikev2-server-cert.pem /etc/ipsec.d/cacerts/securewave-ikev2-ca-cert.pem

cat > /etc/ipsec.conf <<CONF
config setup
  uniqueids=no
  strictcrlpolicy=no

conn securewave-ikev2
  auto=add
  keyexchange=ikev2
  type=tunnel
  fragmentation=yes
  forceencaps=yes
  dpdaction=clear
  rekey=no
  left=%any
  leftid=@${IKEV2_SERVER_IDENTITY}
  leftcert=securewave-ikev2-server-cert.pem
  leftsendcert=always
  leftsubnet=0.0.0.0/0,::/0
  right=%any
  rightid=%any
  rightauth=eap-tls
  rightsourceip=${IKEV2_POOL_CIDR}
  rightdns=${IKEV2_DNS_1},${IKEV2_DNS_2}
  eap_identity=%identity
CONF

cat > /etc/ipsec.secrets <<CONF
: RSA /etc/ipsec.d/private/securewave-ikev2-server-key.pem
CONF
chmod 600 /etc/ipsec.secrets

# ip_forward and routing isolation are managed by securewave-vpn-routing.
# Table 300 + IKEV2_NAT chain; does not write bare MASQUERADE to UFW before.rules.
# Teardown removes only IKEv2 state and never affects WireGuard or OpenVPN.
if [[ -x /usr/local/bin/securewave-vpn-routing ]]; then
  EGRESS_IFACE="${IKEV2_INTERFACE}" \
  IKEV2_CIDR="${IKEV2_POOL_CIDR}" \
    /usr/local/bin/securewave-vpn-routing setup ikev2
else
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${SELF_DIR}/setup_vpn_routing.sh" ]]; then
    install -m 755 "${SELF_DIR}/setup_vpn_routing.sh" /usr/local/bin/securewave-vpn-routing
    EGRESS_IFACE="${IKEV2_INTERFACE}" \
    IKEV2_CIDR="${IKEV2_POOL_CIDR}" \
      /usr/local/bin/securewave-vpn-routing setup ikev2
  else
    echo "[warn] securewave-vpn-routing not found; NAT not configured" >&2
  fi
fi

sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw allow 500/udp comment 'SecureWave IKEv2 ISAKMP'
ufw allow 4500/udp comment 'SecureWave IKEv2 NAT-T'

cat > /usr/local/bin/securewave-ikev2-issue-client <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CN=""
TOKEN=""
VALID_DAYS="30"
SERVER_HOST=""
REMOTE_ID=""
OUTPUT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --common-name) CN="$2"; shift 2 ;;
    --provisioning-token) TOKEN="$2"; shift 2 ;;
    --valid-days) VALID_DAYS="$2"; shift 2 ;;
    --server) SERVER_HOST="$2"; shift 2 ;;
    --remote-id) REMOTE_ID="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "unknown_arg:$1" >&2; exit 2 ;;
  esac
done

if [[ -z "${CN}" || -z "${TOKEN}" || -z "${SERVER_HOST}" ]]; then
  echo "missing_required_argument" >&2
  exit 3
fi
if [[ ! "${CN}" =~ ^[A-Za-z0-9._-]{6,96}$ ]]; then
  echo "invalid_common_name" >&2
  exit 4
fi

/usr/local/bin/securewave-validate-provisioning-token --token "${TOKEN}" --subject "${CN}" --protocol ikev2 >/dev/null

CA_DIR="/etc/securewave/secrets/ikev2/ca"
OPENSSL_CNF="${CA_DIR}/openssl.cnf"
CLIENT_DIR="/etc/securewave/secrets/ikev2/clients/${CN}"
mkdir -p "${CLIENT_DIR}"
chmod 700 "${CLIENT_DIR}"

CLIENT_KEY="${CLIENT_DIR}/client-key.pem"
CLIENT_CSR="${CA_DIR}/csr/${CN}.csr.pem"
CLIENT_CERT="${CLIENT_DIR}/client-cert.pem"
CLIENT_P12="${CLIENT_DIR}/client.p12"
CA_CERT="${CA_DIR}/ca-cert.pem"

if [[ ! -f "${CLIENT_KEY}" ]]; then
  openssl genrsa -out "${CLIENT_KEY}" 4096
  chmod 600 "${CLIENT_KEY}"
fi
if [[ ! -f "${CLIENT_CERT}" ]]; then
  openssl req -new -key "${CLIENT_KEY}" -out "${CLIENT_CSR}" -subj "/CN=${CN}"
  openssl ca -batch -config "${OPENSSL_CNF}" -days "${VALID_DAYS}" -notext -in "${CLIENT_CSR}" -out "${CLIENT_CERT}"
  chmod 644 "${CLIENT_CERT}"
fi

P12_PASSWORD="$(openssl rand -base64 24 | tr -d '\n=+' | cut -c1-24)"
openssl pkcs12 -export -inkey "${CLIENT_KEY}" -in "${CLIENT_CERT}" -certfile "${CA_CERT}" \
  -out "${CLIENT_P12}" -passout pass:"${P12_PASSWORD}" -name "SecureWave ${CN}"
chmod 600 "${CLIENT_P12}"

SERIAL="$(openssl x509 -in "${CLIENT_CERT}" -noout -serial | cut -d= -f2)"
FINGERPRINT="$(openssl x509 -in "${CLIENT_CERT}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d :)"
EXPIRES_AT="$(python3 - <<PY
from datetime import datetime, timezone
import subprocess
raw = subprocess.check_output(["openssl", "x509", "-in", "${CLIENT_CERT}", "-noout", "-enddate"], text=True).strip().split("=", 1)[1]
dt = datetime.strptime(raw, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
print(dt.isoformat().replace("+00:00", "Z"))
PY
)"

P12_B64="$(base64 -w 0 "${CLIENT_P12}")"
CA_B64="$(base64 -w 0 "${CA_CERT}")"

if [[ "${OUTPUT}" != "json" ]]; then
  echo "unsupported_output_format" >&2
  exit 5
fi

jq -n \
  --arg server "${SERVER_HOST}" \
  --arg remote_id "${REMOTE_ID}" \
  --arg client_pkcs12_b64 "${P12_B64}" \
  --arg client_pkcs12_password "${P12_PASSWORD}" \
  --arg ca_cert_pem_b64 "${CA_B64}" \
  --arg cert_serial "${SERIAL}" \
  --arg fingerprint_sha256 "${FINGERPRINT}" \
  --arg expires_at "${EXPIRES_AT}" \
  '{server:$server,remote_id:$remote_id,client_pkcs12_b64:$client_pkcs12_b64,client_pkcs12_password:$client_pkcs12_password,ca_cert_pem_b64:$ca_cert_pem_b64,cert_serial:$cert_serial,fingerprint_sha256:$fingerprint_sha256,expires_at:$expires_at}'
SCRIPT
chmod 700 /usr/local/bin/securewave-ikev2-issue-client

cat > /usr/local/bin/securewave-ikev2-revoke-client <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --common-name) CN="$2"; shift 2 ;;
    *) echo "unknown_arg:$1" >&2; exit 2 ;;
  esac
done

if [[ -z "${CN}" ]]; then
  echo "missing_common_name" >&2
  exit 3
fi

CA_DIR="/etc/securewave/secrets/ikev2/ca"
OPENSSL_CNF="${CA_DIR}/openssl.cnf"
CLIENT_CERT="/etc/securewave/secrets/ikev2/clients/${CN}/client-cert.pem"

if [[ -f "${CLIENT_CERT}" ]]; then
  openssl ca -config "${OPENSSL_CNF}" -revoke "${CLIENT_CERT}" >/dev/null 2>&1 || true
fi
openssl ca -gencrl -config "${OPENSSL_CNF}" -out "${CA_DIR}/ca-crl.pem" >/dev/null 2>&1 || true
cp -f "${CA_DIR}/ca-crl.pem" /etc/ipsec.d/crls/securewave-ikev2-ca-crl.pem || true

if systemctl list-unit-files | grep -q '^strongswan-starter'; then
  systemctl restart strongswan-starter
else
  systemctl restart strongswan
fi

echo "revoked"
SCRIPT
chmod 700 /usr/local/bin/securewave-ikev2-revoke-client

if systemctl list-unit-files | grep -q '^strongswan-starter'; then
  systemctl enable --now strongswan-starter
  systemctl restart strongswan-starter
else
  systemctl enable --now strongswan
  systemctl restart strongswan
fi

ufw --force reload || true

echo "IKEv2/IPsec provisioned successfully."
echo "- Identity: ${IKEV2_SERVER_IDENTITY}"
echo "- Client pool: ${IKEV2_POOL_CIDR}"
echo "- Secrets: /etc/securewave/secrets/ikev2 (root-only)"
echo "- Issue script: /usr/local/bin/securewave-ikev2-issue-client"
echo "- Revoke script: /usr/local/bin/securewave-ikev2-revoke-client"
echo "IMPORTANT: Configure Hetzner firewall to allow UDP 500 and UDP 4500 only from required sources, plus existing HTTPS/WireGuard ports."
