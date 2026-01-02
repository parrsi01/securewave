#!/usr/bin/env bash
set -euo pipefail

# SecureWave VPN - Deploy Real VPN Server to Azure Container Instance
# This script deploys a single WireGuard VPN server for the hybrid deployment

SERVER_ID="${1:-us-east-1}"
AZURE_REGION="${2:-eastus}"
LOCATION="${3:-New York}"
RG="SecureWaveRG"

echo "=========================================="
echo "SecureWave VPN Server Deployment"
echo "=========================================="
echo "Server ID:     $SERVER_ID"
echo "Azure Region:  $AZURE_REGION"
echo "Location:      $LOCATION"
echo "Resource Group: $RG"
echo "=========================================="
echo

# Check Azure CLI login
echo "[1/5] Checking Azure CLI authentication..."
if ! az account show > /dev/null 2>&1; then
    echo "❌ Not logged in to Azure. Please run: az login"
    exit 1
fi
echo "✅ Azure CLI authenticated"
echo

# Deploy Container Instance
echo "[2/5] Deploying WireGuard container to Azure..."
CONTAINER_NAME="securewave-vpn-${SERVER_ID}"

az container create \
    --resource-group "$RG" \
    --name "$CONTAINER_NAME" \
    --image linuxserver/wireguard:latest \
    --dns-name-label "securewave-${SERVER_ID}" \
    --location "$AZURE_REGION" \
    --ports 51820 \
    --protocol UDP \
    --cpu 2 \
    --memory 2 \
    --environment-variables \
        PUID=1000 \
        PGID=1000 \
        TZ=UTC \
        SERVERURL="securewave-${SERVER_ID}.${AZURE_REGION}.azurecontainer.io" \
        SERVERPORT=51820 \
        PEERS=1000 \
        PEERDNS=1.1.1.1 \
        INTERNAL_SUBNET=10.8.0.0 \
    --restart-policy Always \
    --output table

echo "✅ Container deployed successfully"
echo

# Wait for container to start
echo "[3/5] Waiting for container to initialize..."
sleep 15
echo "✅ Container should be initialized"
echo

# Extract public IP
echo "[4/5] Extracting public IP address..."
PUBLIC_IP=$(az container show \
    --resource-group "$RG" \
    --name "$CONTAINER_NAME" \
    --query ipAddress.ip -o tsv)

if [ -z "$PUBLIC_IP" ]; then
    echo "❌ Failed to get public IP. Check container status."
    exit 1
fi

echo "✅ Public IP: $PUBLIC_IP"
ENDPOINT="${PUBLIC_IP}:51820"
echo "✅ Endpoint: $ENDPOINT"
echo

# Register server in database
echo "[5/5] Registering server in database..."
cd "$(dirname "$0")/.."

python3 infrastructure/register_server.py \
    --server-id "$SERVER_ID" \
    --location "$LOCATION" \
    --public-ip "$PUBLIC_IP" \
    --endpoint "$ENDPOINT" \
    --region "Americas"

echo
echo "=========================================="
echo "🎉 VPN Server Deployment Complete!"
echo "=========================================="
echo "Server ID:  $SERVER_ID"
echo "Location:   $LOCATION"
echo "Endpoint:   $ENDPOINT"
echo "Status:     active"
echo "=========================================="
echo
echo "💡 Next steps:"
echo "   1. Server will appear in optimizer within 30 seconds"
echo "   2. Health monitor will start tracking metrics"
echo "   3. Users can now connect to this server"
echo
echo "🔍 To check container logs:"
echo "   az container logs --resource-group $RG --name $CONTAINER_NAME"
echo
echo "🗑️  To delete the server:"
echo "   az container delete --resource-group $RG --name $CONTAINER_NAME --yes"
echo
