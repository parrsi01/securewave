#!/usr/bin/env bash
set -euo pipefail

echo "===================================="
echo "SecureWave Quick Redeploy"
echo "===================================="
echo ""

ACR_NAME="securewaveacr1767120370"
IMAGE_TAG="redesign-$(date +%Y%m%d%H%M%S)"
APP="securewave-app"
RG="SecureWaveRG"

echo "[1/5] Building new Docker image with updated design..."
az acr build \
  --registry "$ACR_NAME" \
  --image "securewave:${IMAGE_TAG}" \
  --image "securewave:latest" \
  --file Dockerfile \
  . --output table

echo ""
echo "[2/5] Updating web app to use new image..."
az webapp config container set \
  --name "$APP" \
  --resource-group "$RG" \
  --container-image-name "${ACR_NAME}.azurecr.io/securewave:latest" \
  --output none

echo "[3/5] Restarting web app..."
az webapp restart --name "$APP" --resource-group "$RG" --output none

echo "[4/5] Waiting for container to start (60 seconds)..."
sleep 60

echo "[5/5] Testing deployment..."
echo ""
if curl -sf https://securewave-app.azurewebsites.net/api/health > /dev/null; then
  echo "✅ SUCCESS! Your redesigned app is live!"
  echo ""
  echo "🌐 Visit: https://securewave-app.azurewebsites.net"
  echo "📚 API Docs: https://securewave-app.azurewebsites.net/api/docs"
  echo ""
else
  echo "⚠️  App is restarting... Give it another minute and refresh your browser."
fi

echo "===================================="
