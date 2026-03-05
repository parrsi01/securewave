#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
umask 077

install -d -m 755 /etc/securewave/openvpn /etc/securewave/ikev2
install -d -m 700 /var/lib/securewave/pki /var/lib/securewave/pki/openvpn /var/lib/securewave/pki/ikev2

sync_clock_if_possible() {
  timedatectl set-ntp true >/dev/null 2>&1 || true
  systemctl restart systemd-timesyncd >/dev/null 2>&1 || true
  sleep 3
}

apt_update_with_retry() {
  local attempt=1
  while [[ "${attempt}" -le 3 ]]; do
    if apt-get update -y; then
      return 0
    fi
    echo "apt-get update failed (attempt ${attempt}/3); syncing clock and retrying..." >&2
    sync_clock_if_possible
    attempt=$((attempt + 1))
  done
  echo "apt-get update failed after retries." >&2
  return 1
}

sync_clock_if_possible
apt_update_with_retry
apt-get install -y openvpn easy-rsa strongswan strongswan-pki jq openssl python3

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


def _b64u_decode(value: str) -> bytes:
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
        body, signature = args.token.split(".", 1)
    except ValueError:
        print("invalid_token_format", file=sys.stderr)
        return 3

    expected = hmac.new(secret.encode("utf-8"), body.encode("ascii"), hashlib.sha256).digest()
    try:
        actual = _b64u_decode(signature)
    except Exception:
        print("invalid_token_signature_encoding", file=sys.stderr)
        return 4

    if not hmac.compare_digest(expected, actual):
        print("invalid_token_signature", file=sys.stderr)
        return 5

    try:
        payload = json.loads(_b64u_decode(body).decode("utf-8"))
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

cat > /usr/local/bin/securewave-openvpn-upsert-user <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

USERNAME=""
PASSWORD_B64=""
OUTPUT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2 ;;
    --password-b64) PASSWORD_B64="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "unknown_arg:$1" >&2; exit 2 ;;
  esac
done

if [[ "${OUTPUT}" != "json" ]]; then
  echo "unsupported_output_format" >&2
  exit 3
fi
if [[ -z "${USERNAME}" || -z "${PASSWORD_B64}" ]]; then
  jq -n --arg code "openvpn_invalid_input" --arg message "username and password-b64 are required" \
    '{ok:false,code:$code,message:$message,artifact_path:null}'
  exit 4
fi
if [[ ! "${USERNAME}" =~ ^[A-Za-z0-9._@-]{3,96}$ ]]; then
  jq -n --arg code "openvpn_invalid_username" --arg message "invalid username" \
    '{ok:false,code:$code,message:$message,artifact_path:null}'
  exit 5
fi

DB_FILE="/etc/securewave/openvpn/users.db"
LOCK_FILE="/var/lib/securewave/pki/openvpn/.users.lock"
install -d -m 700 /var/lib/securewave/pki/openvpn
touch "${DB_FILE}"
chmod 600 "${DB_FILE}"

exec 9>"${LOCK_FILE}"
flock -w 20 9

tmp="$(mktemp)"
if [[ -s "${DB_FILE}" ]]; then
  grep -v "^${USERNAME}:" "${DB_FILE}" > "${tmp}" || true
fi
printf "%s:%s\n" "${USERNAME}" "${PASSWORD_B64}" >> "${tmp}"
install -m 600 "${tmp}" "${DB_FILE}"
rm -f "${tmp}"

jq -n --arg code "openvpn_user_upserted" --arg message "user credential record stored" --arg artifact_path "${DB_FILE}" \
  '{ok:true,code:$code,message:$message,artifact_path:$artifact_path}'
SCRIPT
chmod 700 /usr/local/bin/securewave-openvpn-upsert-user

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

json_fail() {
  jq -n --arg code "$1" --arg message "$2" '{ok:false,code:$code,message:$message,artifact_path:null}'
}

if [[ "${OUTPUT}" != "json" ]]; then
  echo "unsupported_output_format" >&2
  exit 3
fi
if [[ -z "${CN}" || -z "${TOKEN}" ]]; then
  json_fail "openvpn_invalid_input" "common-name and provisioning-token are required"
  exit 4
fi
if [[ ! "${CN}" =~ ^[A-Za-z0-9._-]{6,96}$ ]]; then
  json_fail "openvpn_invalid_common_name" "invalid common-name format"
  exit 5
