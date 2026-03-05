# SecureWave VPN Test Lab — 2-VPS Isolation Runbook

> **Goal**: Isolated VPN testing lab. Dev machine never touches VPN routing.
> **Date**: 2026-03-02 | **Author**: infrastructure audit

---

## Architecture

```
┌─────────────────┐         ┌─────────────────────────────────┐
│  Dev Machine     │  SSH    │  VPS #1 — 138.199.204.139       │
│  (never routed   │────────▶│  SecureWave backend + VPN server │
│   through VPN)   │         │  WG:51820 OVPN:1194 IKEv2:500   │
└─────────────────┘         └──────────┬──────────────────────┘
                                       │ VPN tunnels
                            ┌──────────▼──────────────────────┐
                            │  VPS #2 — <CLIENT_IP>            │
                            │  Dedicated VPN client test box    │
                            │  Tests WG/OVPN/IKEv2 full tunnel │
                            └──────────────────────────────────┘
```

**Safety**: Your dev machine connects to VPS #1 and VPS #2 via SSH only.
All VPN tunnels run exclusively between VPS #2 → VPS #1.

---

## SECTION 1 — Server Hardening & NAT Validation (VPS #1)

### 1.1 Verify Prerequisites

```bash
# SSH to VPS #1
ssh root@138.199.204.139

# 1. IP forwarding (should be 1)
sysctl net.ipv4.ip_forward

# 2. NAT rules — need MASQUERADE for all 3 VPN subnets
iptables -t nat -L POSTROUTING -n -v
# Expected:
#   10.8.0.0/24  → MASQUERADE (WireGuard)
#   10.9.0.0/24  → MASQUERADE (OpenVPN)
#   10.10.0.0/24 → MASQUERADE (IKEv2/strongSwan)

# 3. Services running
ss -ulnp | grep -E '(51820|1194|500|4500)'
# Expected: all 4 ports listening

# 4. Route table
ip route show default
# Expected: default via 172.31.1.1 dev eth0
```

### 1.2 Fix: IP Forwarding Persistence (idempotent)

```bash
# Already set in 3 places — verify only
grep -r ip_forward /etc/sysctl.conf /etc/sysctl.d/
# If missing:
# echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-vpn-forward.conf
# sysctl -p /etc/sysctl.d/99-vpn-forward.conf
```

### 1.3 Fix: Missing IKEv2 FORWARD Rules

**Current state**: FORWARD policy is DROP. WireGuard and OpenVPN have explicit
ACCEPT rules. IKEv2 (strongSwan) traffic from 10.10.0.0/24 has NO forward rule.

```bash
# Add IKEv2 forwarding (idempotent — check before add)
iptables -C FORWARD -s 10.10.0.0/24 -o eth0 -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -s 10.10.0.0/24 -o eth0 -j ACCEPT

iptables -C FORWARD -d 10.10.0.0/24 -i eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -d 10.10.0.0/24 -i eth0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Persist across reboots — add to /etc/ufw/before.rules or iptables-save
# Option A: Add to strongSwan conn (recommended)
# In /etc/ipsec.conf under conn securewave-ikev2-eap, add:
#   leftfirewall=yes
# This tells charon to insert FORWARD rules automatically.

# Option B: Persist via iptables-save
iptables-save > /etc/iptables/rules.v4
```

### 1.4 Fix: OpenVPN Auth-User-Pass Support

**Current state**: Server expects client certificates (mTLS). Backend's userpass
fallback stores credentials in `/etc/securewave/openvpn/users.db` but server has
no `auth-user-pass-verify` directive — userpass connections WILL FAIL.

**Two paths for client auth:**

#### Path A: mTLS (client certificate) — WORKING NOW
Use the issue-client script to generate per-client certs:
```bash
# Generate client cert (on VPS #1)
/usr/local/bin/securewave-openvpn-issue-client \
  --common-name "testlab-client" \
  --provisioning-token "<TOKEN>" \
  --output json
# Output: /var/lib/securewave/pki/openvpn/testlab-client/client.ovpn
```

#### Path B: Add userpass auth to server — REQUIRES SERVER RESTART

