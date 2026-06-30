#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EMAIL_ENV_FILE="${SECUREWAVE_RELEASE_EMAIL_ENV_FILE:-$ROOT_DIR/securewave_private/release_email.env}"
BILLING_ENV_FILE="${SECUREWAVE_BILLING_RELEASE_ENV_FILE:-$ROOT_DIR/securewave_private/billing_release.env}"
GENERATE_MISSING_KEYS=false
DRY_RUN_TAG=false
RUN_EMAIL_PROOF=false
API_BASE="${SECUREWAVE_API_BASE_URL:-http://127.0.0.1:8000/api}"
PROOF_EMAIL="${SECUREWAVE_EMAIL_PROOF_EMAIL:-}"
PROOF_PASSWORD="${SECUREWAVE_EMAIL_PROOF_PASSWORD:-}"
PROOF_NEW_PASSWORD="${SECUREWAVE_EMAIL_PROOF_NEW_PASSWORD:-}"

usage() {
  cat <<'EOF'
Usage: bash scripts/release_go_no_go.sh [options]

Runs the composed SecureWave release gate without committing secrets:
email config status, billing config status, and scripts/release_preflight.sh.
It loads the ignored private env files for email and billing by default.

Options:
  --email-env-file PATH        Load this private email/release env file.
  --billing-env-file PATH      Load this private billing env file.
  --generate-missing-keys      Generate missing AUTH/WG Fernet keys for this run.
  --dry-run-tag                Use GITHUB_REF=refs/tags/v0.0.0 for local dry-runs.
  --email-live-proof           Run scripts/email_live_proof.py after release preflight.
  --api-base URL               API base for email live proof.
  --email EMAIL                Proof account email for live proof.
  --password PASSWORD          Proof account password for live proof.
  --new-password PASSWORD      New password used during reset proof.
  -h, --help                   Show this help.

Expected private files:
  securewave_private/release_email.env
  securewave_private/billing_release.env
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email-env-file)
      EMAIL_ENV_FILE="$2"
      shift 2
      ;;
    --billing-env-file)
      BILLING_ENV_FILE="$2"
      shift 2
      ;;
    --generate-missing-keys)
      GENERATE_MISSING_KEYS=true
      shift
      ;;
    --dry-run-tag)
      DRY_RUN_TAG=true
      shift
      ;;
    --email-live-proof)
      RUN_EMAIL_PROOF=true
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
      exit 1
    fi
    echo "[PASS] loaded private $label env file: $path"
  else
    echo "[WARN] private $label env file not found: $path"
  fi
}

generate_fernet_key() {
  "$(python_bin)" - <<'PY'
from cryptography.fernet import Fernet
print(Fernet.generate_key().decode())
PY
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

load_env_file "$EMAIL_ENV_FILE" "email"
load_env_file "$BILLING_ENV_FILE" "billing"

if [[ "$GENERATE_MISSING_KEYS" == "true" ]]; then
  generate_missing_keys
fi

if [[ "$DRY_RUN_TAG" == "true" && -z "${GITHUB_REF:-}" && -z "${GITHUB_REF_TYPE:-}" ]]; then
  export GITHUB_REF="refs/tags/v0.0.0"
  echo "[WARN] using dry-run release tag: $GITHUB_REF"
fi

email_args=(--env-file "$EMAIL_ENV_FILE" --skip-preflight --skip-billing-env)
billing_args=(--env-file "$BILLING_ENV_FILE")
preflight_args=(--release-preflight --skip-release-env-file)

if [[ "$DRY_RUN_TAG" == "true" ]]; then
  preflight_args+=(--dry-run-tag)
fi

echo "[STEP] email configuration"
bash scripts/email_release_gate.sh "${email_args[@]}"

echo "[STEP] billing configuration"
bash scripts/billing_release_gate.sh "${billing_args[@]}"

echo "[STEP] full release preflight"
bash scripts/billing_release_gate.sh "${billing_args[@]}" "${preflight_args[@]}"

if [[ "$RUN_EMAIL_PROOF" == "true" ]]; then
  proof_args=(--env-file "$EMAIL_ENV_FILE" --skip-preflight --live-proof --api-base "$API_BASE")
  [[ -n "$PROOF_EMAIL" ]] && proof_args+=(--email "$PROOF_EMAIL")
  [[ -n "$PROOF_PASSWORD" ]] && proof_args+=(--password "$PROOF_PASSWORD")
  [[ -n "$PROOF_NEW_PASSWORD" ]] && proof_args+=(--new-password "$PROOF_NEW_PASSWORD")
  echo "[STEP] email live proof"
  bash scripts/email_release_gate.sh "${proof_args[@]}"
fi

echo "OK: composed release go/no-go checks passed."
