#!/usr/bin/env bash
set -euo pipefail

# setup_production_env.sh - Generate missing production secrets and print copy/paste exports.

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

ensure_python() {
  local python_bin="${PYTHON_BIN:-python3}"
  if ! command -v "$python_bin" >/dev/null 2>&1; then
    if command -v python >/dev/null 2>&1; then
      python_bin="python"
    else
      fail "python3 is required to generate Fernet keys. Install Python or set PYTHON_BIN."
    fi
  fi
  echo "$python_bin"
}

ensure_cryptography() {
  local python_bin="$1"
  if ! "$python_bin" - <<'PY'
try:
    import cryptography  # noqa: F401
except Exception:
    raise SystemExit(1)
PY
  then
    fail "Python package 'cryptography' is required. Install with: pip install cryptography"
  fi
}

generate_fernet_key() {
  local python_bin
  python_bin="$(ensure_python)"
  ensure_cryptography "$python_bin"
  "$python_bin" - <<'PY'
from cryptography.fernet import Fernet
print(Fernet.generate_key().decode())
PY
}

print_export() {
  local name="$1"
  local value="$2"
  local mask="${3:-false}"
  if [[ "$mask" == "true" ]]; then
    value="<set-in-secret-manager>"
  fi
  if [[ -z "$value" ]]; then
    value="<set-me>"
  fi
  echo "export ${name}=\"${value}\""
}

email_provider="${EMAIL_PROVIDER:-smtp}"
from_email="${FROM_EMAIL:-${SMTP_FROM_EMAIL:-}}"

auth_key="${AUTH_ENCRYPTION_KEY:-}"
wg_key="${WG_ENCRYPTION_KEY:-}"

if [[ -z "$auth_key" ]]; then
  # Guard against missing keys by generating new Fernet secrets.
  auth_key="$(generate_fernet_key)"
  echo "INFO: Generated AUTH_ENCRYPTION_KEY"
fi

if [[ -z "$wg_key" ]]; then
  # Guard against missing keys by generating new Fernet secrets.
  wg_key="$(generate_fernet_key)"
  echo "INFO: Generated WG_ENCRYPTION_KEY"
fi

cat <<'HEADER'
### SecureWave production environment exports
### Copy/paste into your shell or .env file as needed.
HEADER

print_export "ENVIRONMENT" "production"
print_export "DATABASE_URL" "${DATABASE_URL:-}"
print_export "EMAIL_PROVIDER" "$email_provider"
case "$email_provider" in
  sendgrid)
    print_export "SENDGRID_API_KEY" "${SENDGRID_API_KEY:-}" true
    print_export "FROM_EMAIL" "$from_email"
    ;;
  smtp)
    print_export "SMTP_HOST" "${SMTP_HOST:-}"
    print_export "SMTP_PORT" "${SMTP_PORT:-}"
    print_export "SMTP_USER" "${SMTP_USER:-}"
    print_export "SMTP_PASSWORD" "${SMTP_PASSWORD:-}" true
    print_export "FROM_EMAIL" "$from_email"
    ;;
  ses|aws_ses)
    print_export "AWS_SES_REGION" "${AWS_SES_REGION:-}"
    print_export "FROM_EMAIL" "$from_email"
    ;;
  *)
    print_export "FROM_EMAIL" "$from_email"
    ;;
esac
print_export "AUTH_ENCRYPTION_KEY" "$auth_key"
print_export "WG_ENCRYPTION_KEY" "$wg_key"

cat <<'FOOTER'
### Reminder: keep DEMO_MODE=false and WG_MOCK_MODE=false in production.
FOOTER