fi
if ! /usr/local/bin/securewave-validate-provisioning-token --token "${TOKEN}" --subject "${CN}" --protocol openvpn >/dev/null 2>&1; then
  json_fail "openvpn_invalid_token" "invalid or expired provisioning token"
  exit 7
fi

LOCK_FILE="/var/lib/securewave/pki/openvpn/.issue.lock"
exec 9>"${LOCK_FILE}"
flock -w 30 9

CA_CERT=""
for p in /etc/openvpn/server/ca.crt /etc/openvpn/easy-rsa/ca.crt /etc/securewave/secrets/openvpn/easy-rsa/pki/ca.crt; do
  if [[ -f "${p}" ]]; then
    CA_CERT="${p}"
    break
  fi
done

CA_KEY=""
for p in /etc/openvpn/easy-rsa/ca.key /etc/openvpn/pki/ca.key /etc/securewave/secrets/openvpn/easy-rsa/pki/private/ca.key; do
  if [[ -f "${p}" ]]; then
    CA_KEY="${p}"
    break
  fi
done

TLS_CRYPT=""
for p in /etc/openvpn/server/tls-crypt.key /etc/securewave/secrets/openvpn/tls-crypt.key; do
  if [[ -f "${p}" ]]; then
    TLS_CRYPT="${p}"
    break
  fi
done

if [[ -z "${CA_CERT}" || -z "${CA_KEY}" ]]; then
  json_fail "openvpn_server_misconfigured" "OpenVPN CA material is missing"
  exit 6
fi

PORT="$(awk '/^port[[:space:]]+[0-9]+/ {print $2; exit}' /etc/openvpn/server/server.conf 2>/dev/null || true)"
if [[ -z "${PORT}" ]]; then
  PORT="$(awk '/^port[[:space:]]+[0-9]+/ {print $2; exit}' /etc/openvpn/server/securewave.conf 2>/dev/null || true)"
fi
if [[ -z "${PORT}" ]]; then
  PORT="1194"
fi

REMOTE_HOST="${OPENVPN_SERVER_PUBLIC_HOST:-}"
if [[ -z "${REMOTE_HOST}" ]]; then
  REMOTE_HOST="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')"
fi
if [[ -z "${REMOTE_HOST}" ]]; then
  REMOTE_HOST="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
fi
if [[ -z "${REMOTE_HOST}" ]]; then
  REMOTE_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
if [[ -z "${REMOTE_HOST}" ]]; then
  REMOTE_HOST="$(hostname -f 2>/dev/null || hostname)"
fi

BASE_DIR="/var/lib/securewave/pki/openvpn/${CN}"
install -d -m 700 "${BASE_DIR}"
CLIENT_KEY="${BASE_DIR}/client.key"
CLIENT_CSR="${BASE_DIR}/client.csr"
CLIENT_CERT="${BASE_DIR}/client.crt"
OVPN_FILE="${BASE_DIR}/client.ovpn"
ARTIFACT_FILE="${BASE_DIR}/payload.json"

if [[ ! -f "${CLIENT_KEY}" ]]; then
  openssl genrsa -out "${CLIENT_KEY}" 2048 >/dev/null 2>&1
  chmod 600 "${CLIENT_KEY}"
fi

if [[ ! -f "${CLIENT_CERT}" ]]; then
  openssl req -new -key "${CLIENT_KEY}" -subj "/CN=${CN}" -out "${CLIENT_CSR}" >/dev/null 2>&1
  openssl x509 -req -in "${CLIENT_CSR}" -CA "${CA_CERT}" -CAkey "${CA_KEY}" -CAcreateserial \
    -out "${CLIENT_CERT}" -days "${VALID_DAYS}" -sha256 >/dev/null 2>&1
  chmod 644 "${CLIENT_CERT}"
fi

SERIAL="$(openssl x509 -in "${CLIENT_CERT}" -noout -serial | cut -d= -f2)"
FINGERPRINT="$(openssl x509 -in "${CLIENT_CERT}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')"
EXPIRES_AT="$(python3 - <<PY
from datetime import datetime, timezone
import subprocess
raw = subprocess.check_output(["openssl", "x509", "-in", "${CLIENT_CERT}", "-noout", "-enddate"], text=True).strip().split("=", 1)[1]
dt = datetime.strptime(raw, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
print(dt.isoformat().replace("+00:00", "Z"))
PY
)"