```bash
# 1. Create auth verification script
cat > /usr/local/bin/securewave-openvpn-auth <<'AUTHSCRIPT'
#!/usr/bin/env bash
# Verify username/password against users.db
# OpenVPN passes credentials via file: $1
# File format: line1=username, line2=password
set -euo pipefail

DB_FILE="/etc/securewave/openvpn/users.db"
CRED_FILE="$1"

if [[ ! -f "$CRED_FILE" ]]; then exit 1; fi
if [[ ! -f "$DB_FILE" ]]; then exit 1; fi

USERNAME="$(head -1 "$CRED_FILE")"
PASSWORD="$(tail -1 "$CRED_FILE")"
PASSWORD_B64="$(echo -n "$PASSWORD" | base64)"

STORED="$(grep "^${USERNAME}:" "$DB_FILE" 2>/dev/null | cut -d: -f2)"

if [[ -z "$STORED" ]]; then exit 1; fi
if [[ "$STORED" == "$PASSWORD_B64" ]]; then exit 0; fi
exit 1
AUTHSCRIPT
chmod 700 /usr/local/bin/securewave-openvpn-auth

# 2. Add to server.conf (append before final newline)
cat >> /etc/openvpn/server/server.conf <<'APPEND'

# SecureWave userpass auth support
auth-user-pass-verify /usr/local/bin/securewave-openvpn-auth via-file
verify-client-cert none
username-as-common-name
script-security 2
APPEND

# 3. Restart OpenVPN
systemctl restart openvpn-server@server
systemctl status openvpn-server@server
```

### 1.5 Validation Commands

```bash
# Full status check
echo "=== IP Forward ===" && sysctl net.ipv4.ip_forward
echo "=== NAT ===" && iptables -t nat -L POSTROUTING -n -v
echo "=== FORWARD ===" && iptables -L FORWARD -n -v
echo "=== WireGuard ===" && wg show
echo "=== strongSwan ===" && ipsec statusall | head -15
echo "=== OpenVPN ===" && systemctl is-active openvpn-server@server
echo "=== Ports ===" && ss -ulnp | grep -E '(51820|1194|500|4500)'
echo "=== Routes ===" && ip route
echo "=== Interfaces ===" && ip -br addr
```

### 1.6 Diagnostic tcpdump Commands

```bash
# WireGuard handshake (UDP 51820)
tcpdump -i eth0 udp port 51820 -n -c 20

# OpenVPN traffic (UDP 1194)
tcpdump -i eth0 udp port 1194 -n -c 20

# IKEv2 IKE_SA_INIT (UDP 500) + ESP-in-UDP (UDP 4500)
tcpdump -i eth0 udp port 500 or udp port 4500 -n -c 20

# VPN subnet traffic (after tunnel up)
tcpdump -i wg0 -n -c 10        # WireGuard
tcpdump -i tun0 -n -c 10       # OpenVPN
tcpdump -i eth0 esp -n -c 10   # IKEv2 ESP packets

# NAT verification — watch MASQUERADE in action
iptables -t nat -L POSTROUTING -n -v -Z  # zero counters first
# ... send traffic through VPN ...
iptables -t nat -L POSTROUTING -n -v     # check pkts/bytes increased
```

---

## SECTION 2 — Prepare Client Test VPS (VPS #2)

### 2.1 Initial Setup

```bash
# SSH to VPS #2
ssh root@<CLIENT_IP>

# Update and install all VPN clients + diagnostics
apt update && apt install -y \
  wireguard \
  openvpn \
  strongswan \
  strongswan-swanctl \
  libcharon-extra-plugins \
  libstrongswan-extra-plugins \
  tcpdump \
  iproute2 \
  net-tools \
  curl \
  jq \
  resolvconf

# Enable IP forwarding (needed for some VPN configs)
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-vpn-client.conf
sysctl -p /etc/sysctl.d/99-vpn-client.conf
```

### 2.2 Diagnostics Script

