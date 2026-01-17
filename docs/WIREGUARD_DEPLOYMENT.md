# SecureWave VPN - WireGuard Deployment Guide

This document provides complete instructions for deploying and testing the SecureWave WireGuard VPN system.

## Architecture Overview

```
+------------------+     HTTPS      +-------------------+
|                  |  (API calls)   |                   |
|  User's Device   +--------------->|  FastAPI Backend  |
|  (WireGuard App) |                |  (Azure App Svc)  |
|                  |                |                   |
+--------+---------+                +--------+----------+
         |                                   |
         |                                   | SSH / Azure Run Command
         | UDP 51820                         |
         | (VPN tunnel)                      v
         |                          +--------+----------+
         |                          |                   |
         +------------------------->|  WireGuard VM     |
                                    |  (Azure Linux VM) |
                                    |                   |
                                    +-------------------+
```

### Component Responsibilities

| Component | Role | Technology |
|-----------|------|------------|
| FastAPI Backend | Control plane - user auth, config generation, peer management | Python 3.11, Azure App Service |
| WireGuard VM | Data plane - actual VPN tunnel termination | Ubuntu 22.04, Azure VM |
| User Device | VPN client - runs WireGuard app with downloaded config | WireGuard (any platform) |

## Phase 1: Azure WireGuard VM Setup

### 1.1 Create Azure VM

```bash
# Variables
RESOURCE_GROUP="SecureWaveVPN"
VM_NAME="securewave-wg-eastus"
LOCATION="eastus"
VM_SIZE="Standard_B2s"  # 2 vCPU, 4GB RAM

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create VM with Ubuntu 22.04
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --location $LOCATION \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest \
  --size $VM_SIZE \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard

# Get public IP
PUBLIC_IP=$(az vm show -g $RESOURCE_GROUP -n $VM_NAME --show-details --query publicIps -o tsv)
echo "VM Public IP: $PUBLIC_IP"

# Open WireGuard port
az vm open-port \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --port 51820 \
  --protocol udp \
  --priority 100
```

### 1.2 Run Setup Script on VM

SSH into the VM and run the setup script:

```bash
# SSH to VM
ssh azureuser@$PUBLIC_IP

# Download and run setup script
curl -sSL https://raw.githubusercontent.com/your-repo/securewave/main/infrastructure/wireguard_vm_setup.sh | sudo bash

# Or copy the script manually and run
sudo bash /path/to/wireguard_vm_setup.sh
```

### 1.3 Retrieve Server Information

After setup, get the server details:

```bash
# On the WG VM
cat /opt/securewave/server_info.json

# Output:
# {
#   "public_ip": "20.xxx.xxx.xxx",
#   "wg_port": 51820,
#   "server_public_key": "xxxxx...xxxxx=",
#   "vpn_subnet": "10.8.0.0/24",
#   "interface": "wg0",
#   "setup_timestamp": "2026-01-17T..."
# }

# Get server public key
cat /etc/wireguard/keys/server_public.key
```

## Phase 2: Backend Configuration

### 2.1 Environment Variables

Add to your `.env` or Azure App Service configuration:

```bash
# WireGuard Configuration
WG_MOCK_MODE=false                           # Set to false for production
WG_DNS=1.1.1.1,1.0.0.1                       # Cloudflare DNS
WG_DATA_DIR=/app/wg_data                     # Config storage directory
WG_ENDPOINT=<vm-public-ip>:51820             # Single-server fallback endpoint
WG_ENCRYPTION_KEY=<generate-fernet-key>      # For encrypting private keys
WG_SERVER_PUBLIC_KEY=<from-vm-setup>         # Optional: override default

# Server Communication
WG_SSH_KEY_PATH=/app/keys/wg_server.pem      # SSH private key for VM access
WG_SSH_USER=azureuser                        # SSH username
WG_COMMAND_TIMEOUT=30                        # Timeout for server commands

# Or use Azure Run Command (alternative to SSH)
WG_VM_NAME=securewave-wg-eastus              # Azure VM name
WG_RESOURCE_GROUP=SecureWaveVPN              # Azure resource group

# Auto-registration
WG_AUTO_REGISTER_PEERS=true                  # Auto-register peers on config generation
```

