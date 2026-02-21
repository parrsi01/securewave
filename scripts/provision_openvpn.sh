#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

OPENVPN_UDP_PORT="${OPENVPN_UDP_PORT:-1194}"
OPENVPN_ENABLE_TCP_443="${OPENVPN_ENABLE_TCP_443:-0}"
OPENVPN_SERVER_CN="${OPENVPN_SERVER_CN:-securewave-openvpn-server}"
OPENVPN_NETWORK_CIDR="${OPENVPN_NETWORK_CIDR:-10.44.0.0/24}"
OPENVPN_INTERFACE="${OPENVPN_INTERFACE:-$(ip -4 route list default | awk '{print $5; exit}') }"
OPENVPN_DNS_1="${OPENVPN_DNS_1:-94.140.14.14}"
OPENVPN_DNS_2="${OPENVPN_DNS_2:-94.140.15.15}"
OPENVPN_SERVER_PUBLIC_HOST="${OPENVPN_SERVER_PUBLIC_HOST:-$(curl -4s --max-time 3 ifconfig.me || true)}"
OPENVPN_CLIENT_CERT_VALID_DAYS="${OPENVPN_CLIENT_CERT_VALID_DAYS:-30}"

if [[ -z "${OPENVPN_INTERFACE}" ]]; then
  echo "Could not determine egress interface. Set OPENVPN_INTERFACE." >&2
  exit 1
fi

install -d -m 700 /etc/securewave/secrets
install -d -m 700 /etc/securewave/secrets/openvpn
install -d -m 755 /etc/securewave/openvpn
install -d -m 755 /var/lib/securewave/openvpn

apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y openvpn easy-rsa ufw jq openssl python3

TOKEN_SECRET_FILE="/etc/securewave/secrets/provisioning_token_secret"
if [[ ! -s "${TOKEN_SECRET_FILE}" ]]; then
  umask 077
  openssl rand -hex 32 > "${TOKEN_SECRET_FILE}"
  chmod 600 "${TOKEN_SECRET_FILE}"
fi

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

EASYRSA_DIR="/etc/securewave/secrets/openvpn/easy-rsa"
if [[ ! -x "${EASYRSA_DIR}/easyrsa" ]]; then
  cp -a /usr/share/easy-rsa "${EASYRSA_DIR}"
fi
cd "${EASYRSA_DIR}"
chmod 700 "${EASYRSA_DIR}"

if [[ ! -d "${EASYRSA_DIR}/pki" ]]; then
  ./easyrsa --batch init-pki
fi

if [[ ! -f "${EASYRSA_DIR}/pki/ca.crt" ]]; then
  ./easyrsa --batch build-ca nopass
fi

if [[ ! -f "${EASYRSA_DIR}/pki/issued/${OPENVPN_SERVER_CN}.crt" ]]; then
  ./easyrsa --batch build-server-full "${OPENVPN_SERVER_CN}" nopass
fi

if [[ ! -f "${EASYRSA_DIR}/pki/crl.pem" ]]; then
  ./easyrsa --batch gen-crl
fi

if [[ ! -f /etc/securewave/secrets/openvpn/tls-crypt.key ]]; then
  openvpn --genkey secret /etc/securewave/secrets/openvpn/tls-crypt.key
  chmod 600 /etc/securewave/secrets/openvpn/tls-crypt.key
fi

