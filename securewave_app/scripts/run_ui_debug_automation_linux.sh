#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

STAMP="$(date -u +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="$ROOT_DIR/build/ui_automation"
LOG_FILE="$ARTIFACT_DIR/ui_debug_smoke_${STAMP}.log"
ACCOUNT_FILE="$ARTIFACT_DIR/latest-account.env"

mkdir -p "$ARTIFACT_DIR"

CREATE_ACCOUNT="${SECUREWAVE_E2E_CREATE_ACCOUNT:-}"
MOCK_VPN="${SECUREWAVE_MOCK_VPN:-true}"

if [[ -n "${SECUREWAVE_E2E_EMAIL:-}" && -n "${SECUREWAVE_E2E_PASSWORD:-}" ]]; then
  EMAIL="$SECUREWAVE_E2E_EMAIL"
  PASSWORD="$SECUREWAVE_E2E_PASSWORD"
  CREATE_ACCOUNT="${CREATE_ACCOUNT:-false}"
elif [[ "${SECUREWAVE_FORCE_NEW_ACCOUNT:-false}" != "true" && -f "$ACCOUNT_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ACCOUNT_FILE"
  EMAIL="${SECUREWAVE_E2E_EMAIL}"
  PASSWORD="${SECUREWAVE_E2E_PASSWORD}"
  CREATE_ACCOUNT="${CREATE_ACCOUNT:-false}"
else
  EMAIL="codex.auto.${STAMP}@example.com"
  PASSWORD="${SECUREWAVE_E2E_PASSWORD:-Securewave123!}"
  CREATE_ACCOUNT="${CREATE_ACCOUNT:-true}"
fi

cat <<EOF
SecureWave UI automation
  Email:    $EMAIL
  Password: ***
  Register: $CREATE_ACCOUNT
  Log file: $LOG_FILE
EOF

flutter pub get

flutter test integration_test/ui_debug_smoke_test.dart \
  -d linux \
  --reporter expanded \
  --dart-define=SECUREWAVE_UI_AUTOMATION=true \
  --dart-define=SECUREWAVE_MOCK_VPN="$MOCK_VPN" \
  --dart-define=SECUREWAVE_E2E_CREATE_ACCOUNT="$CREATE_ACCOUNT" \
  --dart-define=SECUREWAVE_E2E_EMAIL="$EMAIL" \
  --dart-define=SECUREWAVE_E2E_PASSWORD="$PASSWORD" | tee "$LOG_FILE"

printf 'SECUREWAVE_E2E_EMAIL=%s\nSECUREWAVE_E2E_PASSWORD=%s\n' \
  "$EMAIL" \
  "$PASSWORD" > "$ACCOUNT_FILE"

cat <<EOF
UI automation completed.
Latest account file: $ACCOUNT_FILE
EOF
