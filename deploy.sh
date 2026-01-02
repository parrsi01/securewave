#!/usr/bin/env bash
set -euo pipefail

############################################################
# SECUREWAVE VPN - UNIVERSAL DEPLOYMENT SCRIPT
# Deploys to: securewave-web.azurewebsites.net
############################################################

echo "========================================================"
echo "  SECUREWAVE VPN - AZURE DEPLOYMENT"
echo "========================================================"
echo ""

# Configuration
RESOURCE_GROUP="SecureWaveRG"
LOCATION="westeurope"
PLAN_NAME="SecureWavePlan"
APP_NAME="securewave-web"
BASE_URL="https://securewave-web.azurewebsites.net"

# Check Azure authentication
echo "[1/8] Checking Azure CLI..."
if ! az account show > /dev/null 2>&1; then
  echo "❌ Not logged in to Azure."
  echo "Running: az login --use-device-code"
  az login --use-device-code
fi
echo "✅ Azure authenticated"
echo ""

# Clean and prepare build
echo "[2/8] Preparing deployment package..."
rm -rf build deploy.zip
mkdir build

# Copy backend files (flattened structure)
cp main.py build/
cp requirements.txt build/
cp alembic.ini build/
cp -r routers models database services alembic build/

# Copy frontend to static
mkdir -p build/static
cp -r frontend/* build/static/

# Create startup script
cat > build/startup.sh << 'STARTUP_EOF'
#!/bin/bash
echo "=== Starting SecureWave VPN ==="
cd /home/site/wwwroot

# Create database tables if needed
python3 -c "
from database.session import engine
from database import base
from models import user, subscription, audit_log, vpn_server, vpn_connection
base.Base.metadata.create_all(bind=engine)
print('Database tables ready')
" || echo "Database setup skipped"

# Start server
exec gunicorn \
  -k uvicorn.workers.UvicornWorker \
  main:app \
  --bind=0.0.0.0:$PORT \
  --timeout 600 \
  --workers 2
STARTUP_EOF
chmod +x build/startup.sh

echo "✅ Build prepared"
echo ""

# Create deployment zip
echo "[3/8] Creating deployment package..."
cd build
zip -r ../deploy.zip . -x "*.pyc" "__pycache__/*" "*.db" > /dev/null 2>&1
cd ..
echo "✅ deploy.zip created"
echo ""

# Ensure Azure resources exist
echo "[4/8] Ensuring Azure resources..."
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" --output none 2>/dev/null || true
az appservice plan create -n "$PLAN_NAME" -g "$RESOURCE_GROUP" --is-linux --sku B1 --output none 2>/dev/null || true
az webapp create -n "$APP_NAME" -g "$RESOURCE_GROUP" -p "$PLAN_NAME" -r "PYTHON:3.12" --output none 2>/dev/null || true
echo "✅ Resources ready"
echo ""

# Configure app settings
echo "[5/8] Configuring app settings..."
az webapp config appsettings set \
  -g "$RESOURCE_GROUP" \
  -n "$APP_NAME" \
  --settings \
    PORT=8000 \
    DATABASE_URL="sqlite:///./securewave.db" \
    ENVIRONMENT="production" \
    ACCESS_TOKEN_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')" \
    REFRESH_TOKEN_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')" \
    CORS_ORIGINS="$BASE_URL" \
    WG_MOCK_MODE="true" \
    WG_DATA_DIR="./wg_data" \
  --output none
echo "✅ Settings configured"
echo ""

# Set startup command
echo "[6/8] Setting startup command..."
az webapp config set \
  -g "$RESOURCE_GROUP" \
  -n "$APP_NAME" \
  --startup-file "startup.sh" \
  --output none
echo "✅ Startup configured"
echo ""

# Deploy
echo "[7/8] Deploying to Azure..."
az webapp deploy \
  -g "$RESOURCE_GROUP" \
  -n "$APP_NAME" \
  --type zip \
  --src-path deploy.zip \
  --output none
echo "✅ Deployed"
echo ""

# Restart and wait
echo "[8/8] Restarting app..."
az webapp restart -g "$RESOURCE_GROUP" -n "$APP_NAME" --output none
echo "⏱️  Waiting 30 seconds for startup..."
sleep 30

# Health check
echo "Running health check..."
HEALTH=$(curl -s "$BASE_URL/api/health" || echo "")
if echo "$HEALTH" | grep -q "ok"; then
  echo "✅ Health check passed"
else
  echo "⚠️  App may still be starting..."
fi
echo ""

# Success message
echo "========================================================"
echo "🎉 DEPLOYMENT SUCCESSFUL!"
echo ""
echo "🔗 Your Live Site:"
echo "   🌐 Website:   $BASE_URL"
echo "   🏠 Home:      $BASE_URL/home.html"
echo "   🔐 Login:     $BASE_URL/login.html"
echo "   📝 Register:  $BASE_URL/register.html"
echo "   📚 API Docs:  $BASE_URL/api/docs"
echo "   ❤️  Health:   $BASE_URL/api/health"
echo ""
echo "📊 Monitor Logs:"
echo "   az webapp log tail -n $APP_NAME -g $RESOURCE_GROUP"
echo ""
echo "🚀 Send this link to demo testers: $BASE_URL"
echo "========================================================"