cat > "${OVPN_FILE}" <<CONF
client
dev tun
proto udp
remote ${REMOTE_HOST} ${PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
verb 3
<ca>
$(cat "${CA_CERT}")
</ca>
<cert>
$(cat "${CLIENT_CERT}")
</cert>
<key>
$(cat "${CLIENT_KEY}")
</key>
CONF

if [[ -n "${TLS_CRYPT}" ]]; then
  cat >> "${OVPN_FILE}" <<CONF
<tls-crypt>
$(cat "${TLS_CRYPT}")
</tls-crypt>
CONF
fi

OVPN_B64="$(base64 -w 0 "${OVPN_FILE}")"
jq -n \
  --arg ovpn_config_b64 "${OVPN_B64}" \
  --arg cert_serial "${SERIAL}" \
  --arg fingerprint_sha256 "${FINGERPRINT}" \
  --arg expires_at "${EXPIRES_AT}" \
  '{ovpn_config_b64:$ovpn_config_b64,cert_serial:$cert_serial,fingerprint_sha256:$fingerprint_sha256,expires_at:$expires_at}' > "${ARTIFACT_FILE}"
chmod 600 "${ARTIFACT_FILE}"

jq -n \
  --arg code "openvpn_profile_issued" \
  --arg message "OpenVPN profile artifact generated" \
  --arg artifact_path "${ARTIFACT_FILE}" \
  '{ok:true,code:$code,message:$message,artifact_path:$artifact_path}'
SCRIPT
chmod 700 /usr/local/bin/securewave-openvpn-issue-client

cat > /usr/local/bin/securewave-openvpn-revoke-client <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CN=""
OUTPUT="json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --common-name) CN="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "unknown_arg:$1" >&2; exit 2 ;;
  esac
done

if [[ "${OUTPUT}" != "json" ]]; then
  echo "unsupported_output_format" >&2
  exit 3
fi
if [[ -z "${CN}" ]]; then
  jq -n --arg code "openvpn_invalid_input" --arg message "common-name is required" \
    '{ok:false,code:$code,message:$message,artifact_path:null}'
  exit 4
fi

LOCK_FILE="/var/lib/securewave/pki/openvpn/.issue.lock"
exec 9>"${LOCK_FILE}"
flock -w 20 9

BASE_DIR="/var/lib/securewave/pki/openvpn/${CN}"
ARTIFACT_FILE="${BASE_DIR}/payload.json"

if [[ -d "${BASE_DIR}" ]]; then
  rm -f "${BASE_DIR}/client.key" "${BASE_DIR}/client.csr" "${BASE_DIR}/client.crt" "${BASE_DIR}/client.ovpn" "${ARTIFACT_FILE}"
  rmdir "${BASE_DIR}" 2>/dev/null || true
  jq -n --arg code "openvpn_client_revoked" --arg message "OpenVPN client material removed" \
    '{ok:true,code:$code,message:$message,artifact_path:null}'
  exit 0
fi

jq -n --arg code "openvpn_client_not_found" --arg message "No OpenVPN client material found for common-name" \
  '{ok:true,code:$code,message:$message,artifact_path:null}'
SCRIPT
chmod 700 /usr/local/bin/securewave-openvpn-revoke-client

cat > /usr/local/bin/securewave-ikev2-upsert-user <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

USERNAME=""
PASSWORD_B64=""
OUTPUT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username) USERNAME="$2"; shift 2 ;;
    --password-b64) PASSWORD_B64="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "unknown_arg:$1" >&2; exit 2 ;;
  esac
done

if [[ "${OUTPUT}" != "json" ]]; then
  echo "unsupported_output_format" >&2
  exit 3
fi
if [[ -z "${USERNAME}" || -z "${PASSWORD_B64}" ]]; then
  jq -n --arg code "ikev2_invalid_input" --arg message "username and password-b64 are required" \
    '{ok:false,code:$code,message:$message,artifact_path:null}'
  exit 4
fi
if [[ ! "${USERNAME}" =~ ^[A-Za-z0-9._@-]{3,96}$ ]]; then
  jq -n --arg code "ikev2_invalid_username" --arg message "invalid username" \
    '{ok:false,code:$code,message:$message,artifact_path:null}'
  exit 5
fi

PASSWORD="$(python3 - <<PY
import base64
print(base64.b64decode("${PASSWORD_B64}".encode("ascii")).decode("utf-8"))
PY
)"

SECRETS_FILE="/etc/ipsec.secrets"
LOCK_FILE="/var/lib/securewave/pki/ikev2/.users.lock"
touch "${SECRETS_FILE}"
chmod 600 "${SECRETS_FILE}"

exec 9>"${LOCK_FILE}"
flock -w 20 9

