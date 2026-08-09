"""Fail-closed remote lifecycle for issued WireGuard peers.

The database is the control-plane record, not proof that a peer is usable on a
WireGuard server.  This module keeps an existing peer usable while a new
assignment or key is being confirmed and never returns a private-key-bearing
profile after an unconfirmed remote operation.
"""

from __future__ import annotations

import logging
import os

from sqlalchemy.orm import Session

from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.vpn_peer_manager import VPNPeerManager
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
)
logger = logging.getLogger(__name__)


class WireGuardPeerSyncError(RuntimeError):
    """A remote peer change could not be confirmed safely."""


def remote_peer_sync_required() -> bool:
    """Skip remote mutation only for explicitly marked local tests."""
    return os.getenv("TESTING", "").lower() != "true"


async def _add_peer(server: VPNServer, public_key: str, allowed_ips: str) -> bool:
    manager = get_wireguard_server_manager()
    success, _ = await manager.add_peer(
        server_connection_from_db(server), public_key, allowed_ips
    )
    return bool(success)


async def _remove_peer(server: VPNServer, public_key: str) -> bool:
    manager = get_wireguard_server_manager()
    success, _ = await manager.remove_peer(
        server_connection_from_db(server), public_key
    )
    return bool(success)


async def confirm_peer_assignment(
    db: Session,
    peer_manager: VPNPeerManager,
    peer: WireGuardPeer,
    server: VPNServer,
    *,
    rotate_keys: bool = False,
    auto_register: bool = True,
) -> WireGuardPeer:
    """Confirm a peer on ``server`` before committing its local assignment.

    A real assignment adds the target peer before removing the previous peer.
    If any step fails, the new remote key is removed and the old local record
    remains intact.  Test/demo/mock modes deliberately do not contact hosts.
    """
    old_public_key = peer.public_key
    old_server = peer.server
    if old_server is None and peer.server_id:
        old_server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
    old_server_id = peer.server_id
    remote_sync = remote_peer_sync_required()
    target_added = False
    old_removed = False

    try:
        if rotate_keys:
            peer = peer_manager.rotate_peer_keys(peer.id, commit=False)

        # Keep the new key outside SQLAlchemy's expirable object state. A
        # transaction rollback restores ``peer.public_key`` to the old value,
        # but remote compensation must remove the newly added key.
        target_public_key = peer.public_key
        target_ipv4_address = peer.ipv4_address

        if remote_sync:
            if not auto_register:
                raise WireGuardPeerSyncError("WireGuard peer registration is disabled.")
            if not await _add_peer(server, target_public_key, target_ipv4_address):
                raise WireGuardPeerSyncError(
                    "WireGuard peer registration could not be confirmed."
                )
            target_added = rotate_keys or old_server_id != server.id

            if old_server and (rotate_keys or old_server.id != server.id):
                if not await _remove_peer(old_server, old_public_key):
                    raise WireGuardPeerSyncError(
                        "Previous WireGuard peer removal could not be confirmed."
                    )
                old_removed = True

        peer.server_id = server.id
        peer.is_active = True
        db.add(peer)
        db.commit()
        db.refresh(peer)
        return peer
    except Exception as exc:
        db.rollback()

        # Restore the old remote key before removing the new one.  The
        # compensating operations are best effort only; their results never
        # turn a failed operation into success.
        compensation_failed = False
        if remote_sync:
            if old_removed and old_server:
                try:
                    compensation_failed = not await _add_peer(
                        old_server, old_public_key, peer.ipv4_address
                    )
                except Exception:
                    compensation_failed = True
            if target_added:
                try:
                    removed = await _remove_peer(server, target_public_key)
                    compensation_failed = compensation_failed or not removed
                except Exception:
                    compensation_failed = True

        logger.warning(
            "WireGuard peer lifecycle rollback device_id=%s exception_type=%s compensation_failed=%s",
            peer.id,
            type(exc).__name__,
            compensation_failed,
        )
        if compensation_failed:
            raise WireGuardPeerSyncError(
                "WireGuard peer operation failed and remote recovery could not be confirmed."
            ) from exc
        if isinstance(exc, WireGuardPeerSyncError):
            raise
        raise WireGuardPeerSyncError(
            "WireGuard peer operation could not be confirmed."
        ) from exc


async def revoke_peer_after_remote_removal(
    peer_manager: VPNPeerManager,
    peer: WireGuardPeer,
) -> bool:
    """Revoke locally only after real remote key removal has succeeded."""
    if remote_peer_sync_required() and peer.server is not None:
        if not await _remove_peer(peer.server, peer.public_key):
            raise WireGuardPeerSyncError(
                "WireGuard peer removal could not be confirmed."
            )
    return peer_manager.revoke_peer(peer.id)
