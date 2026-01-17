#!/bin/bash
# =============================================================================
# SecureWave VPN - WireGuard Server Setup Script
# Run this on a fresh Ubuntu 22.04 Azure VM
# =============================================================================

set -e

# Configuration
WG_PORT="${WG_PORT:-51820}"
WG_INTERFACE="wg0"
WG_ADDRESS="10.8.0.1/24"
API_PORT="${API_PORT:-8080}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# 1. System Updates and Dependencies
# =============================================================================
log_info "Updating system packages..."
apt-get update && apt-get upgrade -y

log_info "Installing required packages..."
apt-get install -y \
    wireguard \
    wireguard-tools \
    iptables \
    net-tools \
    curl \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    ufw \
    fail2ban \
    htop \
    iotop

# =============================================================================
# 2. Enable IP Forwarding
# =============================================================================
log_info "Enabling IP forwarding..."
cat > /etc/sysctl.d/99-wireguard.conf << 'EOF'
# Enable IP forwarding for WireGuard VPN
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Security hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
EOF

sysctl -p /etc/sysctl.d/99-wireguard.conf

# =============================================================================
# 3. Generate WireGuard Server Keys
# =============================================================================
log_info "Generating WireGuard server keys..."
mkdir -p /etc/wireguard/keys
chmod 700 /etc/wireguard/keys

# Generate private key
wg genkey > /etc/wireguard/keys/server_private.key
chmod 600 /etc/wireguard/keys/server_private.key

# Generate public key
cat /etc/wireguard/keys/server_private.key | wg pubkey > /etc/wireguard/keys/server_public.key

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/keys/server_private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/keys/server_public.key)

log_info "Server public key: ${SERVER_PUBLIC_KEY}"

# =============================================================================
# 4. Detect Primary Network Interface
# =============================================================================
log_info "Detecting primary network interface..."
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$PRIMARY_INTERFACE" ]; then
    PRIMARY_INTERFACE="eth0"
    log_warn "Could not detect primary interface, defaulting to eth0"
fi
log_info "Primary interface: ${PRIMARY_INTERFACE}"

# =============================================================================
# 5. Create WireGuard Configuration
# =============================================================================
log_info "Creating WireGuard configuration..."
cat > /etc/wireguard/${WG_INTERFACE}.conf << EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${WG_ADDRESS}
ListenPort = ${WG_PORT}
SaveConfig = false

