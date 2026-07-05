#!/usr/bin/env bash
set -euo pipefail

# Create the ignored Flutter .env asset needed by flutter_dotenv during
# analyze, tests, and Linux packaging. The file is intentionally generated at
# runtime so local secrets are never committed.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_env="$repo_root/securewave_app/.env"
template="$repo_root/.env.example.flutter"

ensure_ci_linux_secret_headers() {
  if [[ "${CI:-false}" != "true" ]]; then
    return
  fi
  if [[ "$(uname -s)" != "Linux" ]]; then
    return
  fi
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libsecret-1; then
    return
  fi
  if ! command -v sudo >/dev/null 2>&1 || ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: libsecret-1 development headers are required for Flutter Linux CI builds." >&2
    exit 1
  fi
  sudo apt-get update
  sudo apt-get install -y libsecret-1-dev
}

ensure_ci_linux_secret_headers

if [[ -f "$app_env" && "${FORCE_FLUTTER_ENV:-false}" != "true" ]]; then
  echo "Flutter env already exists: securewave_app/.env"
  exit 0
fi

if [[ -f "$template" ]]; then
  cp "$template" "$app_env"
else
  cat > "$app_env" <<'ENV'
LIVE_API_BASE_URL=http://localhost:8000
SECUREWAVE_API_BASE_URL=http://localhost:8000/api
SECUREWAVE_PORTAL_URL=http://localhost:8000/account
SECUREWAVE_UPGRADE_URL=http://localhost:8000/subscription
SECUREWAVE_RESET_SESSION_ON_BOOT=false
ENV
fi

echo "Prepared Flutter env asset: securewave_app/.env"