```bash
cat > /root/vpn_diag.sh <<'DIAG'
#!/usr/bin/env bash
set -euo pipefail
echo "=============================="
echo "VPN Diagnostics — $(date -Iseconds)"
echo "=============================="

echo -e "\n--- Default Route ---"
ip route show default

echo -e "\n--- All Routes ---"
ip route show

echo -e "\n--- Interfaces ---"
ip -br addr

echo -e "\n--- Policy Routes ---"
ip rule show

echo -e "\n--- DNS ---"
resolvectl status 2>/dev/null || cat /etc/resolv.conf

echo -e "\n--- Ping 8.8.8.8 (3 packets) ---"
ping -c 3 -W 2 8.8.8.8 2>&1 || echo "PING FAILED"

echo -e "\n--- External IP ---"
curl -sf --max-time 5 https://ifconfig.me 2>/dev/null || echo "CURL FAILED"

echo -e "\n--- WireGuard ---"
wg show 2>/dev/null || echo "No WG interface"

echo -e "\n--- IPsec ---"
ipsec statusall 2>/dev/null || echo "No IPsec SA"

echo -e "\n--- OpenVPN processes ---"
pgrep -a openvpn 2>/dev/null || echo "No OpenVPN process"

echo -e "\n--- Journal Errors (last 20) ---"
journalctl -p err --no-pager -n 20 2>/dev/null || echo "journalctl unavailable"

echo -e "\n--- MTU Check ---"
ip link show | grep -E '(mtu|wg|tun|sw-)'
DIAG
chmod +x /root/vpn_diag.sh
```

### 2.3 SSH Safety — Preserve Control Channel

**CRITICAL**: Before any full-tunnel test, add a static route for your SSH session.
This ensures SSH to VPS #2 survives even if the default route changes.

```bash
# Determine your SSH source IP
SSH_SRC=$(echo $SSH_CONNECTION | awk '{print $1}')
GATEWAY=$(ip route show default | awk '{print $3}')
IFACE=$(ip route show default | awk '{print $5}')

echo "SSH from: $SSH_SRC via gateway: $GATEWAY dev: $IFACE"

# Pin SSH route BEFORE activating any VPN
ip route add $SSH_SRC/32 via $GATEWAY dev $IFACE 2>/dev/null || true

# Also pin VPS #1 management route
ip route add 138.199.204.139/32 via $GATEWAY dev $IFACE 2>/dev/null || true
```

Save as a reusable script:
```bash
cat > /root/pin_ssh_route.sh <<'PIN'
#!/usr/bin/env bash
set -euo pipefail
SSH_SRC=$(echo $SSH_CONNECTION | awk '{print $1}')
GW=$(ip route show default | awk '{print $3}')
DEV=$(ip route show default | awk '{print $5}')
echo "Pinning SSH route: $SSH_SRC via $GW dev $DEV"
ip route add $SSH_SRC/32 via $GW dev $DEV 2>/dev/null || echo "Route already exists"
ip route add 138.199.204.139/32 via $GW dev $DEV 2>/dev/null || echo "Route already exists"
echo "SSH control channel protected."
PIN
chmod +x /root/pin_ssh_route.sh
```

---

## SECTION 3 — WireGuard Full Tunnel Test

### 3.1 Generate Test Peer on VPS #1

```bash
# On VPS #1
ssh root@138.199.204.139

# Generate keypair for VPS #2 test client
wg genkey | tee /tmp/testlab_privkey | wg pubkey > /tmp/testlab_pubkey
TESTLAB_PUBKEY=$(cat /tmp/testlab_pubkey)
TESTLAB_PRIVKEY=$(cat /tmp/testlab_privkey)
echo "Client pubkey: $TESTLAB_PUBKEY"
echo "Client privkey: $TESTLAB_PRIVKEY"

# Assign IP — use 10.8.0.200 (outside app-provisioned range)
CLIENT_IP="10.8.0.200"

# Add peer to server (idempotent)
wg set wg0 peer "$TESTLAB_PUBKEY" allowed-ips "$CLIENT_IP/32"
wg-quick save wg0

# Verify
wg show wg0 | grep -A2 "$TESTLAB_PUBKEY"

# Get server pubkey
SERVER_PUBKEY=$(wg show wg0 public-key)
echo "Server pubkey: $SERVER_PUBKEY"
```

### 3.2 Phase 1: Split-Tunnel (VPN subnet only)

```bash
# On VPS #2
cat > /etc/wireguard/wg-test.conf <<WGCONF
[Interface]
PrivateKey = <TESTLAB_PRIVKEY>
Address = 10.8.0.200/32
DNS = 94.140.14.14

[Peer]
PublicKey = <SERVER_PUBKEY>
Endpoint = 138.199.204.139:51820
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
WGCONF

# Pin SSH route FIRST
/root/pin_ssh_route.sh

# Bring up split tunnel
wg-quick up wg-test

# Validate
wg show wg-test
ping -c 3 10.8.0.1          # Should succeed — VPN server
ip route show                # Default route should be UNCHANGED
curl -sf https://ifconfig.me # Should show VPS #2 public IP (NOT VPS #1)
```