python3 - "${SECRETS_FILE}" "${USERNAME}" "${PASSWORD}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
username = sys.argv[2]
password = sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
out = []
prefix = f"{username} : EAP "
for line in lines:
    stripped = line.strip()
    if stripped.startswith(prefix):
        continue
    out.append(line)
out.append(f'{username} : EAP "{password}"')
path.write_text("\n".join(out).strip() + "\n", encoding="utf-8")
PY
chmod 600 "${SECRETS_FILE}"

ipsec rereadsecrets >/dev/null 2>&1 || true

jq -n --arg code "ikev2_user_upserted" --arg message "IKEv2 EAP user updated" --arg artifact_path "${SECRETS_FILE}" \
  '{ok:true,code:$code,message:$message,artifact_path:$artifact_path}'
SCRIPT
chmod 700 /usr/local/bin/securewave-ikev2-upsert-user

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

json_fail() {
  jq -n --arg code "$1" --arg message "$2" '{ok:false,code:$code,message:$message,artifact_path:null}'
}

if [[ "${OUTPUT}" != "json" ]]; then
  echo "unsupported_output_format" >&2
  exit 3
fi
if [[ -z "${CN}" || -z "${TOKEN}" || -z "${SERVER_HOST}" ]]; then
  json_fail "ikev2_invalid_input" "common-name, provisioning-token and server are required"
  exit 4
fi
if [[ ! "${CN}" =~ ^[A-Za-z0-9._-]{6,96}$ ]]; then
  json_fail "ikev2_invalid_common_name" "invalid common-name format"
  exit 5
fi
if ! /usr/local/bin/securewave-validate-provisioning-token --token "${TOKEN}" --subject "${CN}" --protocol ikev2 >/dev/null 2>&1; then
  json_fail "ikev2_invalid_token" "invalid or expired provisioning token"
  exit 7
fi

LOCK_FILE="/var/lib/securewave/pki/ikev2/.issue.lock"
exec 9>"${LOCK_FILE}"
flock -w 30 9

CA_CERT=""
for p in /etc/ipsec.d/cacerts/ca-cert.pem /etc/securewave/secrets/ikev2/ca/ca-cert.pem; do
  if [[ -f "${p}" ]]; then
    CA_CERT="${p}"
    break
  fi
done

CA_KEY=""
for p in /etc/ipsec.d/private/ca-key.pem /etc/securewave/secrets/ikev2/ca/ca-key.pem; do
  if [[ -f "${p}" ]]; then
    CA_KEY="${p}"
    break
  fi
done

if [[ -z "${CA_CERT}" || -z "${CA_KEY}" ]]; then
  json_fail "ikev2_server_misconfigured" "IKEv2 CA material is missing"
  exit 6
fi

BASE_DIR="/var/lib/securewave/pki/ikev2/${CN}"
install -d -m 700 "${BASE_DIR}"
CLIENT_KEY="${BASE_DIR}/client-key.pem"
CLIENT_CSR="${BASE_DIR}/client.csr"
CLIENT_CERT="${BASE_DIR}/client-cert.pem"
CLIENT_P12="${BASE_DIR}/client.p12"
ARTIFACT_FILE="${BASE_DIR}/payload.json"

if [[ ! -f "${CLIENT_KEY}" ]]; then
  openssl genrsa -out "${CLIENT_KEY}" 2048 >/dev/null 2>&1
  chmod 600 "${CLIENT_KEY}"
fi
if [[ ! -f "${CLIENT_CERT}" ]]; then
  openssl req -new -key "${CLIENT_KEY}" -subj "/CN=${CN}" -out "${CLIENT_CSR}" >/dev/null 2>&1
  openssl x509 -req -in "${CLIENT_CSR}" -CA "${CA_CERT}" -CAkey "${CA_KEY}" -CAcreateserial \
    -out "${CLIENT_CERT}" -days "${VALID_DAYS}" -sha256 >/dev/null 2>&1
  chmod 644 "${CLIENT_CERT}"
fi

P12_PASSWORD="$(openssl rand -base64 24 | tr -d '\n=+' | cut -c1-24)"
openssl pkcs12 -export -inkey "${CLIENT_KEY}" -in "${CLIENT_CERT}" -certfile "${CA_CERT}" \
  -out "${CLIENT_P12}" -passout pass:"${P12_PASSWORD}" -name "SecureWave ${CN}" >/dev/null 2>&1
chmod 600 "${CLIENT_P12}"

