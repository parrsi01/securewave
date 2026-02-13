#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-development}"
ENVIRONMENT_LOWER="${ENVIRONMENT,,}"
STRICT_ENV=false
if [[ "$ENVIRONMENT_LOWER" == "production" || "$ENVIRONMENT_LOWER" == "staging" ]]; then
  STRICT_ENV=true
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  PYTHON_BIN="python"
fi

errors=0
warnings=0

log_error() {
  echo "ERROR: $*"
  errors=$((errors + 1))
}

log_warning() {
  echo "WARN: $*"
  warnings=$((warnings + 1))
}

require_var() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "${value}" ]]; then
    if [[ "$STRICT_ENV" == "true" ]]; then
      log_error "$name is required for $ENVIRONMENT_LOWER"
    else
      log_warning "$name is not set"
    fi
  fi
}

require_false() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "${value}" ]]; then
    if [[ "$STRICT_ENV" == "true" ]]; then
      log_error "$name must be explicitly set to false for $ENVIRONMENT_LOWER"
    else
      log_warning "$name is not set (defaults may apply)"
    fi
    return
  fi
  if [[ "${value,,}" != "false" ]]; then
    if [[ "$STRICT_ENV" == "true" ]]; then
      log_error "$name must be false for $ENVIRONMENT_LOWER (got $value)"
    else
      log_warning "$name is $value (expected false outside production)"
    fi
  fi
}

validate_fernet() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "${value}" ]]; then
    if [[ "$STRICT_ENV" == "true" ]]; then
      log_error "$name is required for $ENVIRONMENT_LOWER"
    else
      log_warning "$name is not set"
    fi
    return
  fi

  if ! "$PYTHON_BIN" - <<PY
from cryptography.fernet import Fernet
import sys
value = "${value}"
try:
    Fernet(value.encode())
except Exception as exc:
    print(f"{name} invalid: {exc}")
    sys.exit(1)
PY
  then
    if [[ "$STRICT_ENV" == "true" ]]; then
      log_error "$name is not a valid Fernet key"
    else
      log_warning "$name is not a valid Fernet key"
    fi
  fi
}

provider="${EMAIL_PROVIDER:-smtp}"
provider="${provider,,}"
if [[ "$STRICT_ENV" == "true" && -z "${EMAIL_PROVIDER:-}" ]]; then
  log_error "EMAIL_PROVIDER must be explicitly set for $ENVIRONMENT_LOWER"
fi

from_email="${FROM_EMAIL:-${SMTP_FROM_EMAIL:-${SMTP_USER:-}}}"

if [[ "$STRICT_ENV" == "true" ]]; then
  validate_fernet AUTH_ENCRYPTION_KEY
  validate_fernet WG_ENCRYPTION_KEY
  if [[ "${TESTING:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
    log_error "TESTING must not be true for $ENVIRONMENT_LOWER"
  fi
fi

if [[ "$provider" == "smtp" ]]; then
  require_var SMTP_HOST
  require_var SMTP_PORT
  require_var SMTP_USER
  require_var SMTP_PASSWORD
  if [[ -z "$from_email" ]]; then
    if [[ "$STRICT_ENV" == "true" ]]; then
      log_error "FROM_EMAIL (or SMTP_FROM_EMAIL/SMTP_USER fallback) is required"
    else
      log_warning "FROM_EMAIL (or SMTP_FROM_EMAIL/SMTP_USER fallback) is not set"
    fi
  fi
elif [[ "$provider" == "sendgrid" ]]; then
  require_var SENDGRID_API_KEY
  if [[ -z "$from_email" ]]; then
    if [[ "$STRICT_ENV" == "true" ]]; then
      log_error "FROM_EMAIL (or SMTP_FROM_EMAIL/SMTP_USER fallback) is required"
    else
      log_warning "FROM_EMAIL (or SMTP_FROM_EMAIL/SMTP_USER fallback) is not set"
    fi
  fi
elif [[ "$provider" == "ses" || "$provider" == "aws_ses" ]]; then
  require_var AWS_SES_REGION
  if [[ -z "$from_email" ]]; then
    if [[ "$STRICT_ENV" == "true" ]]; then
      log_error "FROM_EMAIL (or SMTP_FROM_EMAIL/SMTP_USER fallback) is required"
    else
      log_warning "FROM_EMAIL (or SMTP_FROM_EMAIL/SMTP_USER fallback) is not set"
    fi
  fi
else
  if [[ "$STRICT_ENV" == "true" ]]; then
    log_error "EMAIL_PROVIDER '$provider' is not supported"
  else
    log_warning "EMAIL_PROVIDER '$provider' is not supported"
  fi
fi

echo "Environment: $ENVIRONMENT_LOWER"
if [[ "$STRICT_ENV" == "true" ]]; then
  echo "Mode: strict"
else
  echo "Mode: non-strict"
fi

echo "Errors: $errors"
echo "Warnings: $warnings"

if [[ $errors -gt 0 ]]; then
  exit 1
fi