### 3.3 Phase 2: Full Tunnel

```bash
# Tear down split tunnel
wg-quick down wg-test

# Create full-tunnel config
cat > /etc/wireguard/wg-full.conf <<WGCONF
[Interface]
PrivateKey = <TESTLAB_PRIVKEY>
Address = 10.8.0.200/32
DNS = 94.140.14.14
# Table = off + manual policy routing (matches SecureWave app config)
Table = off
PostUp = ip route add default dev %i table 51820 2>/dev/null || true
PostUp = ip rule add not fwmark 51820 table 51820 priority 32764 2>/dev/null || true
PostDown = ip rule del not fwmark 51820 table 51820 priority 32764 2>/dev/null || true
PostDown = ip route del default dev %i table 51820 2>/dev/null || true

[Peer]
PublicKey = <SERVER_PUBKEY>
Endpoint = 138.199.204.139:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
WGCONF

# Pin SSH route FIRST (critical for full tunnel)
/root/pin_ssh_route.sh

# Bring up full tunnel
wg-quick up wg-full

# Validate
wg show wg-full                    # Handshake should appear within 30s
ping -c 3 8.8.8.8                  # Internet via VPN
curl -sf https://ifconfig.me       # Should show 138.199.204.139 (VPS #1)
ip route show table 51820          # Should show default dev wg-full
ip rule show                       # Should show fwmark 51820 rule
```

### 3.4 Validation Checklist — WireGuard

```
[ ] wg show shows handshake timestamp
[ ] ping 10.8.0.1 works (VPN gateway)
[ ] ping 8.8.8.8 works (internet)
[ ] curl ifconfig.me returns 138.199.204.139 (full tunnel)
[ ] SSH session to VPS #2 still works
[ ] ip route show table 51820 has default route
[ ] On VPS #1: tcpdump -i wg0 shows traffic from 10.8.0.200
[ ] On VPS #1: iptables -t nat -L POSTROUTING -n -v shows pkts on 10.8.0.0/24 rule
```

### 3.5 Teardown & Recovery

```bash
# Clean disconnect
wg-quick down wg-full

# Emergency recovery (if routing breaks and SSH freezes)
# Wait 60s — if you added PersistentKeepalive, wg-quick down should be reachable
# Otherwise, use Hetzner console to access VPS #2:
ip link del wg-full 2>/dev/null || true
ip rule del table 51820 2>/dev/null || true
ip route flush table 51820 2>/dev/null || true
ip route add default via <GATEWAY> dev eth0
```

---

## SECTION 4 — OpenVPN Test

### 4.1 Generate Client Config on VPS #1

#### Option A: mTLS (client certificate) — RECOMMENDED

```bash
# On VPS #1 — generate cert manually (no provisioning token needed)
CN="testlab-vpn2"
CA_CERT="/etc/openvpn/server/ca.crt"
CA_KEY="/etc/openvpn/easy-rsa/ca.key"
TLS_CRYPT="/etc/openvpn/server/tls-crypt.key"

# Find CA key
for p in /etc/openvpn/easy-rsa/ca.key /etc/openvpn/pki/ca.key /etc/securewave/secrets/openvpn/easy-rsa/pki/private/ca.key; do
  [ -f "$p" ] && CA_KEY="$p" && break
done

# Generate client key + cert
mkdir -p /tmp/testlab-ovpn
openssl genrsa -out /tmp/testlab-ovpn/client.key 2048 2>/dev/null
openssl req -new -key /tmp/testlab-ovpn/client.key -subj "/CN=$CN" \
  -out /tmp/testlab-ovpn/client.csr 2>/dev/null
openssl x509 -req -in /tmp/testlab-ovpn/client.csr \
  -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
  -out /tmp/testlab-ovpn/client.crt -days 30 -sha256 2>/dev/null

# Build .ovpn profile
cat > /tmp/testlab-ovpn/client.ovpn <<OVPN
client
dev tun
proto udp
remote 138.199.204.139 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
verb 3
<ca>
$(cat $CA_CERT)
</ca>
<cert>
$(cat /tmp/testlab-ovpn/client.crt)
</cert>
<key>
$(cat /tmp/testlab-ovpn/client.key)
</key>
<tls-crypt>
$(cat $TLS_CRYPT)
</tls-crypt>
OVPN

echo "Config at: /tmp/testlab-ovpn/client.ovpn"
cat /tmp/testlab-ovpn/client.ovpn | base64 -w 0
```