cat > /etc/openvpn/server/securewave.conf <<CONF
port ${OPENVPN_UDP_PORT}
proto udp
dev tun
user nobody
group nogroup
persist-key
persist-tun
topology subnet
server ${OPENVPN_NETWORK_CIDR%/*} 255.255.255.0
ifconfig-pool-persist /var/lib/securewave/openvpn/ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${OPENVPN_DNS_1}"
push "dhcp-option DNS ${OPENVPN_DNS_2}"
keepalive 10 120
tls-crypt /etc/securewave/secrets/openvpn/tls-crypt.key
ca ${EASYRSA_DIR}/pki/ca.crt
cert ${EASYRSA_DIR}/pki/issued/${OPENVPN_SERVER_CN}.crt
key ${EASYRSA_DIR}/pki/private/${OPENVPN_SERVER_CN}.key
crl-verify ${EASYRSA_DIR}/pki/crl.pem
auth SHA256
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM
explicit-exit-notify 1
verb 3
CONF

cat > /etc/sysctl.d/99-securewave-vpn.conf <<SYSCTL
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
SYSCTL
sysctl --system >/dev/null

if ! grep -q "# SECUREWAVE-OPENVPN-NAT-START" /etc/ufw/before.rules; then
  cp /etc/ufw/before.rules /etc/ufw/before.rules.securewave.bak
  awk -v cidr="${OPENVPN_NETWORK_CIDR}" -v iface="${OPENVPN_INTERFACE}" '
    NR==1 {
      print "# SECUREWAVE-OPENVPN-NAT-START"
      print "*nat"
      print ":POSTROUTING ACCEPT [0:0]"
      print "-A POSTROUTING -s " cidr " -o " iface " -j MASQUERADE"
      print "COMMIT"
      print "# SECUREWAVE-OPENVPN-NAT-END"
    }
    {print}
  ' /etc/ufw/before.rules.securewave.bak > /etc/ufw/before.rules
fi

sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw allow "${OPENVPN_UDP_PORT}/udp" comment 'SecureWave OpenVPN UDP'

if [[ "${OPENVPN_ENABLE_TCP_443}" == "1" ]]; then
  if ss -ltn '( sport = :443 )' | tail -n +2 | grep -q .; then
    echo "TCP 443 is already in use (likely HTTPS). Skipping OpenVPN TCP 443 setup." >&2
  else
    cat > /etc/openvpn/server/securewave-tcp443.conf <<CONF
port 443
proto tcp-server
dev tun
user nobody
group nogroup
persist-key
persist-tun
topology subnet
server 10.44.1.0 255.255.255.0
ifconfig-pool-persist /var/lib/securewave/openvpn/ipp-tcp443.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${OPENVPN_DNS_1}"
push "dhcp-option DNS ${OPENVPN_DNS_2}"
keepalive 10 120
tls-crypt /etc/securewave/secrets/openvpn/tls-crypt.key
ca ${EASYRSA_DIR}/pki/ca.crt
cert ${EASYRSA_DIR}/pki/issued/${OPENVPN_SERVER_CN}.crt
key ${EASYRSA_DIR}/pki/private/${OPENVPN_SERVER_CN}.key
crl-verify ${EASYRSA_DIR}/pki/crl.pem
auth SHA256
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM
verb 3
CONF
    ufw allow 443/tcp comment 'SecureWave OpenVPN TCP443'
    systemctl enable --now openvpn-server@securewave-tcp443
  fi
fi

cat > /usr/local/bin/securewave-openvpn-issue-client <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CN=""
TOKEN=""
VALID_DAYS="30"
OUTPUT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --common-name) CN="$2"; shift 2 ;;
    --provisioning-token) TOKEN="$2"; shift 2 ;;
    --valid-days) VALID_DAYS="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "unknown_arg:$1" >&2; exit 2 ;;
  esac
done

if [[ -z "${CN}" || -z "${TOKEN}" ]]; then
  echo "missing_common_name_or_token" >&2
  exit 3
fi
if [[ ! "${CN}" =~ ^[A-Za-z0-9._-]{6,96}$ ]]; then
  echo "invalid_common_name" >&2
  exit 4
fi

/usr/local/bin/securewave-validate-provisioning-token --token "${TOKEN}" --subject "${CN}" --protocol openvpn >/dev/null

EASYRSA_DIR="/etc/securewave/secrets/openvpn/easy-rsa"
cd "${EASYRSA_DIR}"
if [[ ! -f "${EASYRSA_DIR}/pki/issued/${CN}.crt" ]]; then
  ./easyrsa --batch build-client-full "${CN}" nopass
fi

CERT_PATH="${EASYRSA_DIR}/pki/issued/${CN}.crt"
KEY_PATH="${EASYRSA_DIR}/pki/private/${CN}.key"
CA_PATH="${EASYRSA_DIR}/pki/ca.crt"
TLS_CRYPT_PATH="/etc/securewave/secrets/openvpn/tls-crypt.key"

SERIAL="$(openssl x509 -in "${CERT_PATH}" -noout -serial | cut -d= -f2)"
FINGERPRINT="$(openssl x509 -in "${CERT_PATH}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d :)"
EXPIRES_AT="$(python3 - <<PY
from datetime import datetime, timezone
import subprocess
raw = subprocess.check_output(["openssl", "x509", "-in", "${CERT_PATH}", "-noout", "-enddate"], text=True).strip().split("=", 1)[1]
dt = datetime.strptime(raw, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
print(dt.isoformat().replace("+00:00", "Z"))
PY
)"

REMOTE_HOST="${OPENVPN_SERVER_PUBLIC_HOST:-}"
if [[ -z "${REMOTE_HOST}" ]]; then
  REMOTE_HOST="$(hostname -f 2>/dev/null || hostname)"
fi

OVPN_FILE="$(mktemp)"
cat > "${OVPN_FILE}" <<CONF
client
dev tun
proto udp
remote ${REMOTE_HOST} ${OPENVPN_UDP_PORT:-1194}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
verb 3
<ca>
$(cat "${CA_PATH}")
</ca>
<cert>
$(cat "${CERT_PATH}")
</cert>
<key>
$(cat "${KEY_PATH}")
</key>
<tls-crypt>
$(cat "${TLS_CRYPT_PATH}")
</tls-crypt>
CONF

OVPN_B64="$(base64 -w 0 "${OVPN_FILE}")"
rm -f "${OVPN_FILE}"

if [[ "${OUTPUT}" != "json" ]]; then
  echo "unsupported_output_format" >&2
  exit 5
fi

jq -n \
  --arg ovpn_config_b64 "${OVPN_B64}" \
  --arg cert_serial "${SERIAL}" \
  --arg fingerprint_sha256 "${FINGERPRINT}" \
  --arg expires_at "${EXPIRES_AT}" \
  '{ovpn_config_b64:$ovpn_config_b64,cert_serial:$cert_serial,fingerprint_sha256:$fingerprint_sha256,expires_at:$expires_at}'
SCRIPT
chmod 700 /usr/local/bin/securewave-openvpn-issue-client

cat > /usr/local/bin/securewave-openvpn-revoke-client <<'SCRIPT'
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

EASYRSA_DIR="/etc/securewave/secrets/openvpn/easy-rsa"
cd "${EASYRSA_DIR}"
if [[ -f "${EASYRSA_DIR}/pki/issued/${CN}.crt" ]]; then
  ./easyrsa --batch revoke "${CN}" || true
  ./easyrsa --batch gen-crl
fi

systemctl restart openvpn-server@securewave
echo "revoked"
SCRIPT
chmod 700 /usr/local/bin/securewave-openvpn-revoke-client

systemctl enable --now openvpn-server@securewave
ufw --force reload || true

echo "OpenVPN provisioned successfully."
echo "- UDP port: ${OPENVPN_UDP_PORT}"
echo "- Secrets: /etc/securewave/secrets/openvpn (root-only)"
echo "- Issue script: /usr/local/bin/securewave-openvpn-issue-client"
echo "- Revoke script: /usr/local/bin/securewave-openvpn-revoke-client"
echo "IMPORTANT: Configure Hetzner firewall to allow UDP ${OPENVPN_UDP_PORT} only from required sources, plus existing HTTPS/WireGuard ports."
