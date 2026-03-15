#!/usr/bin/env bash
set -euo pipefail

STRICT=false
if [[ "${1:-}" == "--strict" || "${VERIFY_STRICT:-}" == "true" ]]; then
  STRICT=true
fi

ENVIRONMENT_VALUE="${ENVIRONMENT:-}"
ENVIRONMENT_LOWER="${ENVIRONMENT_VALUE,,}"
ENFORCE_REQUIRED=false
if [[ "$STRICT" == "true" || "$ENVIRONMENT_LOWER" == "production" ]]; then
  ENFORCE_REQUIRED=true
fi

errors=0
warnings=0

log_error() {
  echo "ERROR: $*" >&2
  errors=$((errors + 1))
}

log_warning() {
  echo "WARN: $*" >&2
  warnings=$((warnings + 1))
}

require_var() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "$value" ]]; then
    if [[ "$ENFORCE_REQUIRED" == "true" ]]; then
      log_error "$name is required."
    else
      log_warning "$name is not set."
    fi
  fi
}

require_port() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "$value" ]]; then
    if [[ "$ENFORCE_REQUIRED" == "true" ]]; then
      log_error "$name is required for SMTP."
    else
      log_warning "$name is not set."
    fi
    return
  fi
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    log_error "$name must be numeric (got '$value')."
    return
  fi
  if (( value < 1 || value > 65535 )); then
    log_error "$name must be between 1 and 65535 (got '$value')."
  fi
}

ensure_python() {
  local python_bin="${PYTHON_BIN:-python3}"
  if ! command -v "$python_bin" >/dev/null 2>&1; then
    if command -v python >/dev/null 2>&1; then
      python_bin="python"
    else
      log_error "python3 is required to validate Fernet keys. Install Python or set PYTHON_BIN."
      echo ""
      return
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
    log_error "Python package 'cryptography' is required. Install with: pip install cryptography"
    return 1
  fi
}

validate_fernet() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "$value" ]]; then
    if [[ "$ENFORCE_REQUIRED" == "true" ]]; then
      log_error "$name is required."
    else
      log_warning "$name is not set."
    fi
    return
  fi
  local python_bin
  python_bin="$(ensure_python)"
  if [[ -z "$python_bin" ]]; then
    return
  fi
  if ! ensure_cryptography "$python_bin"; then
    return
  fi
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
    log_error "$name is not a valid Fernet key."
  fi
}

provider="${EMAIL_PROVIDER:-}"
if [[ -z "$provider" ]]; then
  if [[ "$ENFORCE_REQUIRED" == "true" ]]; then
    log_error "EMAIL_PROVIDER is required (smtp, sendgrid, ses)."
  else
    log_warning "EMAIL_PROVIDER is not set."
  fi
else
  provider="${provider,,}"
  from_email="${FROM_EMAIL:-${SMTP_FROM_EMAIL:-${SMTP_USER:-}}}"
  case "$provider" in
    smtp)
      require_var SMTP_HOST
      require_port SMTP_PORT
      require_var SMTP_USER
      require_var SMTP_PASSWORD
      if [[ -z "$from_email" ]]; then
        if [[ "$ENFORCE_REQUIRED" == "true" ]]; then
          log_error "FROM_EMAIL is required for SMTP (or set SMTP_FROM_EMAIL/SMTP_USER fallback)."
        else
          log_warning "FROM_EMAIL is not set for SMTP."
        fi
      fi
      ;;
    sendgrid)
      require_var SENDGRID_API_KEY
      if [[ -z "$from_email" ]]; then
        if [[ "$ENFORCE_REQUIRED" == "true" ]]; then
          log_error "FROM_EMAIL is required for SendGrid."
        else
          log_warning "FROM_EMAIL is not set for SendGrid."
        fi
      fi
      ;;
    ses|aws_ses)
      require_var AWS_SES_REGION
      if [[ -z "$from_email" ]]; then
        if [[ "$ENFORCE_REQUIRED" == "true" ]]; then
          log_error "FROM_EMAIL is required for AWS SES."
        else
          log_warning "FROM_EMAIL is not set for AWS SES."
        fi
      fi
      ;;
    *)
      if [[ "$ENFORCE_REQUIRED" == "true" ]]; then
        log_error "EMAIL_PROVIDER '$provider' is not supported."
      else
        log_warning "EMAIL_PROVIDER '$provider' is not supported."
      fi
      ;;
  esac
fi

validate_fernet AUTH_ENCRYPTION_KEY
validate_fernet WG_ENCRYPTION_KEY

for flag in PAYMENTS_MOCK DEMO_MODE WG_MOCK_MODE; do
  value="${!flag-}"
  if [[ "$ENVIRONMENT_LOWER" == "production" && "$value" =~ ^([Tt][Rr][Uu][Ee]|1|yes|on)$ ]]; then
    log_error "$flag must not be enabled in production."
  fi
done

if [[ "$ENVIRONMENT_LOWER" == "production" ]]; then
  require_var STRIPE_SECRET_KEY
  require_var STRIPE_PUBLISHABLE_KEY
  require_var STRIPE_WEBHOOK_SECRET
  require_var STRIPE_PRICE_BASIC_MONTHLY
  require_var STRIPE_PRICE_PREMIUM_MONTHLY
  require_var STRIPE_PRICE_ULTRA_MONTHLY
fi

# Guard against missing database configuration in production.
if [[ "$ENVIRONMENT_LOWER" == "production" ]]; then
  if [[ -z "${DATABASE_URL:-}" ]]; then
    log_error "DATABASE_URL is required for production (example: postgresql://user:pass@host:5432/securewave)."
  elif [[ "${ALLOW_SQLITE_PRODUCTION:-false}" != "true" && "${DATABASE_URL,,}" == sqlite* ]]; then
    log_error "DATABASE_URL points to SQLite. Set ALLOW_SQLITE_PRODUCTION=true only for an intentional fallback."
  fi
fi

echo "Verification mode: $([[ "$STRICT" == "true" ]] && echo strict || echo safe)"
echo "Errors: $errors"
echo "Warnings: $warnings"

if [[ $errors -gt 0 ]]; then
  exit 1
fi
