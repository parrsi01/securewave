#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEFAULT_ENV_FILE="$ROOT_DIR/securewave_private/release_email.env"
ENV_FILE="${SECUREWAVE_RELEASE_EMAIL_ENV_FILE:-$DEFAULT_ENV_FILE}"
DEFAULT_BILLING_ENV_FILE="$ROOT_DIR/securewave_private/billing_release.env"
BILLING_ENV_FILE="${SECUREWAVE_BILLING_RELEASE_ENV_FILE:-$DEFAULT_BILLING_ENV_FILE}"
RUN_PREFLIGHT=true
RUN_LIVE_PROOF=false
WRITE_ENV_FILE=false
GENERATE_MISSING_KEYS=false
DRY_RUN_TAG=false
LOAD_BILLING_ENV=true
API_BASE="${SECUREWAVE_API_BASE_URL:-http://127.0.0.1:8000/api}"
PROOF_EMAIL="${SECUREWAVE_EMAIL_PROOF_EMAIL:-}"
PROOF_PASSWORD="${SECUREWAVE_EMAIL_PROOF_PASSWORD:-}"
PROOF_NEW_PASSWORD="${SECUREWAVE_EMAIL_PROOF_NEW_PASSWORD:-}"

usage() {
  cat <<'EOF'
Usage: bash scripts/email_release_gate.sh [options]

Automates the repeatable SecureWave email release checks without committing
secrets. By default it loads securewave_private/release_email.env when present.
When preflight is enabled, it also loads securewave_private/billing_release.env
so scripts/release_preflight.sh sees both email and billing configuration.

Options:
  --env-file PATH              Load/write this private env file.
  --billing-env-file PATH      Load this private billing env before preflight.
  --skip-billing-env           Do not load the private billing env before preflight.
  --write-env-file             Write the current email/release env to PATH.
  --generate-missing-keys      Generate missing AUTH/WG Fernet keys for this run.
  --dry-run-tag                Use GITHUB_REF=refs/tags/v0.0.0 when no release
                               tag is present, useful for env-only dry-runs.
  --skip-preflight             Do not run scripts/release_preflight.sh.
  --live-proof                 Run scripts/email_live_proof.py after preflight.
  --api-base URL               API base for live proof, default localhost /api.
  --email EMAIL                Proof account email for live proof.
  --password PASSWORD          Proof account password for live proof.
  --new-password PASSWORD      New password used during reset proof.
  -h, --help                   Show this help.

Expected private env file keys:
  EMAIL_PROVIDER, SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, FROM_EMAIL,
  FROM_NAME, APP_URL, AUTH_ENCRYPTION_KEY, WG_ENCRYPTION_KEY, DEMO_MODE,
  WG_MOCK_MODE

Optional live proof keys:
  SECUREWAVE_API_BASE_URL, SECUREWAVE_EMAIL_PROOF_EMAIL,
  SECUREWAVE_EMAIL_PROOF_PASSWORD, SECUREWAVE_EMAIL_PROOF_NEW_PASSWORD
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --billing-env-file)
      BILLING_ENV_FILE="$2"
      shift 2
      ;;
    --skip-billing-env)
      LOAD_BILLING_ENV=false
      shift
      ;;
    --write-env-file)
      WRITE_ENV_FILE=true
      shift
      ;;
    --generate-missing-keys)
      GENERATE_MISSING_KEYS=true
      shift
      ;;
    --dry-run-tag)
      DRY_RUN_TAG=true
      shift
      ;;
    --skip-preflight)
      RUN_PREFLIGHT=false
      shift
      ;;
    --live-proof)
      RUN_LIVE_PROOF=true
      shift
      ;;
    --api-base)
      API_BASE="$2"
      shift 2
      ;;
    --email)
      PROOF_EMAIL="$2"
      shift 2
      ;;
    --password)
      PROOF_PASSWORD="$2"
      shift 2
      ;;
    --new-password)
      PROOF_NEW_PASSWORD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

python_bin() {
  if [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
    echo "$ROOT_DIR/.venv/bin/python"
  else
    echo "python3"
  fi
}

generate_fernet_key() {
  "$(python_bin)" - <<'PY'
from cryptography.fernet import Fernet
print(Fernet.generate_key().decode())
PY
}

load_env_file() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    set +e
    set -a
    # shellcheck disable=SC1090
    source "$path"
    local source_code=$?
    set +a
    set -e
    if (( source_code != 0 )); then
      echo "ERROR: failed to load private $label env file: $path" >&2
      echo "FIX: quote values that contain spaces, for example FROM_NAME=\"SecureWave VPN\"" >&2
      exit 1
    fi
    echo "[PASS] loaded private $label env file: $path"
  else
    echo "[WARN] private $label env file not found: $path"
  fi
}

generate_missing_keys() {
  if [[ -z "${AUTH_ENCRYPTION_KEY:-}" ]]; then
    export AUTH_ENCRYPTION_KEY
    AUTH_ENCRYPTION_KEY="$(generate_fernet_key)"
    echo "[PASS] generated AUTH_ENCRYPTION_KEY for this run"
  fi
  if [[ -z "${WG_ENCRYPTION_KEY:-}" ]]; then
    export WG_ENCRYPTION_KEY
    WG_ENCRYPTION_KEY="$(generate_fernet_key)"
    echo "[PASS] generated WG_ENCRYPTION_KEY for this run"
  fi
}