Generate a Fernet encryption key:

```python
from cryptography.fernet import Fernet
print(Fernet.generate_key().decode())
```

Optional helper script (Azure App Service):

```bash
export AZURE_RESOURCE_GROUP="SecureWaveRG"
export AZURE_APP_NAME="securewave-web"
export WG_ENCRYPTION_KEY="<fernet-key>"
export WG_ENDPOINT="<vm-public-ip>:51820"
export WG_SERVER_PUBLIC_KEY="<server-public-key>"
export WG_VM_NAME="securewave-wg"
export WG_RESOURCE_GROUP="SecureWaveRG"
export WG_AUTO_REGISTER_PEERS=true
./scripts/phase2_backend_config.sh
```

### 2.2 Register Server in Database

Use the admin API or run directly:

```python
# Using the API (requires admin authentication)
import httpx

response = httpx.post(
    "https://your-backend.azurewebsites.net/api/admin/servers/",
    headers={"Authorization": f"Bearer {admin_token}"},
    json={
        "server_id": "us-east-001",
        "location": "Virginia",
        "country": "United States",
        "country_code": "US",
        "city": "Virginia",
        "region": "Americas",
        "azure_region": "eastus",
        "azure_resource_group": "SecureWaveVPN",
        "azure_vm_name": "securewave-wg-eastus",
        "public_ip": "20.xxx.xxx.xxx",
        "wg_public_key": "<server-public-key>",
        "wg_listen_port": 51820,
        "max_connections": 1000,
    }
)
```

Or use the infrastructure script:

```bash
python infrastructure/register_server.py \
  --server-id us-east-001 \
  --public-ip 20.xxx.xxx.xxx \
  --public-key "xxxxx...xxxxx="
```

## Phase 3: Testing the VPN

### 3.1 Local Testing (macOS/Linux)

1. **Install WireGuard:**

```bash
# macOS
brew install wireguard-tools

# Ubuntu/Debian
sudo apt install wireguard

# Fedora
sudo dnf install wireguard-tools
```

2. **Generate Configuration via API:**

```bash
# Login and get token
TOKEN=$(curl -s -X POST https://your-backend.azurewebsites.net/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"yourpassword"}' | jq -r '.access_token')

# Get list of servers
curl -s https://your-backend.azurewebsites.net/api/vpn/servers \
  -H "Authorization: Bearer $TOKEN" | jq

# Allocate configuration
curl -s -X POST https://your-backend.azurewebsites.net/api/vpn/allocate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"server_id":"us-east-001"}' > config_response.json

# Extract config
jq -r '.config' config_response.json > securewave.conf
```

3. **Import and Activate:**

```bash
# Copy config
sudo cp securewave.conf /etc/wireguard/

# Start VPN
sudo wg-quick up securewave

# Check status
sudo wg show
```

### 3.2 Verify VPN is Working

```bash
# 1. Check WireGuard interface
sudo wg show securewave

# Expected output:
# interface: securewave
#   public key: <your-public-key>
#   private key: (hidden)
#   listening port: <random>
#
# peer: <server-public-key>
#   endpoint: 20.xxx.xxx.xxx:51820
#   allowed ips: 0.0.0.0/0, ::/0
#   latest handshake: X seconds ago  <-- THIS SHOULD APPEAR
#   transfer: X KiB received, X KiB sent

# 2. Check your public IP changed
curl -s ifconfig.me
# Should show the VPN server's IP, not your real IP

# 3. Verify routing
traceroute 8.8.8.8
# First hop should be 10.8.0.1 (VPN gateway)

# 4. DNS leak test
nslookup example.com
# Should use 1.1.1.1 (Cloudflare DNS)
```

### 3.3 Disconnect

```bash
sudo wg-quick down securewave
```

### 3.4 Mobile Testing

1. Install WireGuard app from App Store / Play Store
2. Open the VPN configuration page in browser
3. Click "Show QR Code"
4. Scan QR code with WireGuard app
5. Activate the tunnel
6. Verify with IP checker website

## Phase 4: Production Deployment

### 4.1 Deploy Multiple Servers