# NAT and forwarding rules
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${PRIMARY_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${PRIMARY_INTERFACE} -j MASQUERADE

# Peers will be added dynamically via the management API
EOF

chmod 600 /etc/wireguard/${WG_INTERFACE}.conf

# =============================================================================
# 6. Configure Firewall (UFW)
# =============================================================================
log_info "Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow 22/tcp comment 'SSH'

# Allow WireGuard
ufw allow ${WG_PORT}/udp comment 'WireGuard VPN'

# Allow management API (internal only or from specific IPs)
# ufw allow from <backend-ip> to any port ${API_PORT} proto tcp comment 'Management API'

# Enable UFW
ufw --force enable

# =============================================================================
# 7. Start WireGuard
# =============================================================================
log_info "Starting WireGuard..."
systemctl enable wg-quick@${WG_INTERFACE}
systemctl start wg-quick@${WG_INTERFACE}

# =============================================================================
# 8. Create Peer Management Scripts
# =============================================================================
log_info "Creating peer management scripts..."

# Script to add a peer
cat > /usr/local/bin/wg-add-peer << 'ADDPEER'
#!/bin/bash
# Add a WireGuard peer
# Usage: wg-add-peer <public_key> <allowed_ips>

PUBLIC_KEY="$1"
ALLOWED_IPS="$2"

if [ -z "$PUBLIC_KEY" ] || [ -z "$ALLOWED_IPS" ]; then
    echo "Usage: wg-add-peer <public_key> <allowed_ips>"
    exit 1
fi

# Check if peer already exists
if wg show wg0 peers | grep -q "$PUBLIC_KEY"; then
    echo "Peer already exists"
    exit 0
fi

# Add peer
wg set wg0 peer "$PUBLIC_KEY" allowed-ips "$ALLOWED_IPS"

# Save configuration
wg-quick save wg0 2>/dev/null || true

echo "Peer added successfully"
ADDPEER
chmod +x /usr/local/bin/wg-add-peer

# Script to remove a peer
cat > /usr/local/bin/wg-remove-peer << 'REMOVEPEER'
#!/bin/bash
# Remove a WireGuard peer
# Usage: wg-remove-peer <public_key>

PUBLIC_KEY="$1"

if [ -z "$PUBLIC_KEY" ]; then
    echo "Usage: wg-remove-peer <public_key>"
    exit 1
fi

# Remove peer
wg set wg0 peer "$PUBLIC_KEY" remove

# Save configuration
wg-quick save wg0 2>/dev/null || true

echo "Peer removed successfully"
REMOVEPEER
chmod +x /usr/local/bin/wg-remove-peer

# Script to list peers
cat > /usr/local/bin/wg-list-peers << 'LISTPEERS'
#!/bin/bash
# List all WireGuard peers with their status
# Output: JSON format

echo "["
first=true
while IFS= read -r line; do
    if [ "$line" == "" ]; then
        continue
    fi

    PUBLIC_KEY=$(echo "$line" | awk '{print $1}')
    ENDPOINT=$(wg show wg0 endpoints 2>/dev/null | grep "$PUBLIC_KEY" | awk '{print $2}')
    ALLOWED_IPS=$(wg show wg0 allowed-ips 2>/dev/null | grep "$PUBLIC_KEY" | awk '{print $2}')
    LATEST_HANDSHAKE=$(wg show wg0 latest-handshakes 2>/dev/null | grep "$PUBLIC_KEY" | awk '{print $2}')
    TRANSFER=$(wg show wg0 transfer 2>/dev/null | grep "$PUBLIC_KEY" | awk '{print $2, $3}')

    if [ "$first" = true ]; then
        first=false
    else
        echo ","
    fi

    echo "  {"
    echo "    \"public_key\": \"$PUBLIC_KEY\","
    echo "    \"endpoint\": \"$ENDPOINT\","
    echo "    \"allowed_ips\": \"$ALLOWED_IPS\","
    echo "    \"latest_handshake\": \"$LATEST_HANDSHAKE\","
    echo "    \"transfer_rx\": \"$(echo $TRANSFER | awk '{print $1}')\","
    echo "    \"transfer_tx\": \"$(echo $TRANSFER | awk '{print $2}')\""
    echo -n "  }"
done < <(wg show wg0 peers 2>/dev/null)
echo ""
echo "]"
LISTPEERS
chmod +x /usr/local/bin/wg-list-peers

# Script to get server status
cat > /usr/local/bin/wg-server-status << 'STATUS'
#!/bin/bash
# Get WireGuard server status as JSON

INTERFACE="wg0"
PUBLIC_KEY=$(cat /etc/wireguard/keys/server_public.key 2>/dev/null || echo "unknown")
LISTENING_PORT=$(wg show $INTERFACE listen-port 2>/dev/null || echo "0")
PEER_COUNT=$(wg show $INTERFACE peers 2>/dev/null | wc -l)

# Get system metrics
CPU_LOAD=$(awk '{print $1}' /proc/loadavg)
MEMORY_TOTAL=$(free -m | grep Mem | awk '{print $2}')
MEMORY_USED=$(free -m | grep Mem | awk '{print $3}')
MEMORY_PERCENT=$(echo "scale=2; $MEMORY_USED / $MEMORY_TOTAL * 100" | bc)
DISK_PERCENT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
UPTIME=$(cat /proc/uptime | awk '{print $1}')

cat << EOF
{
  "status": "$(systemctl is-active wg-quick@$INTERFACE)",
  "interface": "$INTERFACE",
  "public_key": "$PUBLIC_KEY",
  "listen_port": $LISTENING_PORT,
  "peer_count": $PEER_COUNT,
  "cpu_load": $CPU_LOAD,
  "memory_percent": $MEMORY_PERCENT,
  "disk_percent": $DISK_PERCENT,
  "uptime_seconds": $UPTIME,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
STATUS
chmod +x /usr/local/bin/wg-server-status

# =============================================================================
# 9. Create Management API Service (Optional - for direct VM management)
# =============================================================================
log_info "Creating management API service..."

mkdir -p /opt/securewave
cat > /opt/securewave/wg_api.py << 'APICODE'
#!/usr/bin/env python3
"""
Lightweight WireGuard Management API
Runs on the VPN server to handle peer operations
"""
import os
import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import hmac
import hashlib
import time

# API key for authentication (set via environment variable)
API_KEY = os.environ.get('WG_API_KEY', 'change-me-in-production')
LISTEN_PORT = int(os.environ.get('WG_API_PORT', '8080'))

def verify_api_key(headers):
    """Verify the API key from request headers"""
    provided_key = headers.get('X-API-Key', '')
    return hmac.compare_digest(provided_key, API_KEY)

def run_command(cmd):
    """Run a shell command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return result.returncode == 0, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return False, '', 'Command timed out'
    except Exception as e:
        return False, '', str(e)

class WireGuardAPIHandler(BaseHTTPRequestHandler):
    def send_json_response(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        if not verify_api_key(self.headers):
            self.send_json_response(401, {'error': 'Unauthorized'})
            return

        parsed = urlparse(self.path)

        if parsed.path == '/status':
            success, output, error = run_command('wg-server-status')
            if success:
                self.send_json_response(200, json.loads(output))
            else:
                self.send_json_response(500, {'error': error or 'Failed to get status'})

        elif parsed.path == '/peers':
            success, output, error = run_command('wg-list-peers')
            if success:
                self.send_json_response(200, json.loads(output))
            else:
                self.send_json_response(500, {'error': error or 'Failed to list peers'})

        elif parsed.path == '/health':
            success, _, _ = run_command('wg show wg0')
            self.send_json_response(200 if success else 503, {
                'healthy': success,
                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
            })

        else:
            self.send_json_response(404, {'error': 'Not found'})

    def do_POST(self):
        if not verify_api_key(self.headers):
            self.send_json_response(401, {'error': 'Unauthorized'})
            return

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode() if content_length > 0 else '{}'

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_json_response(400, {'error': 'Invalid JSON'})
            return

        parsed = urlparse(self.path)

        if parsed.path == '/peers/add':
            public_key = data.get('public_key', '').strip()
            allowed_ips = data.get('allowed_ips', '').strip()

            if not public_key or not allowed_ips:
                self.send_json_response(400, {'error': 'Missing public_key or allowed_ips'})
                return

            # Validate public key format (base64, 44 chars)
            if len(public_key) != 44 or not public_key.replace('+', '').replace('/', '').replace('=', '').isalnum():
                self.send_json_response(400, {'error': 'Invalid public key format'})
                return

            cmd = f'wg-add-peer "{public_key}" "{allowed_ips}"'
            success, output, error = run_command(cmd)

            if success:
                self.send_json_response(200, {'success': True, 'message': output or 'Peer added'})
            else:
                self.send_json_response(500, {'success': False, 'error': error or 'Failed to add peer'})

        elif parsed.path == '/peers/remove':
            public_key = data.get('public_key', '').strip()

            if not public_key:
                self.send_json_response(400, {'error': 'Missing public_key'})
                return

            cmd = f'wg-remove-peer "{public_key}"'
            success, output, error = run_command(cmd)

            if success:
                self.send_json_response(200, {'success': True, 'message': output or 'Peer removed'})
            else:
                self.send_json_response(500, {'success': False, 'error': error or 'Failed to remove peer'})

        else:
            self.send_json_response(404, {'error': 'Not found'})

    def log_message(self, format, *args):
        # Custom logging
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {args[0]}")

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', LISTEN_PORT), WireGuardAPIHandler)
    print(f"WireGuard Management API listening on port {LISTEN_PORT}")
    print("Endpoints: GET /status, GET /peers, GET /health, POST /peers/add, POST /peers/remove")
    server.serve_forever()
APICODE

chmod +x /opt/securewave/wg_api.py

# Create systemd service for management API
cat > /etc/systemd/system/wg-management-api.service << 'SVCFILE'
[Unit]
Description=WireGuard Management API
After=network.target wg-quick@wg0.service
Requires=wg-quick@wg0.service

[Service]
Type=simple
User=root
Environment=WG_API_KEY=change-me-in-production
Environment=WG_API_PORT=8080
ExecStart=/usr/bin/python3 /opt/securewave/wg_api.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCFILE

systemctl daemon-reload
# Don't enable by default - requires API key configuration
# systemctl enable wg-management-api
# systemctl start wg-management-api

# =============================================================================
# 10. Configure Fail2Ban for SSH Protection
# =============================================================================
log_info "Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# =============================================================================
# 11. Create Health Check Endpoint
# =============================================================================
log_info "Creating health check service..."

cat > /opt/securewave/health_check.sh << 'HEALTHCHECK'
#!/bin/bash
# Simple health check that returns WG status
if wg show wg0 > /dev/null 2>&1; then
    echo "OK"
    exit 0
else
    echo "FAIL"
    exit 1
fi
HEALTHCHECK
chmod +x /opt/securewave/health_check.sh

# =============================================================================
# 12. Output Server Information
# =============================================================================
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "unknown")

log_info "=============================================="
log_info "WireGuard VPN Server Setup Complete!"
log_info "=============================================="
echo ""
echo "Server Information:"
echo "  Public IP:        ${PUBLIC_IP}"
echo "  WireGuard Port:   ${WG_PORT}/UDP"
echo "  Server Public Key: ${SERVER_PUBLIC_KEY}"
echo "  VPN Subnet:       10.8.0.0/24"
echo ""
echo "Files Created:"
echo "  Config:           /etc/wireguard/${WG_INTERFACE}.conf"
echo "  Server Private:   /etc/wireguard/keys/server_private.key"
echo "  Server Public:    /etc/wireguard/keys/server_public.key"
echo ""
echo "Management Scripts:"
echo "  Add peer:         wg-add-peer <public_key> <allowed_ips>"
echo "  Remove peer:      wg-remove-peer <public_key>"
echo "  List peers:       wg-list-peers"
echo "  Server status:    wg-server-status"
echo ""
echo "Next Steps:"
echo "  1. Save the server public key for your backend: ${SERVER_PUBLIC_KEY}"
echo "  2. Configure your backend with this server's public IP and key"
echo "  3. Optionally enable the management API:"
echo "     - Set WG_API_KEY in /etc/systemd/system/wg-management-api.service"
echo "     - systemctl enable --now wg-management-api"
echo "     - Open port 8080 for the backend IP only"
echo ""

# Save server info to a file
cat > /opt/securewave/server_info.json << EOF
{
  "public_ip": "${PUBLIC_IP}",
  "wg_port": ${WG_PORT},
  "server_public_key": "${SERVER_PUBLIC_KEY}",
  "vpn_subnet": "10.8.0.0/24",
  "interface": "${WG_INTERFACE}",
  "setup_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

log_info "Server info saved to /opt/securewave/server_info.json"