write_env_file() {
  mkdir -p "$(dirname "$ENV_FILE")"
  umask 077
  {
    echo "# SecureWave release email environment. Do not commit."
    printf 'EMAIL_PROVIDER=%q\n' "${EMAIL_PROVIDER:-smtp}"
    printf 'SMTP_HOST=%q\n' "${SMTP_HOST:-}"
    printf 'SMTP_PORT=%q\n' "${SMTP_PORT:-587}"
    printf 'SMTP_USER=%q\n' "${SMTP_USER:-}"
    printf 'SMTP_PASSWORD=%q\n' "${SMTP_PASSWORD:-}"
    printf 'SMTP_FROM_EMAIL=%q\n' "${SMTP_FROM_EMAIL:-${FROM_EMAIL:-}}"
    printf 'SMTP_FROM_NAME=%q\n' "${SMTP_FROM_NAME:-${FROM_NAME:-SecureWave VPN}}"
    printf 'FROM_EMAIL=%q\n' "${FROM_EMAIL:-${SMTP_FROM_EMAIL:-}}"
    printf 'FROM_NAME=%q\n' "${FROM_NAME:-${SMTP_FROM_NAME:-SecureWave VPN}}"
    printf 'SENDGRID_API_KEY=%q\n' "${SENDGRID_API_KEY:-}"
    printf 'AWS_SES_REGION=%q\n' "${AWS_SES_REGION:-}"
    printf 'APP_URL=%q\n' "${APP_URL:-${APP_BASE_URL:-}}"
    printf 'APP_BASE_URL=%q\n' "${APP_BASE_URL:-${APP_URL:-}}"
    printf 'AUTH_ENCRYPTION_KEY=%q\n' "${AUTH_ENCRYPTION_KEY:-}"
    printf 'WG_ENCRYPTION_KEY=%q\n' "${WG_ENCRYPTION_KEY:-}"
    printf 'DEMO_MODE=%q\n' "${DEMO_MODE:-false}"
    printf 'WG_MOCK_MODE=%q\n' "${WG_MOCK_MODE:-false}"
    printf 'SECUREWAVE_API_BASE_URL=%q\n' "${SECUREWAVE_API_BASE_URL:-$API_BASE}"
    printf 'SECUREWAVE_EMAIL_PROOF_EMAIL=%q\n' "${SECUREWAVE_EMAIL_PROOF_EMAIL:-$PROOF_EMAIL}"
    printf 'SECUREWAVE_EMAIL_PROOF_PASSWORD=%q\n' "${SECUREWAVE_EMAIL_PROOF_PASSWORD:-$PROOF_PASSWORD}"
    printf 'SECUREWAVE_EMAIL_PROOF_NEW_PASSWORD=%q\n' "${SECUREWAVE_EMAIL_PROOF_NEW_PASSWORD:-$PROOF_NEW_PASSWORD}"
  } >"$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "[PASS] wrote private env file: $ENV_FILE"
}

print_email_status() {
  "$(python_bin)" - <<'PY'
from services.email_service import EmailService, redact_email

service = EmailService()
status = service.config_status()
print(f"[INFO] email provider: {status['provider']}")
print(f"[INFO] email enabled: {status['enabled']}")
missing = ",".join(status["missing"]) if status["missing"] else "none"
print(f"[INFO] email missing: {missing}")
from_email = status.get("from_email") or ""
print(f"[INFO] from email: {redact_email(from_email) if from_email else 'missing'}")
print(f"[INFO] app url configured: {status.get('app_url_configured')}")
PY
}

load_env_file "$ENV_FILE" "email"

if [[ "$RUN_PREFLIGHT" == "true" && "$LOAD_BILLING_ENV" == "true" ]]; then
  load_env_file "$BILLING_ENV_FILE" "billing"
fi

if [[ "$GENERATE_MISSING_KEYS" == "true" ]]; then
  generate_missing_keys
fi

if [[ "$WRITE_ENV_FILE" == "true" ]]; then
  write_env_file
fi

if [[ "$DRY_RUN_TAG" == "true" && -z "${GITHUB_REF:-}" && -z "${GITHUB_REF_TYPE:-}" ]]; then
  export GITHUB_REF="refs/tags/v0.0.0"
  echo "[WARN] using dry-run release tag: $GITHUB_REF"
fi

print_email_status

if [[ "$RUN_PREFLIGHT" == "true" ]]; then
  bash scripts/release_preflight.sh
fi

if [[ "$RUN_LIVE_PROOF" == "true" ]]; then
  args=(scripts/email_live_proof.py --api-base "$API_BASE")
  [[ -n "$PROOF_EMAIL" ]] && args+=(--email "$PROOF_EMAIL")
  [[ -n "$PROOF_PASSWORD" ]] && args+=(--password "$PROOF_PASSWORD")
  [[ -n "$PROOF_NEW_PASSWORD" ]] && args+=(--new-password "$PROOF_NEW_PASSWORD")
  "$(python_bin)" "${args[@]}"
fi
