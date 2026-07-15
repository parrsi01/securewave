#!/usr/bin/env bash
# Explicit-host OpenVPN provisioning. Private keys are generated only here.
set -euo pipefail
ROOT=/etc/securewave/openvpn
PKI=${ROOT}/pki
CONF=/etc/openvpn/server/securewave.conf
DB=${ROOT}/credentials.db
CA=${PKI}/ca.crt
CA_KEY=${PKI}/ca.key
CERT=${PKI}/server.crt
KEY=${PKI}/server.key
AUTH=/usr/local/libexec/securewave-openvpn-auth
CRED=/usr/local/libexec/securewave-openvpn-credential
HEALTH=/usr/local/libexec/securewave-openvpn-health
NAT=/usr/local/libexec/securewave-openvpn-nat
SERVICE=openvpn-server@securewave.service
host=; port=1194; transport=udp; dns=94.140.14.14
admin_user="${SECUREWAVE_SERVER_ADMIN:-securewave}"

while (($#)); do
  case "$1" in
    --public-host) host="${2:-}"; shift 2 ;;
    --port) port="${2:-}"; shift 2 ;;
    --transport) transport="${2:-}"; shift 2 ;;
    --dns) dns="${2:-}"; shift 2 ;;
    --print-ca) test -r "$CA" && cat "$CA"; exit $? ;;
    *) echo "Usage: $0 --public-host HOST [--port PORT] [--transport udp|tcp] [--dns IPv4]" >&2; exit 64 ;;
  esac
done
[[ ${EUID} -eq 0 && "$host" =~ ^[A-Za-z0-9:.-]{1,253}$ && "$port" =~ ^[0-9]+$ ]] || exit 64
((port > 0 && port < 65536)) && [[ "$transport" =~ ^(udp|tcp)$ && "$dns" =~ ^[0-9.]+$ ]] || exit 64

apt-get update
apt-get install -y --no-install-recommends openvpn openssl iptables ufw
id "$admin_user" >/dev/null 2>&1 || { echo "Configured server admin does not exist." >&2; exit 1; }
getent group securewave-ovpn >/dev/null || groupadd --system securewave-ovpn
id -u securewave-ovpn >/dev/null 2>&1 || useradd --system --no-create-home --gid securewave-ovpn --shell /usr/sbin/nologin securewave-ovpn
install -d -m 0750 -o root -g securewave-ovpn "$ROOT"
install -d -m 0700 "$PKI"
install -d -m 0755 /etc/openvpn/server /usr/local/libexec
touch "$DB"; chown root:securewave-ovpn "$DB"; chmod 0640 "$DB"
if [[ ! -s "$CA" ]]; then
  openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 3650 -keyout "$CA_KEY" -out "$CA" -subj /CN=SecureWave-OpenVPN-CA
  chmod 0600 "$CA_KEY"
