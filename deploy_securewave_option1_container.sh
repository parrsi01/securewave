#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecureWave Production Deployment Script
# Single-Container Azure App Service Deployment
# URL: https://securewave-app.azurewebsites.net
# ============================================================

echo "================================================"
echo "SecureWave VPN - Production Deployment"
echo "================================================"

# Configuration
RG="SecureWaveRG"
LOC="westeurope"
PLAN="SecureWavePlan"
APP="securewave-app"
ACR_NAME="securewaveacr$(date +%s)"
IMAGE_REPO="securewave"
IMAGE_TAG="v$(date +%Y%m%d%H%M%S)"
IMAGE="${ACR_NAME}.azurecr.io/${IMAGE_REPO}:${IMAGE_TAG}"

echo ""
echo "Configuration:"
echo "  Resource Group: $RG"
echo "  Location: $LOC"
echo "  App Service: $APP"
echo "  ACR: $ACR_NAME"
echo "  Image: $IMAGE"
echo ""

# Step 1: Login to Azure
echo "[1/10] Logging in to Azure..."
az account show >/dev/null 2>&1 || az login --use-device-code
echo "✓ Logged in successfully"

# Step 2: Create Resource Group
echo "[2/10] Creating resource group..."
az group create \
    --name "$RG" \
    --location "$LOC" \
    --output none 2>/dev/null || echo "✓ Resource group already exists"
echo "✓ Resource group ready"

# Step 3: Create Azure Container Registry
echo "[3/10] Creating Azure Container Registry..."
az acr create \
    --name "$ACR_NAME" \
    --resource-group "$RG" \
    --location "$LOC" \
    --sku Basic \
    --admin-enabled true \
    --output none 2>/dev/null || echo "✓ ACR already exists"
echo "✓ ACR created: $ACR_NAME"

# Step 4: Build and push Docker image to ACR
echo "[4/10] Building Docker image (this may take a few minutes)..."
az acr build \
    --registry "$ACR_NAME" \
    --image "${IMAGE_REPO}:${IMAGE_TAG}" \
    --image "${IMAGE_REPO}:latest" \
    --file Dockerfile \
    . \
    --output table
echo "✓ Image built and pushed: $IMAGE"

# Step 5: Get ACR credentials
echo "[5/10] Retrieving ACR credentials..."
ACR_URL="https://${ACR_NAME}.azurecr.io"
ACR_USER=$(az acr credential show --name "$ACR_NAME" --query username --output tsv)
ACR_PASS=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" --output tsv)
echo "✓ Credentials retrieved"

# Step 6: Create App Service Plan
echo "[6/10] Creating App Service Plan..."
az appservice plan create \
    --name "$PLAN" \
    --resource-group "$RG" \
    --location "$LOC" \
    --is-linux \
    --sku B2 \
    --output none 2>/dev/null || echo "✓ App Service Plan already exists"
echo "✓ App Service Plan ready"

# Step 7: Create Web App
echo "[7/10] Creating Web App..."
az webapp create \
    --name "$APP" \
    --resource-group "$RG" \
    --plan "$PLAN" \
    --deployment-container-image-name "$IMAGE" \
    --output none 2>/dev/null || echo "✓ Web App already exists"
echo "✓ Web App created: $APP"

# Step 8: Configure container settings
echo "[8/10] Configuring container registry access..."
az webapp config container set \
    --name "$APP" \
    --resource-group "$RG" \
    --docker-custom-image-name "$IMAGE" \
    --docker-registry-server-url "$ACR_URL" \
    --docker-registry-server-user "$ACR_USER" \
    --docker-registry-server-password "$ACR_PASS" \
    --output none
echo "✓ Container configured"

# Step 9: Configure application settings
echo "[9/10] Configuring application settings..."
az webapp config appsettings set \
    --name "$APP" \
    --resource-group "$RG" \
    --settings \
        WEBSITES_PORT=8080 \
        WG_MOCK_MODE=true \
        PAYMENTS_MOCK=true \
        RUN_MIGRATIONS=false \
        GUNICORN_TIMEOUT=120 \
        WEB_CONCURRENCY=2 \
        ACCESS_TOKEN_SECRET="$(openssl rand -hex 32)" \
        REFRESH_TOKEN_SECRET="$(openssl rand -hex 32)" \
        DATABASE_URL="sqlite:///./securewave.db" \
        APP_BASE_URL="https://${APP}.azurewebsites.net" \
        CORS_ORIGINS="https://${APP}.azurewebsites.net,http://localhost:3000" \
        STRIPE_SECRET_KEY="" \
        STRIPE_PRICE_ID="" \
        STRIPE_WEBHOOK_SECRET="" \
        PAYPAL_CLIENT_ID="" \
        PAYPAL_CLIENT_SECRET="" \
    --output none
echo "✓ Application settings configured"

# Step 10: Enable container logging
echo "[10/10] Enabling logging..."
az webapp log config \
    --name "$APP" \
    --resource-group "$RG" \
    --docker-container-logging filesystem \
    --level information \
    --output none 2>/dev/null || true
echo "✓ Logging enabled"

# Restart the app
echo ""
echo "Restarting application..."
az webapp restart \
    --name "$APP" \
    --resource-group "$RG" \
    --output none

echo ""
echo "================================================"
echo "✓ DEPLOYMENT COMPLETE"
echo "================================================"
echo ""
echo "Application URL: https://${APP}.azurewebsites.net"
echo "API Documentation: https://${APP}.azurewebsites.net/api/docs"
echo "Health Check: https://${APP}.azurewebsites.net/api/health"
echo ""
echo "Waiting 15 seconds for container to start..."
sleep 15

echo ""
echo "Testing endpoints..."
curl -s "https://${APP}.azurewebsites.net/api/health" && echo "" || echo "WARNING: Health check failed (container may still be starting)"

echo ""
echo "To view live logs, run:"
echo "  az webapp log tail --name $APP --resource-group $RG"
echo ""
echo "To update the deployment, run this script again."
echo "================================================"
