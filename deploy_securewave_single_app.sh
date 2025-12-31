#!/usr/bin/env bash
set -euo pipefail

############################################
# SECUREWAVE — FOOLPROOF AZURE DEPLOY SCRIPT
# Single App: Frontend + Backend
############################################

RESOURCE_GROUP="SecureWaveRG"
LOCATION="westeurope"
PLAN_NAME="SecureWavePlan"
APP_NAME="securewave-app"
PYTHON_VERSION="PYTHON:3.12"
ZIP_NAME="deploy.zip"

echo "=== AZURE LOGIN ==="
az login --use-device-code

cd "$(dirname "$0")"

echo "=== CLEAN BUILD ==="
rm -rf build deploy.zip
mkdir build

echo "=== COPY BACKEND (FLATTENED) ==="
cp main.py build/
cp startup.sh build/
cp requirements.txt build/
cp alembic.ini build/
cp -r routers models database services alembic build/

echo "=== COPY FRONTEND → STATIC ==="
mkdir -p build/static
cp -r frontend/* build/static/

echo "=== ENSURE startup.sh ==="
cat > build/startup.sh << 'EOF'
#!/bin/bash
exec gunicorn \
  -k uvicorn.workers.UvicornWorker \
  main:app \
  --bind=0.0.0.0:$PORT \
  --timeout 600
EOF
chmod +x build/startup.sh

echo "=== BUILD ZIP ==="
cd build
zip -r ../deploy.zip . -x "*.pyc" "__pycache__/*"
cd ..

echo "=== AZURE RESOURCES ==="
az group create -n "$RESOURCE_GROUP" -l "$LOCATION"
az appservice plan create -n "$PLAN_NAME" -g "$RESOURCE_GROUP" --is-linux --sku B1 || true
az webapp create -n "$APP_NAME" -g "$RESOURCE_GROUP" -p "$PLAN_NAME" -r "$PYTHON_VERSION" || true

echo "=== APP SETTINGS ==="
az webapp config appsettings set \
  -g "$RESOURCE_GROUP" \
  -n "$APP_NAME" \
  --settings \
    PORT=8000 \
    DATABASE_URL="sqlite:///./securewave.db" \
    ACCESS_TOKEN_SECRET="dev" \
    REFRESH_TOKEN_SECRET="dev" \
    WG_MOCK_MODE="true"

echo "=== STARTUP COMMAND ==="
az webapp config set \
  -g "$RESOURCE_GROUP" \
  -n "$APP_NAME" \
  --startup-file "startup.sh"

echo "=== DEPLOY ZIP ==="
az webapp deploy \
  -g "$RESOURCE_GROUP" \
  -n "$APP_NAME" \
  --type zip \
  --src-path deploy.zip

echo "=== RESTART ==="
az webapp restart -g "$RESOURCE_GROUP" -n "$APP_NAME"

echo "======================================="
echo " DEPLOYED SUCCESSFULLY:"
echo " https://$APP_NAME.azurewebsites.net"
echo " Docs: /docs"
echo "======================================="