fi
if [[ ! -s "$CERT" ]]; then
  temp_dir="$(mktemp -d)"; trap 'rm -rf "$temp_dir"' EXIT
  openssl req -newkey rsa:3072 -nodes -sha256 -keyout "$KEY" -out "$PKI/server.csr" -subj "/CN=$host"
  openssl x509 -req -in "$PKI/server.csr" -CA "$CA" -CAkey "$CA_KEY" -CAcreateserial -out "$CERT" -days 825 -sha256 -extfile <(printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:%s\n' "$host")
  rm -f "$PKI/server.csr"
  chmod 0600 "$KEY"
fi

cat >"$AUTH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DB=/etc/securewave/openvpn/credentials.db
file="${1:-}"
[[ -f "$file" && ! -L "$file" ]] || exit 1
mapfile -t lines <"$file"
user="${lines[0]:-}"; credential_input="${lines[1]:-}"
[[ "$user" =~ ^swovpn-[a-f0-9]{32}$ && "$credential_input" =~ ^[A-Za-z0-9_-]{16,256}$ ]] || exit 1
row="$(awk -F'|' -v user="$user" '$1 == user { print; exit }' "$DB")"
[[ -n "$row" ]] || exit 1
IFS='|' read -r stored salt hash expiry <<<"$row"
[[ "$stored" == "$user" && "$expiry" =~ ^[0-9]+$ && "$expiry" -gt "$(date +%s)" ]] || exit 1
[[ "$(printf '%s' "${salt}${credential_input}" | sha256sum | awk '{print $1}')" == "$hash" ]] || exit 1
EOF
chmod 0700 "$AUTH"

cat >"$CRED" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DB=/etc/securewave/openvpn/credentials.db
op="${1:-}"; user="${2:-}"
[[ "$user" =~ ^swovpn-[a-f0-9]{32}$ ]] || exit 64
case "$op" in
  upsert) salt="${3:-}"; hash="${4:-}"; expiry="${5:-}"; [[ "$salt" =~ ^[a-f0-9]{64}$ && "$hash" =~ ^[a-f0-9]{64}$ && "$expiry" =~ ^[0-9]+$ ]] || exit 64; (( expiry > $(date +%s) && expiry < 4102444800 )) || exit 64 ;;
  revoke) [[ $# -eq 2 ]] || exit 64 ;;
  *) exit 64 ;;
esac
exec 9>/etc/securewave/openvpn/credentials.lock; flock -x 9
temp="$(mktemp "${DB}.XXXXXX")"; chmod 0600 "$temp"
awk -F'|' -v user="$user" '$1 != user { print }' "$DB" >"$temp"
[[ "$op" == upsert ]] && printf '%s|%s|%s|%s\n' "$user" "$salt" "$hash" "$expiry" >>"$temp"
mv -f "$temp" "$DB"; chown root:securewave-ovpn "$DB"; chmod 0640 "$DB"; echo OK
EOF
chmod 0700 "$CRED"

cat >"$NAT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CHAIN4=SECUREWAVE_OPENVPN_FORWARD; CHAIN6=SECUREWAVE_OPENVPN6_FORWARD; TAG4=securewave-openvpn-v4-v1; TAG6=securewave-openvpn-v6-v1; SUBNET4=10.66.0.0/24; SUBNET6=fd53:6563:7572:6577::/64; TUN=tun-securewave-server
cleanup() { while iptables -t nat -D POSTROUTING -s "$SUBNET4" -m comment --comment "$TAG4" -j MASQUERADE >/dev/null 2>&1; do :; done; iptables -D FORWARD -j "$CHAIN4" >/dev/null 2>&1 || true; iptables -F "$CHAIN4" >/dev/null 2>&1 || true; iptables -X "$CHAIN4" >/dev/null 2>&1 || true; while ip6tables -t nat -D POSTROUTING -s "$SUBNET6" -m comment --comment "$TAG6" -j MASQUERADE >/dev/null 2>&1; do :; done; ip6tables -D FORWARD -j "$CHAIN6" >/dev/null 2>&1 || true; ip6tables -F "$CHAIN6" >/dev/null 2>&1 || true; ip6tables -X "$CHAIN6" >/dev/null 2>&1 || true; }
case "${1:-}" in
  ensure) cleanup; trap cleanup ERR; dev="$(ip route show default | awk 'NR==1 {print $5}')"; [[ "$dev" =~ ^[A-Za-z0-9_.:-]+$ ]] || exit 1; iptables -N "$CHAIN4"; iptables -A "$CHAIN4" -i "$TUN" -o "$dev" -j ACCEPT; iptables -A "$CHAIN4" -i "$dev" -o "$TUN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; iptables -I FORWARD 1 -j "$CHAIN4"; iptables -t nat -A POSTROUTING -s "$SUBNET4" -o "$dev" -m comment --comment "$TAG4" -j MASQUERADE; dev6="$(ip -6 route show default | awk 'NR==1 {print $5}')"; if [[ "$dev6" =~ ^[A-Za-z0-9_.:-]+$ ]]; then ip6tables -N "$CHAIN6"; ip6tables -A "$CHAIN6" -i "$TUN" -o "$dev6" -j ACCEPT; ip6tables -A "$CHAIN6" -i "$dev6" -o "$TUN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT; ip6tables -I FORWARD 1 -j "$CHAIN6"; ip6tables -t nat -A POSTROUTING -s "$SUBNET6" -o "$dev6" -m comment --comment "$TAG6" -j MASQUERADE; fi; trap - ERR ;;
  cleanup) cleanup ;;
  *) exit 64 ;;
esac
EOF
chmod 0700 "$NAT"

proto=udp; socket_probe="ss -H -lun"; [[ "$transport" == tcp ]] && { proto=tcp-server; socket_probe="ss -H -ltn"; }
cat >"$CONF" <<EOF
port $port
proto $proto
dev tun-securewave-server
topology subnet
server 10.66.0.0 255.255.255.0
server-ipv6 fd53:6563:7572:6577::/64
ca $CA
cert $CERT
key $KEY
dh none
tls-version-min 1.2
data-ciphers AES-256-GCM:AES-128-GCM
user securewave-ovpn
group securewave-ovpn
verify-client-cert none
username-as-common-name
auth-user-pass-verify $AUTH via-file
script-security 2
push "redirect-gateway def1"
push "route-ipv6 2000::/3"
push "dhcp-option DNS $dns"
EOF
chmod 0600 "$CONF"

cat >"$HEALTH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
systemctl is-active --quiet $SERVICE
test -s $CA && test -s $CERT && test -s $KEY
test -x $AUTH && test -x $CRED
$socket_probe | awk '{print \$5}' | grep -Eq '[:.]$port$'
echo OK
EOF
chmod 0700 "$HEALTH"
install -m 0440 /dev/stdin "/etc/sudoers.d/securewave-openvpn" <<EOF
$admin_user ALL=(root) NOPASSWD: $HEALTH, $CRED *
EOF
printf 'net.ipv4.ip_forward=1\nnet.ipv6.conf.all.forwarding=1\n' >/etc/sysctl.d/99-securewave-openvpn.conf
sysctl --system >/dev/null
cat >/etc/systemd/system/securewave-openvpn-nat.service <<EOF
[Unit]
Description=SecureWave OpenVPN owned forwarding rules
After=network-online.target $SERVICE
Requires=$SERVICE
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$NAT ensure
ExecStop=$NAT cleanup
[Install]
WantedBy=multi-user.target
EOF
ufw allow "$port/$transport" >/dev/null
systemctl daemon-reload
systemctl enable --now $SERVICE securewave-openvpn-nat.service
"$HEALTH" >/dev/null
echo "OpenVPN runtime provisioned. Retrieve only its public CA with: $0 --print-ca"
