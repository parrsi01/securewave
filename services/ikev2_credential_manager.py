"""Issue and revoke short-lived, per-device IKEv2 EAP credentials safely."""

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

from models.ikev2_credential import Ikev2Credential
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.ikev2_server_manager import get_ikev2_server_manager
from services.wireguard_server_manager import server_connection_from_db
from utils.env_validation import is_production, validate_fernet_key


class Ikev2CredentialError(RuntimeError):
    """Safe error boundary for IKEv2 profile issuance and revocation."""


@dataclass(frozen=True)
class IssuedIkev2Credential:
    username: str
    password: str
    expires_at: datetime
    credential_id: int


class Ikev2CredentialManager:
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
            key = base64.urlsafe_b64encode(
                hashlib.sha256(b"securewave-ikev2-test-only-key").digest()
            )
            return Fernet(key)
        if is_production():
            raise Ikev2CredentialError("IKEv2 credential encryption is not configured.")
        raise Ikev2CredentialError("Set WG_ENCRYPTION_KEY before enabling IKEv2.")

    @staticmethod
    def _ttl() -> timedelta:
        try:
            seconds = int(os.getenv("SECUREWAVE_IKEV2_CREDENTIAL_TTL_SECONDS", "3600"))
        except ValueError:
            seconds = 3600
        return timedelta(seconds=max(60, min(seconds, 86400)))

    @staticmethod
    def _new_values() -> tuple[str, str]:
        # token_urlsafe uses only characters accepted by NM's strongSwan
        # property parser and the fixed server credential helper.
        return "swikev2-" + secrets.token_hex(16), secrets.token_urlsafe(32)

    def _decrypt(self, value: str) -> str:
        try:
            return self._fernet.decrypt(value.encode()).decode("utf-8")
        except (InvalidToken, UnicodeDecodeError) as exc:
            raise Ikev2CredentialError("Stored IKEv2 credential cannot be recovered.") from exc

    @staticmethod
    def _active_query(db: Session, *, user_id: int, device_id: int, server_id: int):
        return db.query(Ikev2Credential).filter(
            Ikev2Credential.user_id == user_id,
            Ikev2Credential.device_id == device_id,
            Ikev2Credential.server_id == server_id,
            Ikev2Credential.is_active.is_(True),
            Ikev2Credential.revoked_at.is_(None),
        )

    async def issue(
        self,
        *,
        user_id: int,
        peer: WireGuardPeer,
        server: VPNServer,
        force_rotate: bool = False,
    ) -> IssuedIkev2Credential:
        now = datetime.utcnow()
        # Serialize profile requests on the shared device row.  This also
        # avoids an IKEv2/OpenVPN profile race producing duplicate active
        # credentials on PostgreSQL.
        locked_peer = self.db.query(WireGuardPeer).filter(
            WireGuardPeer.id == peer.id,
            WireGuardPeer.user_id == user_id,
            WireGuardPeer.is_active.is_(True),
            WireGuardPeer.is_revoked.is_(False),
        ).with_for_update().first()
        if locked_peer is None:
            raise Ikev2CredentialError("VPN device is unavailable.")

        existing = self._active_query(
            self.db, user_id=user_id, device_id=peer.id, server_id=server.id
        ).order_by(Ikev2Credential.issued_at.desc()).first()
        if existing is not None and existing.expires_at > now and not force_rotate:
            return IssuedIkev2Credential(
                username=existing.username,
                password=self._decrypt(existing.password_encrypted),
                expires_at=existing.expires_at,
                credential_id=existing.id,
            )

        username, password = self._new_values()
        expires_at = now + self._ttl()
        remote = get_ikev2_server_manager()
        connection = server_connection_from_db(server)
        ok, _ = await remote.upsert_credential(
            connection, username=username, password=password
        )
        if not ok:
            raise Ikev2CredentialError("IKEv2 credential registration could not be confirmed.")

        candidate = Ikev2Credential(
            user_id=user_id,
            device_id=peer.id,
            server_id=server.id,
            username=username,
            password_encrypted=self._fernet.encrypt(password.encode()).decode(),
            issued_at=now,
            expires_at=expires_at,
            remote_synced_at=now,
            is_active=True,
        )
        existing_remote_revoked = False
        try:
            if existing is not None:
                revoked, _ = await remote.revoke_credential(
                    connection, username=existing.username
                )
                if not revoked:
                    await remote.revoke_credential(connection, username=username)
                    raise Ikev2CredentialError("IKEv2 credential rotation could not be confirmed.")
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
                    connection,
                    username=existing.username,
                    password=self._decrypt(existing.password_encrypted),
                )
            await remote.revoke_credential(connection, username=username)
            winner = self._active_query(
                self.db, user_id=user_id, device_id=peer.id, server_id=server.id
            ).order_by(Ikev2Credential.issued_at.desc()).first()
            if winner is not None and winner.expires_at > now:
                return IssuedIkev2Credential(
                    username=winner.username,
                    password=self._decrypt(winner.password_encrypted),
                    expires_at=winner.expires_at,
                    credential_id=winner.id,
                )
            raise Ikev2CredentialError("IKEv2 credential issuance conflicted; retry.") from exc
        except Exception:
            self.db.rollback()
            if existing is not None and existing_remote_revoked:
                await remote.upsert_credential(
                    connection,
                    username=existing.username,
                    password=self._decrypt(existing.password_encrypted),
                )
            await remote.revoke_credential(connection, username=username)
            raise

        return IssuedIkev2Credential(
            username=candidate.username,
            password=password,
            expires_at=candidate.expires_at,
            credential_id=candidate.id,
        )

    async def revoke_device_credentials(self, *, user_id: int, peer: WireGuardPeer) -> None:
        active = self.db.query(Ikev2Credential).filter(
            Ikev2Credential.user_id == user_id,
            Ikev2Credential.device_id == peer.id,
            Ikev2Credential.is_active.is_(True),
            Ikev2Credential.revoked_at.is_(None),
        ).all()
        now = datetime.utcnow()
        remote = get_ikev2_server_manager()
        for credential in active:
            server = self.db.query(VPNServer).filter(
                VPNServer.id == credential.server_id
            ).first()
            if server is None:
                raise Ikev2CredentialError("IKEv2 credential server is unavailable.")
            ok, _ = await remote.revoke_credential(
                server_connection_from_db(server), username=credential.username
            )
            if not ok:
                raise Ikev2CredentialError("IKEv2 credential revocation could not be confirmed.")
            credential.is_active = False
            credential.revoked_at = now
        self.db.commit()