#### Option B: Userpass (requires Section 1.4 Path B server fix first)

```bash
# On VPS #1 — the client config for userpass mode
cat > /tmp/testlab-ovpn/client-userpass.ovpn <<OVPN
client
dev tun
proto udp
remote 138.199.204.139 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth-user-pass
auth-nocache
auth SHA256
cipher AES-256-GCM
verb 3
<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>
<tls-crypt>
$(cat /etc/openvpn/server/tls-crypt.key)
</tls-crypt>
OVPN

# Create test user credentials
/usr/local/bin/securewave-openvpn-upsert-user \
  --username testlab-user \
  --password-b64 "$(echo -n 'TestLabPass123!' | base64)" \
  --output json
```

### 4.2 Deploy and Test on VPS #2

```bash
# On VPS #2 — copy config (paste base64 or SCP)
# scp root@138.199.204.139:/tmp/testlab-ovpn/client.ovpn /etc/openvpn/client/testlab.conf

# Pin SSH route FIRST
/root/pin_ssh_route.sh

# Start OpenVPN
openvpn --config /etc/openvpn/client/testlab.conf --daemon --log /var/log/openvpn-test.log

# Wait for connection
sleep 5

# Validate
ip addr show tun0                   # Should have 10.9.0.x address
ip route show                       # Should have new default via tun0
ping -c 3 10.9.0.1                  # VPN gateway
ping -c 3 8.8.8.8                   # Internet via VPN
curl -sf https://ifconfig.me        # Should show 138.199.204.139
cat /var/log/openvpn-test.log | tail -20

# Check from VPS #1
ssh root@138.199.204.139 "cat /var/log/openvpn/status.log"
```

### 4.3 Validation Checklist — OpenVPN

```
[ ] tun0 interface exists with 10.9.0.x/24 address
[ ] Default route points through tun0
[ ] ping 10.9.0.1 works
[ ] ping 8.8.8.8 works
[ ] curl ifconfig.me returns 138.199.204.139
[ ] SSH to VPS #2 still works
[ ] No TLS errors in /var/log/openvpn-test.log
[ ] On VPS #1: /var/log/openvpn/status.log shows connected client
```

### 4.4 Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `TLS Error: TLS handshake failed` | tls-crypt key mismatch or missing | Verify `<tls-crypt>` block matches server's `/etc/openvpn/server/tls-crypt.key` |
| `AUTH_FAILED` (userpass mode) | Server missing `auth-user-pass-verify` | Apply Section 1.4 Path B |
| `VERIFY ERROR: ... certificate verify failed` | CA mismatch | Regenerate client cert with correct CA |
| `write to TUN/TAP : Invalid argument (code=22)` | MTU too large | Add `mssfix 1400` and `tun-mtu 1400` to client config |
| `Initialization Sequence Completed` but no internet | Missing `push redirect-gateway` on server or NAT rule | Check `iptables -t nat -L` for 10.9.0.0/24 MASQUERADE |
| Connected but DNS fails | `push dhcp-option` not applied | Add `script-security 2` + `up /etc/openvpn/update-resolv-conf` to client config |

### 4.5 Teardown

```bash
# Clean stop
killall openvpn 2>/dev/null || true
ip link del tun0 2>/dev/null || true
# Routes auto-restore when OpenVPN exits cleanly
```

---

## SECTION 5 — IKEv2 Test (strongSwan)

### 5.1 Get CA Certificate and Credentials

```bash
# On VPS #1 — get CA cert and create test user
CA_CERT=$(cat /etc/ipsec.d/cacerts/ca-cert.pem)
echo "$CA_CERT"

# Create test user (add to ipsec.secrets)
grep -q "testlab-user" /etc/ipsec.secrets || \
  echo 'testlab-user : EAP "TestLabIKEv2Pass!"' >> /etc/ipsec.secrets

# Reload secrets
ipsec rereadsecrets
ipsec statusall | head -5
```

### 5.2 Configure Client on VPS #2

