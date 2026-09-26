"""
Subscription access helpers for VPN endpoints.

Enforces active/trial subscriptions and revokes peers on expiration.
Free-tier users (no subscription) are allowed up to a configurable
monthly data cap and device limit.
"""

import os
import logging
from datetime import datetime
from typing import Optional, List

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from models.subscription import Subscription
from models.user import User
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.wireguard_server_manager import get_wireguard_server_manager, server_connection_from_db

logger = logging.getLogger(__name__)

FREE_TIER_MONTHLY_GB = float(os.getenv("FREE_TIER_MONTHLY_GB", "5"))
FREE_TIER_MONTHLY_BYTES = int(FREE_TIER_MONTHLY_GB * 1024 * 1024 * 1024)
FREE_TIER_DEVICE_LIMIT = int(os.getenv("FREE_TIER_DEVICE_LIMIT", "1"))


def _get_active_subscription(db: Session, user_id: int) -> Optional[Subscription]:
    return (
        db.query(Subscription)
        .filter(
            Subscription.user_id == user_id,
            Subscription.status.in_(["active", "trialing"])
        )
        .order_by(Subscription.current_period_end.desc().nullslast())
        .first()
    )


async def revoke_user_peers(db: Session, user: User) -> int:
    """Revoke all active peers for a user and attempt server removal."""
    peers: List[WireGuardPeer] = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user.id,
            WireGuardPeer.is_revoked == False
        )
        .all()
    )

    if not peers:
        return 0

    try:
        manager = get_wireguard_server_manager()
    except Exception as exc:
        logger.warning(f"WireGuard manager unavailable; skipping peer removal sync: {exc}")
        manager = None
    revoked = 0

    for peer in peers:
        server = None
        if peer.server_id:
            server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()

        if server and manager:
            try:
                conn = server_connection_from_db(server)
                await manager.remove_peer(conn, peer.public_key)
            except Exception as exc:
                logger.warning(f"Failed to remove peer {peer.id} from server {server.server_id}: {exc}")

        peer.is_revoked = True
        peer.is_active = False
        peer.revoked_at = datetime.utcnow()
        revoked += 1

    db.commit()
    return revoked


async def _sync_user_usage(db: Session, user: User) -> None:
    """Best-effort sync of peer usage from WireGuard servers."""
    peers = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user.id,
            WireGuardPeer.is_revoked == False,
            WireGuardPeer.server_id.isnot(None),
        )
        .all()
    )
    if not peers:
        return

    try:
        manager = get_wireguard_server_manager()
    except Exception as exc:
        logger.warning(f"WireGuard manager unavailable; skipping usage sync: {exc}")
        return
    servers = {}
    for peer in peers:
        if peer.server_id not in servers:
            server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
            if server:
                servers[peer.server_id] = server

    for server_id, server in servers.items():
        try:
            conn = server_connection_from_db(server)
            success, remote_peers = await manager.list_peers(conn)
            if not success:
                continue
            peer_map = {p["public_key"]: p for p in remote_peers}
            for peer in peers:
                if peer.server_id != server_id:
                    continue
                remote = peer_map.get(peer.public_key)
                if not remote:
                    continue
                peer.total_data_received = remote.get("transfer_rx", 0)
                peer.total_data_sent = remote.get("transfer_tx", 0)
                handshake = remote.get("latest_handshake")
                if handshake:
                    peer.last_handshake_at = datetime.utcfromtimestamp(handshake)
        except Exception as exc:
            logger.warning(f"Usage sync failed for server {server.server_id}: {exc}")

    db.commit()


def _user_bytes_used(peers: List[WireGuardPeer]) -> int:
    total = 0
    for peer in peers:
        total += (peer.total_data_sent or 0) + (peer.total_data_received or 0)
    return total


async def enforce_free_tier_cap(db: Session, user: User) -> None:
    """Enforce the free-tier monthly data cap.

    This is called for users who have NO active subscription.  If the
    user's total transfer across all peers is under the cap, they are
    silently allowed through.  Only when the cap is exceeded are peers
    revoked and a 402 raised.
    """
    await _sync_user_usage(db, user)
    peers = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user.id,
            WireGuardPeer.is_revoked == False
        )
        .all()
    )
    if not peers:
        return
    used_bytes = _user_bytes_used(peers)
    if used_bytes >= FREE_TIER_MONTHLY_BYTES:
        await revoke_user_peers(db, user)
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail=f"Free plan limit reached ({FREE_TIER_MONTHLY_GB:.0f} GB/month). Upgrade to continue."
        )


async def require_active_subscription(db: Session, user: User) -> Optional[Subscription]:
    """
    Enforce that the user has an active/trialing subscription OR qualifies
    for the free tier.

    Free-tier users (no subscription record) are permitted as long as they
    have not exceeded the monthly data cap.  This function returns ``None``
    for free-tier and admin users -- callers MUST handle that case
    gracefully (treat None as "free tier allowed").

    Raises ``HTTPException 402`` only when:
    - The free-tier data cap has been exceeded, or
    - A paid subscription has expired.
    """
    if user.is_admin:
        sub = _get_active_subscription(db, user.id)
        return sub if sub else None

    subscription = _get_active_subscription(db, user.id)

    if not subscription:
        # Free-tier path: allow VPN access within the monthly cap.
        await enforce_free_tier_cap(db, user)
        return None

    if subscription.current_period_end and subscription.current_period_end < datetime.utcnow():
        subscription.status = "expired"
        db.add(subscription)
        db.commit()
        await revoke_user_peers(db, user)
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Subscription expired. Please renew to restore VPN access."
        )

    return subscription


# =========================================================================
# Convenience helpers used by device and VPN route modules
# =========================================================================

def is_free_tier(db: Session, user: User) -> bool:
    """Return True when the user has no active paid subscription."""
    return _get_active_subscription(db, user.id) is None


def get_effective_device_limit(db: Session, user: User) -> int:
    """Return the device limit respecting plan tier.

    Free tier: 1 device (configurable via FREE_TIER_DEVICE_LIMIT env).
    Basic:     3 devices.
    Premium:   5 devices.
    Ultra:     10 devices.
    Admin:     unlimited (100).
    """
    if user.is_admin:
        return 100

    sub = _get_active_subscription(db, user.id)
    if not sub or not sub.plan_id:
        return FREE_TIER_DEVICE_LIMIT

    plan = (sub.plan_id or "").lower()
    limits = {
        "basic": 3,
        "premium": 5,
        "pro": 5,
        "ultra": 10,
    }
    return limits.get(plan, FREE_TIER_DEVICE_LIMIT)
