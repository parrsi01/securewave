from __future__ import annotations

import base64
import logging
import os
import secrets
from dataclasses import dataclass
from typing import Optional

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.orm import Session

from models.vpn_credential import VPNCredential
from utils.env_validation import validate_fernet_key, is_production

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class VpnProtocolCredentials:
    username: str
    password: str
    created: bool


class VpnCredentialService:
    """
    Manage per-device VPN credentials for non-WireGuard protocols.

    Credentials are encrypted at rest using AUTH_ENCRYPTION_KEY (preferred)
    or WG_ENCRYPTION_KEY (fallback).
    """

    def __init__(self, db: Session):
        self.db = db
        self.fernet = self._load_fernet()

    def _load_fernet(self) -> Optional[Fernet]:
        key = (os.getenv("AUTH_ENCRYPTION_KEY") or os.getenv("WG_ENCRYPTION_KEY") or "").strip()
        issue = validate_fernet_key(key)
        if issue:
            if is_production():
                raise RuntimeError(f"AUTH_ENCRYPTION_KEY/WG_ENCRYPTION_KEY {issue} in production")
            logger.warning("Credential encryption key %s; using base64 fallback", issue)
            return None
        return Fernet(key.encode())

    def _encrypt(self, value: str) -> str:
        if self.fernet:
            return self.fernet.encrypt(value.encode("utf-8")).decode("utf-8")
        return base64.b64encode(value.encode("utf-8")).decode("utf-8")

    def _decrypt(self, value: str) -> str:
        if not value:
            return ""
        if self.fernet:
            try:
                return self.fernet.decrypt(value.encode("utf-8")).decode("utf-8")
            except InvalidToken:
                # Fall through to base64/plain for dev/test migrations.
                pass
        try:
            return base64.b64decode(value.encode("utf-8")).decode("utf-8")
        except Exception:
            return value

    @staticmethod
    def _generate_username() -> str:
        # Keep to safe characters for shell scripts and legacy auth backends.
        return f"sw_{secrets.token_hex(10)}"

    @staticmethod
    def _generate_password() -> str:
        # URL-safe base64; avoids quotes/whitespace for scripting and config formats.
        return secrets.token_urlsafe(24)

    def get_or_create(
        self,
        *,
        user_id: int,
        device_id: int,
        server_id: int,
        protocol: str,
    ) -> VpnProtocolCredentials:
        normalized = (protocol or "").strip().lower()
        if normalized not in {"openvpn", "ikev2"}:
            raise ValueError("Unsupported credential protocol")

        existing = (
            self.db.query(VPNCredential)
            .filter(
                VPNCredential.user_id == user_id,
                VPNCredential.device_id == device_id,
                VPNCredential.server_id == server_id,
                VPNCredential.protocol == normalized,
            )
            .first()
        )
        if existing:
            return VpnProtocolCredentials(
                username=existing.username,
                password=self._decrypt(existing.password_encrypted),
                created=False,
            )

        username = self._generate_username()
        password = self._generate_password()
        record = VPNCredential(
            user_id=user_id,
            device_id=device_id,
            server_id=server_id,
            protocol=normalized,
            username=username,
            password_encrypted=self._encrypt(password),
        )
        self.db.add(record)
        self.db.commit()
        self.db.refresh(record)

        return VpnProtocolCredentials(username=username, password=password, created=True)
