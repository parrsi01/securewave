#!/usr/bin/env bash
set -euo pipefail

# release_preflight.sh - Guardrail checks to prevent accidental misconfigured releases.

errors=0

fail_with_fix() {
  local message="$1"
  local fix="$2"
  echo "ERROR: $message" >&2
  echo "FIX:" >&2
  echo "$fix" >&2
  echo >&2
  errors=$((errors + 1))
}

require_var() {
  local name="$1"
  local value="${!name-}"
  local fix="$2"
  if [[ -z "$value" ]]; then
    fail_with_fix "$name is required for release." "$fix"
  fi
}

require_value() {
  local label="$1"
  local value="$2"
  local fix="$3"
  if [[ -z "$value" ]]; then
    fail_with_fix "$label is required for release." "$fix"
  fi
}

# Guard against misconfigured transactional email, which breaks verification,
# password reset, and billing flows.
email_provider="${EMAIL_PROVIDER:-smtp}"
email_provider="${email_provider,,}"
from_email="${FROM_EMAIL:-${SMTP_FROM_EMAIL:-${SMTP_USER:-}}}"
app_url="${APP_URL:-${APP_BASE_URL:-}}"

case "$email_provider" in
  smtp)
    require_var "SMTP_HOST" 'export SMTP_HOST="smtp.example.com"'
    require_var "SMTP_PORT" 'export SMTP_PORT="587"'
    require_var "SMTP_USER" 'export SMTP_USER="smtp-user"'
    require_var "SMTP_PASSWORD" 'export SMTP_PASSWORD="smtp-password"'
    if [[ -n "${SMTP_PORT:-}" && ! "${SMTP_PORT}" =~ ^[0-9]+$ ]]; then
      fail_with_fix "SMTP_PORT must be a numeric TCP port." 'export SMTP_PORT="587"'
    fi
    require_value "FROM_EMAIL or SMTP_FROM_EMAIL" "$from_email" 'export FROM_EMAIL="noreply@securewave.app"'
    ;;
  sendgrid)
    require_var "SENDGRID_API_KEY" 'export SENDGRID_API_KEY="SG...."'
    require_value "FROM_EMAIL or SMTP_FROM_EMAIL" "$from_email" 'export FROM_EMAIL="noreply@securewave.app"'
    ;;
  ses|aws_ses)
    require_var "AWS_SES_REGION" 'export AWS_SES_REGION="us-east-1"'
    require_value "FROM_EMAIL or SMTP_FROM_EMAIL" "$from_email" 'export FROM_EMAIL="noreply@securewave.app"'
    ;;
  *)
    fail_with_fix "EMAIL_PROVIDER '${email_provider}' is not supported." 'export EMAIL_PROVIDER="smtp" # or sendgrid / ses'
    ;;
esac

require_value "APP_URL or APP_BASE_URL" "$app_url" 'export APP_URL="https://securewave.app"'
if [[ "$app_url" == *"example.com"* ]]; then
  fail_with_fix "APP_URL must not point at an example domain." 'export APP_URL="https://securewave.app"'
fi

