#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${AZURE_RESOURCE_GROUP:-}" || -z "${AZURE_APP_NAME:-}" ]]; then
  echo "Missing Azure deployment configuration."
  echo "Set the required environment variables and try again:"
  echo "  1) az login"
  echo "  2) export AZURE_RESOURCE_GROUP=\"your-resource-group\""
  echo "  3) export AZURE_APP_NAME=\"your-app-name\""
  echo "  4) bash deploy_securewave_single_app.sh"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
ZIP_PATH="${ROOT_DIR}/deploy.zip"

rm -rf "${BUILD_DIR}" "${ZIP_PATH}"
mkdir -p "${BUILD_DIR}"

cp "${ROOT_DIR}/main.py" "${BUILD_DIR}/main.py"
cp -R "${ROOT_DIR}/routers" "${BUILD_DIR}/routers"
cp -R "${ROOT_DIR}/routes" "${BUILD_DIR}/routes"
cp -R "${ROOT_DIR}/services" "${BUILD_DIR}/services"
cp -R "${ROOT_DIR}/models" "${BUILD_DIR}/models"
cp -R "${ROOT_DIR}/database" "${BUILD_DIR}/database"
cp -R "${ROOT_DIR}/utils" "${BUILD_DIR}/utils"
if [[ -d "${ROOT_DIR}/securewave-tests" ]]; then
  cp -R "${ROOT_DIR}/securewave-tests" "${BUILD_DIR}/securewave-tests"
  rm -rf "${BUILD_DIR}/securewave-tests/results"
fi
cp -R "${ROOT_DIR}/alembic" "${BUILD_DIR}/alembic"
cp "${ROOT_DIR}/alembic.ini" "${BUILD_DIR}/alembic.ini"
cp "${ROOT_DIR}/requirements.txt" "${BUILD_DIR}/requirements.txt"

mkdir -p "${BUILD_DIR}/static"
cp -R "${ROOT_DIR}/static/"* "${BUILD_DIR}/static/"

if [[ -d "${ROOT_DIR}/frontend" ]]; then
  cp -R "${ROOT_DIR}/frontend/"* "${BUILD_DIR}/static/"
fi

cd "${BUILD_DIR}"
zip -r "${ZIP_PATH}" . -x "*.pyc" "__pycache__/*" "*.db" "*.sqlite" ".git/*" -q
cd "${ROOT_DIR}"

az webapp deploy \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AZURE_APP_NAME}" \
  --src-path "${ZIP_PATH}" \
  --type zip

az webapp config set \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AZURE_APP_NAME}" \
  --startup-file "bash /home/site/wwwroot/startup.sh"

az webapp restart --resource-group "${AZURE_RESOURCE_GROUP}" --name "${AZURE_APP_NAME}"

echo "Deployment complete."
echo "Tail logs with:"
echo "az webapp log tail --resource-group \"${AZURE_RESOURCE_GROUP}\" --name \"${AZURE_APP_NAME}\""
