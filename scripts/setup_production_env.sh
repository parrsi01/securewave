#!/usr/bin/env bash
set -euo pipefail

# setup_production_env.sh - Generate missing production secrets and print or write sourceable exports.

OUTPUT_FILE=""

usage() {
  cat <<'EOF'
Usage: bash scripts/setup_production_env.sh [--write-env-file path]

Generates any missing Fernet keys, emits sourceable export lines for the
SecureWave production environment, and leaves TODO comments for values that
must still come from a real secret manager or operator input.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-env-file)
      [[ $# -ge 2 ]] || fail "--write-env-file requires a path."
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

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
  local placeholder="${3:-<set-me>}"
  local rendered=""
  if [[ -n "$value" ]]; then
    printf -v rendered '%q' "$value"
    echo "export ${name}=${rendered}"
  else
    printf -v rendered '%q' "$placeholder"
    echo "# TODO: export ${name}=${rendered}"
  fi
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

lines=()
append_line() {
  lines+=("$1")
}

append_line "### SecureWave production environment exports"
append_line "### Source with: set -a && source <file> && set +a"
append_line "$(print_export "ENVIRONMENT" "production")"
append_line "$(print_export "EMAIL_PROVIDER" "$email_provider")"
append_line "$(print_export "DATABASE_URL" "${DATABASE_URL:-}" "postgresql+psycopg2://securewave:password@db.example.com:5432/securewave")"
append_line "$(print_export "SMTP_HOST" "${SMTP_HOST:-}" "smtp.example.com")"
append_line "$(print_export "SMTP_PORT" "${SMTP_PORT:-}" "587")"
append_line "$(print_export "SMTP_USER" "${SMTP_USER:-}" "smtp-user")"
append_line "$(print_export "SMTP_PASSWORD" "${SMTP_PASSWORD:-}" "<set-in-secret-manager>")"
append_line "$(print_export "FROM_EMAIL" "$from_email" "noreply@securewave.app")"
append_line "$(print_export "AUTH_ENCRYPTION_KEY" "$auth_key")"
append_line "$(print_export "WG_ENCRYPTION_KEY" "$wg_key")"
append_line "$(print_export "STRIPE_SECRET_KEY" "${STRIPE_SECRET_KEY:-}" "sk_live_...")"
append_line "$(print_export "STRIPE_PUBLISHABLE_KEY" "${STRIPE_PUBLISHABLE_KEY:-}" "pk_live_...")"
append_line "$(print_export "STRIPE_WEBHOOK_SECRET" "${STRIPE_WEBHOOK_SECRET:-}" "whsec_...")"
append_line "$(print_export "STRIPE_PRICE_BASIC_MONTHLY" "${STRIPE_PRICE_BASIC_MONTHLY:-}" "price_...")"
append_line "$(print_export "STRIPE_PRICE_PREMIUM_MONTHLY" "${STRIPE_PRICE_PREMIUM_MONTHLY:-}" "price_...")"
append_line "$(print_export "STRIPE_PRICE_ULTRA_MONTHLY" "${STRIPE_PRICE_ULTRA_MONTHLY:-}" "price_...")"
append_line "### Reminder: ensure TESTING is unset/false in production."

if [[ -n "$OUTPUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  printf '%s\n' "${lines[@]}" >"$OUTPUT_FILE"
  chmod 600 "$OUTPUT_FILE"
  echo "INFO: Wrote sourceable production env template to $OUTPUT_FILE"
else
  printf '%s\n' "${lines[@]}"
fi
