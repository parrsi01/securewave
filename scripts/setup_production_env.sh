#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_var() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "$value" ]]; then
    fail "$name is required. Set it in your production environment or .env file."
  fi
}

require_port() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "$value" ]]; then
    fail "$name is required for SMTP."
  fi
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    fail "$name must be numeric (got '$value')."
  fi
  if (( value < 1 || value > 65535 )); then
    fail "$name must be between 1 and 65535 (got '$value')."
  fi
}

ensure_python() {
  local python_bin="${PYTHON_BIN:-python3}"
  if ! command -v "$python_bin" >/dev/null 2>&1; then
    if command -v python >/dev/null 2>&1; then
      python_bin="python"
    else
      fail "python3 is required to validate Fernet keys. Install Python or set PYTHON_BIN."
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

validate_fernet() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "$value" ]]; then
    fail "$name is required. Generate with: python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'"
  fi
  local python_bin
  python_bin="$(ensure_python)"
  ensure_cryptography "$python_bin"
  if ! "$python_bin" - <<PY
from cryptography.fernet import Fernet
import sys
value = "${value}"
try:
    Fernet(value.encode())
except Exception as exc:
    print(f"Invalid {name}: {exc}")
    sys.exit(1)
PY
  then
    fail "$name is not a valid Fernet key. Regenerate with scripts/generate_keys.sh or the Fernet command."
  fi
}

provider="${EMAIL_PROVIDER:-}"
if [[ -z "$provider" ]]; then
  fail "EMAIL_PROVIDER is required. Supported: smtp, sendgrid, ses."
fi
provider="${provider,,}"

from_email="${FROM_EMAIL:-${SMTP_FROM_EMAIL:-${SMTP_USER:-}}}"

case "$provider" in
  smtp)
    require_var SMTP_HOST
    require_port SMTP_PORT
    require_var SMTP_USER
    require_var SMTP_PASSWORD
    if [[ -z "$from_email" ]]; then
      fail "FROM_EMAIL is required for SMTP (or set SMTP_FROM_EMAIL/SMTP_USER fallback)."
    fi
    ;;
  sendgrid)
    require_var SENDGRID_API_KEY
    if [[ -z "$from_email" ]]; then
      fail "FROM_EMAIL is required for SendGrid."
    fi
    ;;
  ses|aws_ses)
    require_var AWS_SES_REGION
    if [[ -z "$from_email" ]]; then
      fail "FROM_EMAIL is required for AWS SES."
    fi
    ;;
  *)
    fail "EMAIL_PROVIDER '$provider' is not supported. Use smtp, sendgrid, or ses."
    ;;
 esac

validate_fernet AUTH_ENCRYPTION_KEY
validate_fernet WG_ENCRYPTION_KEY

echo "OK: Production environment variables validated."
