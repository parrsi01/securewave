#!/usr/bin/env bash
set -euo pipefail

# Phase 2 - Backend Configuration for WireGuard live mode.
# This script only sets Azure App Service settings; it does not deploy code.

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI not found. Install az and login before running."
  exit 1
fi

if [[ -z "${AZURE_RESOURCE_GROUP:-}" || -z "${AZURE_APP_NAME:-}" ]]; then
  echo "Set AZURE_RESOURCE_GROUP and AZURE_APP_NAME before running."
  exit 1
fi

if [[ -z "${WG_ENCRYPTION_KEY:-}" ]]; then
  echo "Set WG_ENCRYPTION_KEY (Fernet key) before running."
  exit 1
fi

settings=(
  "WG_MOCK_MODE=false"
  "DEMO_MODE=false"
  "WG_DNS=${WG_DNS:-1.1.1.1,1.0.0.1}"
  "WG_DATA_DIR=${WG_DATA_DIR:-/tmp/wg_data}"
  "WG_ENCRYPTION_KEY=${WG_ENCRYPTION_KEY}"
  "WG_ENDPOINT=${WG_ENDPOINT:-}"
  "WG_SERVER_PUBLIC_KEY=${WG_SERVER_PUBLIC_KEY:-}"
  "WG_VM_NAME=${WG_VM_NAME:-securewave-wg}"
  "WG_RESOURCE_GROUP=${WG_RESOURCE_GROUP:-SecureWaveRG}"
  "WG_AUTO_REGISTER_PEERS=${WG_AUTO_REGISTER_PEERS:-true}"
  "WG_SSH_USER=${WG_SSH_USER:-azureuser}"
  "WG_SSH_KEY_PATH=${WG_SSH_KEY_PATH:-}"
  "WG_COMMAND_TIMEOUT=${WG_COMMAND_TIMEOUT:-30}"
)

filtered_settings=()
for setting in "${settings[@]}"; do
  if [[ "$setting" == *= && "${setting#*=}" == "" ]]; then
    continue
  fi
  filtered_settings+=("$setting")
done

echo "Applying WireGuard app settings to Azure App Service..."
az webapp config appsettings set \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$AZURE_APP_NAME" \
  --settings "${filtered_settings[@]}" \
  --output none

echo "Done. Restart the app if needed:"
echo "  az webapp restart --resource-group \"$AZURE_RESOURCE_GROUP\" --name \"$AZURE_APP_NAME\""
