#!/usr/bin/env bash
set -euo pipefail

umask 077

TARGET_FILE="${1:-$HOME/.config/securewave/secrets.env}"
TARGET_DIR="$(cd "$(dirname "$TARGET_FILE")" && pwd)"
TARGET_BASENAME="$(basename "$TARGET_FILE")"
BACKUP_FILE=""

mkdir -p "$TARGET_DIR"
chmod 700 "$TARGET_DIR"

if [[ -f "$TARGET_FILE" ]]; then
  BACKUP_FILE="${TARGET_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  cp "$TARGET_FILE" "$BACKUP_FILE"
  chmod 600 "$BACKUP_FILE"
fi

tmp_file="$(mktemp "$TARGET_DIR/.${TARGET_BASENAME}.tmp.XXXXXX")"

python3 - "$TARGET_FILE" "$tmp_file" <<'PY'
from __future__ import annotations

import secrets
import sys
from pathlib import Path

from cryptography.fernet import Fernet


target_path = Path(sys.argv[1])
tmp_path = Path(sys.argv[2])

managed = {
    "JWT_SECRET": secrets.token_hex(32),
    "ACCESS_TOKEN_SECRET": secrets.token_hex(32),
    "REFRESH_TOKEN_SECRET": secrets.token_hex(32),
    "AUTH_ENCRYPTION_KEY": Fernet.generate_key().decode(),
    "WG_ENCRYPTION_KEY": Fernet.generate_key().decode(),
    "SECUREWAVE_PROVISIONING_TOKEN_SECRET": secrets.token_hex(32),
}

lines: list[str] = []
seen: set[str] = set()
if target_path.exists():
    for raw in target_path.read_text(encoding="utf-8").splitlines():
        if "=" not in raw or raw.lstrip().startswith("#"):
            lines.append(raw)
            continue
        key, _sep, _value = raw.partition("=")
        normalized = key.strip()
        if normalized in managed:
            lines.append(f"{normalized}={managed[normalized]}")
            seen.add(normalized)
        else:
            lines.append(raw)

for key, value in managed.items():
    if key not in seen:
        lines.append(f"{key}={value}")

tmp_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
PY

mv "$tmp_file" "$TARGET_FILE"
chmod 600 "$TARGET_FILE"

cat <<EOF
SecureWave secret rotation complete.
  Target file: $TARGET_FILE
  Backup file: ${BACKUP_FILE:-none}

Rotated values:
  - JWT_SECRET
  - ACCESS_TOKEN_SECRET
  - REFRESH_TOKEN_SECRET
  - AUTH_ENCRYPTION_KEY
  - WG_ENCRYPTION_KEY
  - SECUREWAVE_PROVISIONING_TOKEN_SECRET

Manual follow-up still required for externally managed credentials:
  - Stripe keys and webhook secrets
  - PayPal client secret
  - SMTP credentials
  - Hetzner / cloud provider API tokens
EOF