```bash
# On VPS #2

# Install CA cert
cat > /etc/ipsec.d/cacerts/securewave-ca.pem <<'CACERT'
<PASTE CA_CERT FROM VPS #1>
CACERT

# Client ipsec.conf
cat > /etc/ipsec.conf <<'IPSECCONF'
config setup
  uniqueids=no

conn securewave-test
  auto=start
  type=tunnel
  keyexchange=ikev2
  fragmentation=yes
  forceencaps=yes
  dpdaction=restart
  dpddelay=30s

  # Server side
  right=138.199.204.139
  rightid=138.199.204.139
  rightsubnet=0.0.0.0/0

  # Client side
  left=%defaultroute
  leftid=testlab-user
  leftauth=eap-mschapv2
  leftsourceip=%config
  eap_identity=testlab-user

  # Crypto — must match server
  ike=aes256gcm16-prfsha256-ecp256,aes256-sha256-modp2048!
  esp=aes256gcm16-ecp256,aes256-sha256!
IPSECCONF

# Client secrets
cat > /etc/ipsec.secrets <<'SECRETS'
testlab-user : EAP "TestLabIKEv2Pass!"
SECRETS

# Pin SSH route FIRST
/root/pin_ssh_route.sh

# Start strongSwan
systemctl restart strongswan-starter
sleep 3

# Check status
ipsec statusall
```

### 5.3 Validation Checklist — IKEv2

```
[ ] ipsec statusall shows ESTABLISHED IKE_SA
[ ] ipsec statusall shows INSTALLED CHILD_SA with traffic selectors
[ ] Virtual IP assigned (10.10.0.x)
[ ] ping 8.8.8.8 works
[ ] curl ifconfig.me returns 138.199.204.139
[ ] SSH to VPS #2 still works
[ ] On VPS #1: ipsec statusall shows the client connection
```

### 5.4 Debug Commands

```bash
# Live IKEv2 negotiation logs
journalctl -u strongswan -f

# Detailed charon debug (temporary)
# Edit /etc/strongswan.d/charon-logging.conf:
#   filelog { stderr { ike = 2, net = 1 } }
# Then: systemctl restart strongswan-starter

# Security associations
ip xfrm state   # Show IPsec SAs (encryption keys, SPI)
ip xfrm policy  # Show IPsec policies (traffic selectors)

# Packet capture for IKEv2
tcpdump -i eth0 udp port 500 or udp port 4500 -n

# Check if ESP packets are flowing
tcpdump -i eth0 esp -n -c 10
```

### 5.5 Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `NO_PROPOSAL_CHOSEN` | Crypto mismatch | Align `ike=` and `esp=` with server config |
| `AUTHENTICATION_FAILED` | Wrong EAP password or missing in server secrets | Check `/etc/ipsec.secrets` on VPS #1 |
| `INVALID_ID_INFORMATION` | `rightid` doesn't match server's `leftid` | Set `rightid=138.199.204.139` |
| `TS_UNACCEPTABLE` | Traffic selector mismatch | Ensure `rightsubnet=0.0.0.0/0` matches server's `leftsubnet` |
| Established but no traffic | Missing FORWARD rules on server | Apply Section 1.3 fix |
| `received NO_ADDITIONAL_SAS` | Server at max SA limit | Check `uniqueids` setting |
| Tunnel up, no internet | Missing MASQUERADE for 10.10.0.0/24 | `iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o eth0 -j MASQUERADE` |

### 5.6 Teardown

```bash
ipsec down securewave-test
systemctl stop strongswan-starter
# Routes auto-restore when xfrm policies are removed
```

---

## SECTION 6 — Safety Guarantees

### 6.1 SSH Control Channel Protection

**Every full-tunnel test MUST start with:**
```bash
/root/pin_ssh_route.sh
```

This adds host routes for your SSH source IP and VPS #1, via the original
gateway, so they bypass the VPN tunnel.

### 6.2 Dev Machine Isolation

Your dev machine is **never** part of the VPN routing:
- Dev ↔ VPS #1: SSH only (TCP 22)
- Dev ↔ VPS #2: SSH only (TCP 22)
- VPN tunnel: VPS #2 → VPS #1 only

No VPN config is installed on your dev machine. All VPN traffic is between
the two VPSes.

### 6.3 Emergency Recovery (if locked out of VPS #2)

