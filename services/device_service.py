from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from models.vpn_credential import VPNCredential
from models.vpn_server import VPNServer
from models.wireguard_peer import (
    DEVICE_STATE_ACTIVE,
    DEVICE_STATE_EXPIRED,
    DEVICE_STATE_REVOKED,
    WireGuardPeer,
)
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
)
from services.vpn_credential_service import VpnCredentialService
from utils.time_utils import utcnow

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class DeviceCleanupSummary:
    expired: int = 0

    def to_dict(self) -> dict[str, int]:
        return {"expired": self.expired}


class DeviceService:
    """Centralize device lifecycle updates and remote peer cleanup."""

    def __init__(self, db: Session):
        self.db = db

    @staticmethod
    def _to_naive_utc(value: Optional[datetime]) -> Optional[datetime]:
        if value is None:
            return None
        if value.tzinfo is None:
            return value
        return value.astimezone(timezone.utc).replace(tzinfo=None)

    def _set_state(
        self,
        peer: WireGuardPeer,
        *,
        state: str,
        profile_expires_at: Optional[datetime] = None,
        revoked_at: Optional[datetime] = None,
    ) -> WireGuardPeer:
        peer.device_state = state
        peer.is_revoked = state == DEVICE_STATE_REVOKED
        peer.is_active = state == DEVICE_STATE_ACTIVE
        peer.profile_expires_at = self._to_naive_utc(profile_expires_at)
        peer.revoked_at = self._to_naive_utc(revoked_at)
        self.db.add(peer)
        return peer

    def mark_profile_issued(
        self,
        peer: WireGuardPeer,
        *,
        profile_expires_at: Optional[datetime],
        commit: bool = True,
    ) -> WireGuardPeer:
        self._set_state(
            peer,
            state=DEVICE_STATE_ACTIVE,
            profile_expires_at=profile_expires_at,
            revoked_at=None,
        )
        if commit:
            self.db.commit()
            self.db.refresh(peer)
        return peer

    def mark_expired(
        self,
        peer: WireGuardPeer,
        *,
        commit: bool = True,
    ) -> WireGuardPeer:
        self._set_state(
            peer,
            state=DEVICE_STATE_EXPIRED,
            profile_expires_at=peer.profile_expires_at,
            revoked_at=None,
        )
        if commit:
            self.db.commit()
            self.db.refresh(peer)
        return peer

    def expire_if_due(
        self,
        peer: WireGuardPeer,
        *,
        now: Optional[datetime] = None,
        commit: bool = True,
    ) -> bool:
        if peer.is_revoked:
            return False
        current = now or utcnow()
        if peer.profile_expires_at is None or peer.profile_expires_at > current:
            return False
        if peer.effective_device_state == DEVICE_STATE_EXPIRED and not peer.is_active:
            return False
        self.mark_expired(peer, commit=commit)
        return True

    def expire_due_devices(self, *, now: Optional[datetime] = None) -> DeviceCleanupSummary:
        current = now or utcnow()
        peers = (
            self.db.query(WireGuardPeer)
            .filter(
                WireGuardPeer.is_revoked == False,
                WireGuardPeer.profile_expires_at.isnot(None),
                WireGuardPeer.profile_expires_at <= current,
            )
            .all()
        )
        expired = 0
        for peer in peers:
            if peer.effective_device_state == DEVICE_STATE_EXPIRED and not peer.is_active:
                continue
            self._set_state(
                peer,
                state=DEVICE_STATE_EXPIRED,
                profile_expires_at=peer.profile_expires_at,
                revoked_at=None,
            )
            expired += 1
        if expired:
            self.db.commit()
        return DeviceCleanupSummary(expired=expired)

    async def remove_remote_peer(
        self,
        peer: WireGuardPeer,
        *,
        public_key: Optional[str] = None,
    ) -> None:
        key = (public_key or peer.public_key or "").strip()
        if not key or not peer.server_id:
            return
        server = self.db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
        if not server:
            return
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        await manager.remove_peer(conn, key)

    async def revoke_credentials_for_device(
        self,
        peer: WireGuardPeer,
        *,
        reason: str,
        delete_records: bool = False,
    ) -> int:
        credentials = (
            self.db.query(VPNCredential)
            .filter(VPNCredential.device_id == peer.id)
            .all()
        )
        changed = 0
        now = utcnow()
        credential_service = VpnCredentialService(self.db)
        for credential in credentials:
            server = None
            if credential.server_id:
                server = self.db.query(VPNServer).filter(VPNServer.id == credential.server_id).first()
            if delete_records:
                if (
                    credential.revoked_at is None
                    and credential.credential_type == "client_certificate"
                    and server is not None
                ):
                    ok, message = await credential_service.revoke_certificate(
                        credential=credential,
                        server=server,
                        reason=reason,
                    )
                    if not ok and message != "already_revoked":
                        logger.warning(
                            "Failed to revoke certificate credential %s during device delete: %s",
                            credential.id,
                            message,
                        )
                self.db.delete(credential)
                changed += 1
                continue
            if (
                credential.revoked_at is None
                and credential.credential_type == "client_certificate"
                and server is not None
            ):
                ok, message = await credential_service.revoke_certificate(
                    credential=credential,
                    server=server,
                    reason=reason,
                )
                if not ok and message != "already_revoked":
                    logger.warning(
                        "Failed to revoke certificate credential %s during device revoke: %s",
                        credential.id,
                        message,
                    )
                    continue
                changed += 1
                continue
            if credential.revoked_at is None:
                credential.revoked_at = now
                credential.revoke_reason = (reason or "device_revoked")[:128]
                self.db.add(credential)
                changed += 1
        return changed

    async def revoke_device(
        self,
        peer: WireGuardPeer,
        *,
        reason: str = "manual_revoke",
        commit: bool = True,
    ) -> WireGuardPeer:
        try:
            await self.remove_remote_peer(peer)
        except Exception as exc:
            logger.warning(
                "Failed to remove peer %s from server during revoke: %s",
                peer.id,
                exc,
            )
        await self.revoke_credentials_for_device(peer, reason=reason)
        self._set_state(
            peer,
            state=DEVICE_STATE_REVOKED,
            profile_expires_at=peer.profile_expires_at,
            revoked_at=utcnow(),
        )
        if commit:
            self.db.commit()
            self.db.refresh(peer)
        return peer

    async def delete_device(
        self,
        peer: WireGuardPeer,
        *,
        reason: str = "device_deleted",
    ) -> None:
        try:
            await self.remove_remote_peer(peer)
        except Exception as exc:
            logger.warning(
                "Failed to remove peer %s from server during delete: %s",
                peer.id,
                exc,
            )
        await self.revoke_credentials_for_device(
            peer,
            reason=reason,
            delete_records=True,
        )
        self.db.delete(peer)
        self.db.commit()


def get_device_service(db: Session) -> DeviceService:
    return DeviceService(db)