# Guard against fake or incomplete production billing.
payment_provider="${PAYMENT_PROVIDER:-stripe}"
payment_provider="${payment_provider,,}"
if [[ "${PAYMENTS_MOCK:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
  fail_with_fix "PAYMENTS_MOCK must be false for release." "export PAYMENTS_MOCK=false"
fi
if [[ "${DEMO_BILLING:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
  fail_with_fix "DEMO_BILLING must be false for release." "export DEMO_BILLING=false"
fi

case "$payment_provider" in
  stripe)
    stripe_key_value="${STRIPE_SECRET_KEY:-${STRIPE_SECRET:-}}"
    require_value "STRIPE_SECRET_KEY or STRIPE_SECRET" "$stripe_key_value" 'export STRIPE_SECRET_KEY="sk_live_..."'
    require_var "STRIPE_WEBHOOK_SECRET" 'export STRIPE_WEBHOOK_SECRET="whsec_..."'
    require_var "STRIPE_PUBLISHABLE_KEY" 'export STRIPE_PUBLISHABLE_KEY="pk_live_..."'
    require_var "STRIPE_PORTAL_CONFIG_ID" 'export STRIPE_PORTAL_CONFIG_ID="bpc_..."'
    if [[ -n "$stripe_key_value" && ! "$stripe_key_value" =~ ^(sk_live_|rk_live_) ]]; then
      fail_with_fix "Stripe secret key must be a live-mode key." 'export STRIPE_SECRET_KEY="sk_live_..."'
    fi
    if [[ -n "${STRIPE_WEBHOOK_SECRET:-}" && ! "${STRIPE_WEBHOOK_SECRET}" =~ ^whsec_ ]]; then
      fail_with_fix "STRIPE_WEBHOOK_SECRET must be a webhook signing secret." 'export STRIPE_WEBHOOK_SECRET="whsec_..."'
    fi
    if [[ -n "${STRIPE_PUBLISHABLE_KEY:-}" && ! "${STRIPE_PUBLISHABLE_KEY}" =~ ^pk_live_ ]]; then
      fail_with_fix "STRIPE_PUBLISHABLE_KEY must be a live-mode publishable key." 'export STRIPE_PUBLISHABLE_KEY="pk_live_..."'
    fi
    if [[ -n "${STRIPE_PORTAL_CONFIG_ID:-}" && ! "${STRIPE_PORTAL_CONFIG_ID}" =~ ^bpc_ ]]; then
      fail_with_fix "STRIPE_PORTAL_CONFIG_ID must be a Stripe Customer Portal configuration ID." 'export STRIPE_PORTAL_CONFIG_ID="bpc_..."'
    fi
    for plan in BASIC PREMIUM ULTRA; do
      for cycle in MONTHLY YEARLY; do
        price_var="STRIPE_PRICE_${plan}_${cycle}"
        price_value="${!price_var-}"
        require_var "$price_var" "export ${price_var}=price_..."
        if [[ -n "$price_value" && ! "$price_value" =~ ^price_ ]]; then
          fail_with_fix "$price_var must be a Stripe Price ID." "export ${price_var}=price_..."
        fi
      done
    done
    ;;
  paypal)
    require_var "PAYPAL_CLIENT_ID" 'export PAYPAL_CLIENT_ID="..."'
    require_var "PAYPAL_CLIENT_SECRET" 'export PAYPAL_CLIENT_SECRET="..."'
    if [[ "${PAYPAL_MODE:-}" != "live" ]]; then
      fail_with_fix "PAYPAL_MODE must be live for release." 'export PAYPAL_MODE=live'
    fi
    ;;
  *)
    fail_with_fix "PAYMENT_PROVIDER '${payment_provider}' is not supported." 'export PAYMENT_PROVIDER="stripe"'
    ;;
esac

ensure_python() {
  local python_bin="${PYTHON_BIN:-python3}"
  if ! command -v "$python_bin" >/dev/null 2>&1; then
    if command -v python >/dev/null 2>&1; then
      python_bin="python"
    else
      fail_with_fix "python3 is required to validate Fernet keys." "sudo apt-get install -y python3"
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
    fail_with_fix "Python package 'cryptography' is required." "python -m pip install cryptography"
    return 1
  fi
}

validate_fernet() {
  local name="$1"
  local value="${!name-}"
  if [[ -z "$value" ]]; then
    fail_with_fix "$name is required for release." "Run: bash scripts/generate_keys.sh; then export ${name}=<generated-fernet-key>"
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
  if ! NAME="$name" VALUE="$value" "$python_bin" - <<'PY'
from cryptography.fernet import Fernet
import os
import sys
name = os.environ["NAME"]
value = os.environ["VALUE"]
try:
    Fernet(value.encode())
except Exception as exc:
    print(f"Invalid {name}: {exc}")
    sys.exit(1)
PY
  then
    fail_with_fix "$name is invalid." "bash scripts/generate_keys.sh"
  fi
}

# Guard against invalid encryption keys so secrets are not stored unrecoverably.
validate_fernet "AUTH_ENCRYPTION_KEY"
validate_fernet "WG_ENCRYPTION_KEY"

# Guard against accidentally releasing demo or mock tunnels.
if [[ "${DEMO_MODE:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
  fail_with_fix "DEMO_MODE must be false for release." "export DEMO_MODE=false"
fi
if [[ "${WG_MOCK_MODE:-false}" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
  fail_with_fix "WG_MOCK_MODE must be false for release." "export WG_MOCK_MODE=false"
fi

# Guard against Xcode project usage in build commands (not documentation warnings).
# We explicitly allow mentions in .md files, guard scripts, and error messages.
check_xcodeproj_misuse() {
  local bad_refs=""
  # Only check CI workflows for actual -project Runner.xcodeproj build commands
  if command -v rg >/dev/null 2>&1; then
    bad_refs="$(rg -n "\-project.*Runner\.xcodeproj" .github/workflows/*.yml 2>/dev/null || true)"
  else
    bad_refs="$(grep -r -n "\-project.*Runner\.xcodeproj" .github/workflows/*.yml 2>/dev/null || true)"
  fi
  echo "$bad_refs"
}
project_misuse="$(check_xcodeproj_misuse)"
if [[ -n "$project_misuse" ]]; then
  fail_with_fix "xcodebuild -project Runner.xcodeproj found in CI workflow." "Use -workspace Runner.xcworkspace in CI build commands"
fi

# Guard against non-versioned releases by enforcing v* tags.
release_tag=""
if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  release_tag="${GITHUB_REF#refs/tags/}"
elif [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" == v* ]]; then
  release_tag="${GITHUB_REF_NAME}"
elif command -v git >/dev/null 2>&1; then
  release_tag="$(git tag --points-at HEAD --list 'v*' | head -n 1)"
fi
if [[ -z "$release_tag" ]]; then
  fail_with_fix "Release must be built from a v* tag." "git tag vX.Y.Z && git push origin vX.Y.Z"
fi

if [[ $errors -gt 0 ]]; then
  exit 1
fi

echo "OK: Release preflight checks passed."
