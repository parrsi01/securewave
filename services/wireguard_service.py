"""Small WireGuard key and private-key storage service for Beta 1."""

from __future__ import annotations

import base64
import os
import shutil
import subprocess  # nosec B404 - fixed WireGuard executable and arguments

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.serialization import (
    Encoding,
    NoEncryption,
    PrivateFormat,
    PublicFormat,
)

from utils.env_validation import is_production, validate_fernet_key


class WireGuardService:
    """Generate WireGuard keys and encrypt client private keys at rest."""

    def __init__(self) -> None:
        self.wg_path = shutil.which("wg")
        key = os.getenv("WG_ENCRYPTION_KEY")
        issue = validate_fernet_key(key)
        if issue and is_production():
            raise RuntimeError(f"WG_ENCRYPTION_KEY {issue} in production")
        self.fernet = Fernet(key.encode()) if key and not issue else None

    def generate_keypair(self) -> tuple[str, str]:
        if self.wg_path:
            private_key = subprocess.check_output(  # nosec B603
                [self.wg_path, "genkey"], text=True
            ).strip()
            public_key = subprocess.check_output(  # nosec B603
                [self.wg_path, "pubkey"], input=private_key, text=True
            ).strip()
            return private_key, public_key
        if is_production():
            raise RuntimeError("WireGuard key generation requires the wg executable in production")
        private = X25519PrivateKey.generate()
        private_bytes = private.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
        public_bytes = private.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
        return (
            base64.b64encode(private_bytes).decode(),
            base64.b64encode(public_bytes).decode(),
        )

    def encrypt_private_key(self, key: str) -> str:
        if self.fernet:
            return self.fernet.encrypt(key.encode()).decode()
        if is_production():
            raise RuntimeError("WG_ENCRYPTION_KEY is required in production")
        return base64.b64encode(key.encode()).decode()

    def decrypt_private_key(self, encrypted: str) -> str:
        if not encrypted:
            return ""
        if self.fernet:
            return self.fernet.decrypt(encrypted.encode()).decode()
        return base64.b64decode(encrypted.encode()).decode()