Use the deployer script for global fleet:

```bash
# Deploy single server
python infrastructure/azure_vpn_deployer.py eastus

# Deploy global fleet (2 servers per region)
python infrastructure/azure_vpn_deployer.py deploy-global
```

### 4.2 Configure Health Monitoring

The backend includes health check endpoints. Set up monitoring:

```bash
# Manual health check
curl -X POST https://your-backend.azurewebsites.net/api/admin/servers/us-east-001/health-check \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Response:
# {
#   "server_id": "us-east-001",
#   "healthy": true,
#   "message": "Server healthy",
#   "consecutive_failures": 0,
#   "health_status": "healthy"
# }
```

### 4.3 Azure Application Insights

Add monitoring with Application Insights:

```bash
# In .env
APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=xxx;...
```

## Troubleshooting

### VPN Won't Connect

1. **Check firewall:**
```bash
# On VM
sudo ufw status
# Ensure 51820/udp is allowed
```

2. **Check WireGuard is running:**
```bash
# On VM
sudo systemctl status wg-quick@wg0
sudo wg show wg0
```

3. **Verify peer is registered:**
```bash
# On VM - list all peers
sudo wg show wg0 peers
# Your public key should appear in the list
```

4. **Check endpoint reachability:**
```bash
# From client - test UDP connectivity
nc -vzu 20.xxx.xxx.xxx 51820
```

### Handshake Not Completing

1. **Verify keys match:**
```bash
# Client public key should match what's registered on server
# Check server peers
ssh azureuser@$VM_IP "sudo wg show wg0 allowed-ips"
```

2. **Check IP forwarding:**
```bash
# On VM
cat /proc/sys/net/ipv4/ip_forward
# Should be 1
```

3. **Check NAT rules:**
```bash
# On VM
sudo iptables -t nat -L POSTROUTING
# Should show MASQUERADE rule
```

### Config Generation Fails

1. **Check backend logs:**
```bash
az webapp log tail --name securewave-app --resource-group SecureWaveRG
```

2. **Test API manually:**
```bash
curl -v -X POST https://your-backend.azurewebsites.net/api/vpn/allocate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"server_id":"us-east-001"}'
```

## MARL + XGBoost Integration Points

The AI optimization system can integrate at these points:

### Observable Metrics (Read-Only)
- Server CPU/memory usage from `/api/admin/servers/{id}/metrics`
- Connection counts per server
- Latency measurements
- Packet loss statistics
- User connection patterns

### Influenceable Decisions
- Server recommendation ranking (modify `performance_score`)
- Load balancing weights (adjust `priority` field)
- Auto-scaling triggers (modify thresholds)

### Must NOT Touch
- WireGuard key generation/management
- IP address allocation
- Peer registration on servers
- User authentication/authorization
- Config file contents

### Integration Example

```python
# In services/vpn_optimizer.py
class MARLOptimizer:
    def get_recommended_server(self, user_location, servers):
        """
        Use MARL model to select optimal server.

        Inputs:
        - user_location: estimated lat/lon from IP
        - servers: list of available servers with metrics

        Output:
        - server_id to recommend
        """
        # Get features from servers
        features = self._extract_features(servers)

        # Run XGBoost prediction for QoS score
        qos_predictions = self.qos_model.predict(features)

        # Use MARL policy to balance load and performance
        action = self.marl_policy.select_action(
            state=self._build_state(servers, user_location),
            qos_scores=qos_predictions
        )

        return servers[action].server_id
```

## Security Considerations

1. **Private Key Protection:**
   - All private keys are encrypted with Fernet before storage
   - Never log or expose private keys
   - Key rotation every 90 days recommended

2. **API Authentication:**
   - All VPN endpoints require JWT authentication
   - Admin endpoints require `is_admin=True`
   - Rate limiting on config generation (5/minute)

3. **Network Isolation:**
   - WireGuard VM should only expose port 51820/UDP
   - Management API (if enabled) only accessible from backend IP
   - SSH key-based authentication only

4. **Audit Logging:**
   - All peer additions/removals are logged
   - Config downloads are tracked
   - Admin actions recorded in audit_log table
