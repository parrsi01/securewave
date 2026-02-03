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

# Guard against misconfigured SMTP, which breaks password reset and billing flows.
require_var "SMTP_HOST" 'export SMTP_HOST="smtp.example.com"'
require_var "SMTP_PORT" 'export SMTP_PORT="587"'
require_var "SMTP_USER" 'export SMTP_USER="smtp-user"'
require_var "SMTP_PASSWORD" 'export SMTP_PASSWORD="smtp-password"'

from_email="${FROM_EMAIL:-${SMTP_FROM_EMAIL:-}}"
if [[ -z "$from_email" ]]; then
  fail_with_fix "FROM_EMAIL is required for SMTP." 'export FROM_EMAIL="noreply@securewave.app"'
fi

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
    fail_with_fix "$name is required for release." "export ${name}=\"\\$(python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')\""
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

# Guard against Xcode project usage, which bypasses CocoaPods workspace.
project_refs=""
if command -v rg >/dev/null 2>&1; then
  project_refs="$(rg -n "Runner\.xcodeproj" -S . || true)"
else
  project_refs="$(grep -R -n "Runner\.xcodeproj" . || true)"
fi
if [[ -n "$project_refs" ]]; then
  fail_with_fix "Runner.xcodeproj reference detected." "python - <<'PY'
import pathlib
for path in pathlib.Path('.').rglob('*'):
    if path.is_file():
        text = path.read_text(errors='ignore')
        if 'Runner.xcodeproj' in text:
            path.write_text(text.replace('Runner.xcodeproj', 'Runner.xcworkspace'))
print('Replaced Runner.xcodeproj with Runner.xcworkspace')
PY"
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
