"""Issue and revoke short-lived, per-device OpenVPN credentials safely."""

from __future__ import annotations

import base64
import hashlib
import os
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta

from cryptography.fernet import Fernet, InvalidToken
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models.openvpn_credential import OpenVpnCredential
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.openvpn_server_manager import get_openvpn_server_manager
from services.wireguard_server_manager import server_connection_from_db
from utils.env_validation import is_production, validate_fernet_key


class OpenVpnCredentialError(RuntimeError):
    """Safe error boundary for profile issuance and device revocation."""


@dataclass(frozen=True)
class IssuedOpenVpnCredential:
    username: str
    password: str
    expires_at: datetime
    credential_id: int


class OpenVpnCredentialManager:
    def __init__(self, db: Session):
        self.db = db
        self._fernet = self._load_fernet()

    @staticmethod
    def _load_fernet() -> Fernet:
        configured = os.getenv("WG_ENCRYPTION_KEY")
        issue = validate_fernet_key(configured)
        if not issue:
            return Fernet(configured.encode())
        if os.getenv("TESTING", "").lower() == "true":
            # A fixed test-only key keeps tests encrypted without quietly
            # allowing plaintext credentials in development or production.
            key = base64.urlsafe_b64encode(
                hashlib.sha256(b"securewave-openvpn-test-only-key").digest()
            )
            return Fernet(key)
        if is_production():
            raise OpenVpnCredentialError("OpenVPN credential encryption is not configured.")
        raise OpenVpnCredentialError("Set WG_ENCRYPTION_KEY before enabling OpenVPN.")

    @staticmethod
    def _ttl() -> timedelta:
        try:
            seconds = int(os.getenv("SECUREWAVE_OPENVPN_CREDENTIAL_TTL_SECONDS", "3600"))
        except ValueError:
            seconds = 3600
        return timedelta(seconds=max(60, min(seconds, 86400)))

    @staticmethod
    def _new_values() -> tuple[str, str, str, str]:
        username = "swovpn-" + secrets.token_hex(16)
        password = secrets.token_urlsafe(32)
        salt = secrets.token_hex(32)
        verifier = hashlib.sha256((salt + password).encode("utf-8")).hexdigest()
        return username, password, salt, verifier

    def _decrypt(self, value: str) -> str:
        try:
            return self._fernet.decrypt(value.encode()).decode("utf-8")
        except (InvalidToken, UnicodeDecodeError) as exc:
            raise OpenVpnCredentialError("Stored OpenVPN credential cannot be recovered.") from exc

    @staticmethod
    def _active_query(db: Session, *, user_id: int, device_id: int, server_id: int):
        return db.query(OpenVpnCredential).filter(
            OpenVpnCredential.user_id == user_id,
            OpenVpnCredential.device_id == device_id,
            OpenVpnCredential.server_id == server_id,
            OpenVpnCredential.is_active.is_(True),
            OpenVpnCredential.revoked_at.is_(None),
        )

    async def issue(
        self,
        *,
        user_id: int,
        peer: WireGuardPeer,
        server: VPNServer,
        force_rotate: bool = False,
    ) -> IssuedOpenVpnCredential:
        now = datetime.utcnow()
        # Locking the shared device row serializes WireGuard/OpenVPN profile
        # requests on PostgreSQL and avoids concurrent duplicate credentials.
        locked_peer = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.id == peer.id,
            WireGuardPeer.user_id == user_id,
            WireGuardPeer.is_active.is_(True),
            WireGuardPeer.is_revoked.is_(False),
        ).with_for_update().first()
        if locked_peer is None:
            raise OpenVpnCredentialError("VPN device is unavailable.")

        existing = self._active_query(
            self.db, user_id=user_id, device_id=peer.id, server_id=server.id
        ).order_by(OpenVpnCredential.issued_at.desc()).first()
        if (
            existing is not None
            and existing.expires_at > now
            and not force_rotate
        ):
            return IssuedOpenVpnCredential(
                username=existing.username,
                password=self._decrypt(existing.password_encrypted),
                expires_at=existing.expires_at,
                credential_id=existing.id,
            )

        username, password, salt, verifier = self._new_values()
        expires_at = now + self._ttl()
        remote = get_openvpn_server_manager()
        ok, _ = await remote.upsert_credential(
            server_connection_from_db(server),
            username=username,
            password_salt=salt,
            password_hash=verifier,
            expires_at_epoch=int(expires_at.timestamp()),
        )
        if not ok:
            raise OpenVpnCredentialError("OpenVPN credential registration could not be confirmed.")

        candidate = OpenVpnCredential(
            user_id=user_id,
            device_id=peer.id,
            server_id=server.id,
            username=username,
            password_encrypted=self._fernet.encrypt(password.encode()).decode(),
            password_salt=salt,
            password_hash=verifier,
            issued_at=now,
            expires_at=expires_at,
            remote_synced_at=now,
            is_active=True,
        )
        existing_remote_revoked = False
        try:
            if existing is not None:
                # A remote new credential is never allowed to leave an old
                # active credential behind after successful rotation.
                revoked, _ = await remote.revoke_credential(
                    server_connection_from_db(server), username=existing.username
                )
                if not revoked:
                    await remote.revoke_credential(
                        server_connection_from_db(server), username=username
                    )
                    raise OpenVpnCredentialError("OpenVPN credential rotation could not be confirmed.")
                existing_remote_revoked = True
                existing.is_active = False
                existing.revoked_at = now
            self.db.add(candidate)
            self.db.commit()
            self.db.refresh(candidate)
        except IntegrityError as exc:
            self.db.rollback()
            if existing is not None and existing_remote_revoked:
                await remote.upsert_credential(
                    server_connection_from_db(server),
                    username=existing.username,
                    password_salt=existing.password_salt,
                    password_hash=existing.password_hash,
                    expires_at_epoch=int(existing.expires_at.timestamp()),
                )
            await remote.revoke_credential(
                server_connection_from_db(server), username=username
            )
            # A concurrent request may have won. Re-read its valid credential
            # instead of emitting a duplicate server-side identity.
            winner = self._active_query(
                self.db, user_id=user_id, device_id=peer.id, server_id=server.id
            ).order_by(OpenVpnCredential.issued_at.desc()).first()
            if winner is not None and winner.expires_at > now:
                return IssuedOpenVpnCredential(
                    username=winner.username,
                    password=self._decrypt(winner.password_encrypted),
                    expires_at=winner.expires_at,
                    credential_id=winner.id,
                )
            raise OpenVpnCredentialError("OpenVPN credential issuance conflicted; retry.") from exc
        except Exception:
            self.db.rollback()
            if existing is not None and existing_remote_revoked:
                await remote.upsert_credential(
                    server_connection_from_db(server),
                    username=existing.username,
                    password_salt=existing.password_salt,
                    password_hash=existing.password_hash,
                    expires_at_epoch=int(existing.expires_at.timestamp()),
                )
            await remote.revoke_credential(
                server_connection_from_db(server), username=username
            )
            raise

        return IssuedOpenVpnCredential(
            username=candidate.username,
            password=password,
            expires_at=candidate.expires_at,
            credential_id=candidate.id,
        )

    async def revoke_device_credentials(self, *, user_id: int, peer: WireGuardPeer) -> None:
        active = self.db.query(OpenVpnCredential).filter(
            OpenVpnCredential.user_id == user_id,
            OpenVpnCredential.device_id == peer.id,
            OpenVpnCredential.is_active.is_(True),
            OpenVpnCredential.revoked_at.is_(None),
        ).all()
        now = datetime.utcnow()
        for credential in active:
            server = self.db.query(VPNServer).filter(VPNServer.id == credential.server_id).first()
            if server is None:
                raise OpenVpnCredentialError("OpenVPN credential server is unavailable.")
            ok, _ = await get_openvpn_server_manager().revoke_credential(
                server_connection_from_db(server), username=credential.username
            )
            if not ok:
                raise OpenVpnCredentialError("OpenVPN credential revocation could not be confirmed.")
            credential.is_active = False
            credential.revoked_at = now
        self.db.commit()
