#!/usr/bin/env python3
"""Create the owner-only credential file used by Linux live VPN proofs."""

from __future__ import annotations

import getpass
import os
from pathlib import Path
import tempfile


REPO_ROOT = Path(__file__).resolve().parents[1]
AUTH_PATH = REPO_ROOT / "securewave_private" / "live_certification_account.env"


def main() -> int:
    email = input("SecureWave live account email: ").strip()
    password = getpass.getpass("SecureWave live account password: ").strip()
    if not email or "@" not in email or not password:
        print("A valid email and non-empty password are required.")
        return 2

    AUTH_PATH.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(AUTH_PATH.parent, 0o700)
    fd, temporary_name = tempfile.mkstemp(
        prefix=".live-certification-account.",
        dir=AUTH_PATH.parent,
        text=True,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(f"SECUREWAVE_RUNTIME_PROBE_EMAIL={email}\n")
            output.write(f"SECUREWAVE_RUNTIME_PROBE_PASSWORD={password}\n")
        os.chmod(temporary_path, 0o600)
        temporary_path.replace(AUTH_PATH)
        os.chmod(AUTH_PATH, 0o600)
    finally:
        temporary_path.unlink(missing_ok=True)

    print(f"Live proof credentials saved with mode 0600: {AUTH_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