SERIAL="$(openssl x509 -in "${CLIENT_CERT}" -noout -serial | cut -d= -f2)"
FINGERPRINT="$(openssl x509 -in "${CLIENT_CERT}" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')"
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

jq -n \
  --arg server "${SERVER_HOST}" \
  --arg remote_id "${REMOTE_ID}" \
  --arg client_pkcs12_b64 "${P12_B64}" \
  --arg client_pkcs12_password "${P12_PASSWORD}" \
  --arg ca_cert_pem_b64 "${CA_B64}" \
  --arg cert_serial "${SERIAL}" \
  --arg fingerprint_sha256 "${FINGERPRINT}" \
  --arg expires_at "${EXPIRES_AT}" \
  '{server:$server,remote_id:$remote_id,client_pkcs12_b64:$client_pkcs12_b64,client_pkcs12_password:$client_pkcs12_password,ca_cert_pem_b64:$ca_cert_pem_b64,cert_serial:$cert_serial,fingerprint_sha256:$fingerprint_sha256,expires_at:$expires_at}' > "${ARTIFACT_FILE}"
chmod 600 "${ARTIFACT_FILE}"

jq -n \
  --arg code "ikev2_profile_issued" \
  --arg message "IKEv2 profile artifact generated" \
  --arg artifact_path "${ARTIFACT_FILE}" \
  '{ok:true,code:$code,message:$message,artifact_path:$artifact_path}'
SCRIPT
chmod 700 /usr/local/bin/securewave-ikev2-issue-client

cat > /usr/local/bin/securewave-ikev2-revoke-client <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CN=""
OUTPUT="json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --common-name) CN="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "unknown_arg:$1" >&2; exit 2 ;;
  esac
done

if [[ "${OUTPUT}" != "json" ]]; then
  echo "unsupported_output_format" >&2
  exit 3
fi
if [[ -z "${CN}" ]]; then
  jq -n --arg code "ikev2_invalid_input" --arg message "common-name is required" \
    '{ok:false,code:$code,message:$message,artifact_path:null}'
  exit 4
fi

LOCK_FILE="/var/lib/securewave/pki/ikev2/.issue.lock"
exec 9>"${LOCK_FILE}"
flock -w 20 9

SECRETS_FILE="/etc/ipsec.secrets"
if [[ -f "${SECRETS_FILE}" ]]; then
  python3 - "${SECRETS_FILE}" "${CN}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
name = sys.argv[2]
prefix = f"{name} : EAP "
lines = path.read_text(encoding="utf-8").splitlines()
filtered = [line for line in lines if not line.strip().startswith(prefix)]
path.write_text("\n".join(filtered).strip() + "\n", encoding="utf-8")
PY
  chmod 600 "${SECRETS_FILE}"
fi

BASE_DIR="/var/lib/securewave/pki/ikev2/${CN}"
if [[ -d "${BASE_DIR}" ]]; then
  rm -f "${BASE_DIR}/client-key.pem" "${BASE_DIR}/client.csr" "${BASE_DIR}/client-cert.pem" "${BASE_DIR}/client.p12" "${BASE_DIR}/payload.json"
  rmdir "${BASE_DIR}" 2>/dev/null || true
fi

ipsec rereadsecrets >/dev/null 2>&1 || true

jq -n --arg code "ikev2_client_revoked" --arg message "IKEv2 client material removed" \
  '{ok:true,code:$code,message:$message,artifact_path:null}'
SCRIPT
chmod 700 /usr/local/bin/securewave-ikev2-revoke-client

if systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "openvpn-server@server.service"; then
  systemctl enable --now openvpn-server@server
elif systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "openvpn-server@securewave.service"; then
  systemctl enable --now openvpn-server@securewave
elif systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "openvpn@server.service"; then
  systemctl enable --now openvpn@server
fi

if systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "strongswan-starter.service"; then
  systemctl enable --now strongswan-starter
elif systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "strongswan.service"; then
  systemctl enable --now strongswan
elif systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -qx "charon-systemd.service"; then
  systemctl enable --now charon-systemd
fi

echo "SecureWave OpenVPN/IKEv2 helper restore complete."
echo "Installed scripts:"
echo " - /usr/local/bin/securewave-openvpn-issue-client"
echo " - /usr/local/bin/securewave-openvpn-upsert-user"
echo " - /usr/local/bin/securewave-openvpn-revoke-client"
echo " - /usr/local/bin/securewave-ikev2-issue-client"
echo " - /usr/local/bin/securewave-ikev2-upsert-user"
echo " - /usr/local/bin/securewave-ikev2-revoke-client"
