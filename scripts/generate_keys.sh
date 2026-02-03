#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  PYTHON_BIN="python"
fi

"$PYTHON_BIN" - <<'PY'
from cryptography.fernet import Fernet

auth_key = Fernet.generate_key().decode()
wg_key = Fernet.generate_key().decode()

print(f"AUTH_ENCRYPTION_KEY={auth_key}")
print(f"WG_ENCRYPTION_KEY={wg_key}")
PY
