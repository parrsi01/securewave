#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEFAULT_ENV_FILE="$ROOT_DIR/securewave_private/billing_release.env"
ENV_FILE="${SECUREWAVE_BILLING_RELEASE_ENV_FILE:-$DEFAULT_ENV_FILE}"
WRITE_ENV_FILE=false
RUN_RELEASE_PREFLIGHT=false
DRY_RUN_TAG=false

usage() {
  cat <<'EOF'
Usage: bash scripts/billing_release_gate.sh [options]

Validates SecureWave billing/Stripe release configuration without committing
secrets. By default it loads securewave_private/billing_release.env when present
and checks Stripe keys, webhook secret, and Price IDs.

Options:
  --env-file PATH          Load/write this private env file.
  --write-env-file         Write current billing env to PATH with 0600 perms.
  --release-preflight      Also run scripts/release_preflight.sh. This requires
                           the full release env, including SMTP and Fernet keys.
  --dry-run-tag            Use GITHUB_REF=refs/tags/v0.0.0 when running release
                           preflight without a real tag.
  -h, --help               Show this help.

Expected private env file keys:
  PAYMENTS_MOCK=false
  DEMO_BILLING=false
  PAYMENT_PROVIDER=stripe
  STRIPE_SECRET_KEY=sk_live_...
  STRIPE_WEBHOOK_SECRET=whsec_...
  STRIPE_PUBLISHABLE_KEY=pk_live_...
  STRIPE_PRICE_BASIC_MONTHLY=price_...
  STRIPE_PRICE_BASIC_YEARLY=price_...
  STRIPE_PRICE_PREMIUM_MONTHLY=price_...
  STRIPE_PRICE_PREMIUM_YEARLY=price_...
  STRIPE_PRICE_ULTRA_MONTHLY=price_...
  STRIPE_PRICE_ULTRA_YEARLY=price_...
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --write-env-file)
      WRITE_ENV_FILE=true
      shift
      ;;
    --release-preflight)
      RUN_RELEASE_PREFLIGHT=true
      shift
      ;;
    --dry-run-tag)
      DRY_RUN_TAG=true
      shift
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

load_env_file() {
  if [[ -f "$ENV_FILE" ]]; then
    set +e
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    local source_code=$?
    set +a
    set -e
    if (( source_code != 0 )); then
      echo "ERROR: failed to load private env file: $ENV_FILE" >&2
      exit 1
    fi
    echo "[PASS] loaded private env file: $ENV_FILE"
  else
    echo "[WARN] private env file not found: $ENV_FILE"
  fi
}

write_env_file() {
  mkdir -p "$(dirname "$ENV_FILE")"
  umask 077
  {
    echo "# SecureWave billing release environment. Do not commit."
    printf 'PAYMENTS_MOCK=%q\n' "${PAYMENTS_MOCK:-false}"
    printf 'DEMO_BILLING=%q\n' "${DEMO_BILLING:-false}"
    printf 'PAYMENT_PROVIDER=%q\n' "${PAYMENT_PROVIDER:-stripe}"
    printf 'STRIPE_SECRET_KEY=%q\n' "${STRIPE_SECRET_KEY:-${STRIPE_SECRET:-}}"
    printf 'STRIPE_WEBHOOK_SECRET=%q\n' "${STRIPE_WEBHOOK_SECRET:-}"
    printf 'STRIPE_PUBLISHABLE_KEY=%q\n' "${STRIPE_PUBLISHABLE_KEY:-}"
    printf 'STRIPE_API_VERSION=%q\n' "${STRIPE_API_VERSION:-2026-02-25.clover}"
    printf 'STRIPE_PRICE_BASIC_MONTHLY=%q\n' "${STRIPE_PRICE_BASIC_MONTHLY:-}"
    printf 'STRIPE_PRICE_BASIC_YEARLY=%q\n' "${STRIPE_PRICE_BASIC_YEARLY:-}"
    printf 'STRIPE_PRICE_PREMIUM_MONTHLY=%q\n' "${STRIPE_PRICE_PREMIUM_MONTHLY:-}"
    printf 'STRIPE_PRICE_PREMIUM_YEARLY=%q\n' "${STRIPE_PRICE_PREMIUM_YEARLY:-}"
    printf 'STRIPE_PRICE_ULTRA_MONTHLY=%q\n' "${STRIPE_PRICE_ULTRA_MONTHLY:-}"
    printf 'STRIPE_PRICE_ULTRA_YEARLY=%q\n' "${STRIPE_PRICE_ULTRA_YEARLY:-}"
    printf 'STRIPE_AUTOMATIC_TAX=%q\n' "${STRIPE_AUTOMATIC_TAX:-false}"
  } >"$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "[PASS] wrote private env file: $ENV_FILE"
}

check_billing_config() {
  "$(python_bin)" - <<'PY'
from utils.env_validation import payment_config_issues
from services.stripe_service import StripeService

provider, missing = payment_config_issues()
status = StripeService.config_status()
print(f"[INFO] payment provider: {provider}")
print(f"[INFO] stripe enabled: {status['enabled']}")
print(f"[INFO] stripe api version: {status['api_version']}")
print(f"[INFO] stripe missing: {','.join(status['missing']) if status['missing'] else 'none'}")
print(f"[INFO] release missing: {','.join(missing) if missing else 'none'}")
if missing:
    raise SystemExit(1)
PY
}

load_env_file

if [[ "$WRITE_ENV_FILE" == "true" ]]; then
  write_env_file
fi

check_billing_config

if [[ "$DRY_RUN_TAG" == "true" && -z "${GITHUB_REF:-}" && -z "${GITHUB_REF_TYPE:-}" ]]; then
  export GITHUB_REF="refs/tags/v0.0.0"
  echo "[WARN] using dry-run release tag: $GITHUB_REF"
fi

if [[ "$RUN_RELEASE_PREFLIGHT" == "true" ]]; then
  bash scripts/release_preflight.sh
fi