1. **Hetzner Console**: Access via Hetzner Cloud web UI → Server → Console
2. **Run recovery commands**:
```bash
# Kill all VPN processes
killall openvpn 2>/dev/null; true
wg-quick down wg-test 2>/dev/null; true
wg-quick down wg-full 2>/dev/null; true
ipsec down securewave-test 2>/dev/null; true
systemctl stop strongswan-starter 2>/dev/null; true

# Delete VPN interfaces
ip link del wg-test 2>/dev/null; true
ip link del wg-full 2>/dev/null; true
ip link del tun0 2>/dev/null; true

# Flush policy routing
ip rule del table 51820 2>/dev/null; true
ip route flush table 51820 2>/dev/null; true

# Restore default route
GATEWAY=$(ip route show | grep -v default | head -1 | awk '{print $1}' | cut -d/ -f1)
# On Hetzner, gateway is typically 172.31.1.1
ip route add default via 172.31.1.1 dev eth0 2>/dev/null; true
```

### 6.4 Automated Watchdog (optional)

Install a cron job on VPS #2 that kills VPN if SSH connectivity is lost:
```bash
cat > /root/vpn_watchdog.sh <<'WD'
#!/usr/bin/env bash
# If we can't reach our gateway for 30s, kill all VPNs
GATEWAY=$(ip route show default | grep -v "dev wg\|dev tun" | awk '{print $3}' | head -1)
if [[ -z "$GATEWAY" ]]; then GATEWAY="172.31.1.1"; fi

if ! ping -c 3 -W 10 $GATEWAY >/dev/null 2>&1; then
  logger "VPN watchdog: gateway unreachable, killing VPN"
  killall openvpn 2>/dev/null; true
  for iface in $(ip link show | grep -oE '(wg-[a-z]+|wg[0-9]+)'); do
    wg-quick down "$iface" 2>/dev/null; true
  done
  systemctl stop strongswan-starter 2>/dev/null; true
fi
WD
chmod +x /root/vpn_watchdog.sh

# Run every 2 minutes
(crontab -l 2>/dev/null; echo "*/2 * * * * /root/vpn_watchdog.sh") | sort -u | crontab -
```

---

## SECTION 7 — Quick Reference

### Test Execution Order

```
1. Apply VPS #1 fixes (Section 1.3, 1.4)
2. Set up VPS #2 (Section 2)
3. Test WireGuard split-tunnel → full-tunnel (Section 3)
4. Test OpenVPN mTLS (Section 4)
5. Test IKEv2 EAP (Section 5)
```

### Common Failure Signatures

| Signature | Protocol | Meaning |
|-----------|----------|---------|
| `Handshake did not complete` | WG | Peer not registered, wrong pubkey, or firewall blocking UDP 51820 |
| `UAPI error` | WG | wg-quick config syntax error |
| `TLS Error: TLS key negotiation failed` | OVPN | tls-crypt mismatch or CA issue |
| `AUTH_FAILED` | OVPN | No auth-user-pass-verify on server (userpass) or cert rejected (mTLS) |
| `NO_PROPOSAL_CHOSEN` | IKEv2 | Cipher suite mismatch between client and server |
| `AUTHENTICATION_FAILED` | IKEv2 | Wrong EAP password |
| `Connection reset by peer` on SSH | ALL | Full tunnel captured SSH — pin_ssh_route not run |
| `RTNETLINK: File exists` | ALL | Route already exists (harmless) |
| `ping: sendmsg: Required key not available` | IKEv2 | xfrm policy issue — check `ip xfrm policy` |

### Port Reference

| Port | Proto | Service |
|------|-------|---------|
| 51820 | UDP | WireGuard |
| 1194 | UDP | OpenVPN |
| 500 | UDP | IKEv2 IKE_SA_INIT |
| 4500 | UDP | IKEv2 NAT-T (ESP-in-UDP) |

### VPN Subnet Reference

| Subnet | Protocol | Server Gateway |
|--------|----------|----------------|
| 10.8.0.0/24 | WireGuard | 10.8.0.1 |
| 10.9.0.0/24 | OpenVPN | 10.9.0.1 |
| 10.10.0.10-250 | IKEv2 | via xfrm |

### Cleanup — Remove Test Peer from VPS #1

```bash
# After testing is complete, remove test artifacts
ssh root@138.199.204.139 bash -s <<'CLEANUP'
# WireGuard
TESTLAB_PUBKEY="<pubkey>"
wg set wg0 peer "$TESTLAB_PUBKEY" remove
wg-quick save wg0

# OpenVPN
rm -rf /var/lib/securewave/pki/openvpn/testlab-*
rm -rf /tmp/testlab-ovpn

# IKEv2
sed -i '/testlab-user/d' /etc/ipsec.secrets
ipsec rereadsecrets
CLEANUP
```
