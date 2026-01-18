"""
Subscription access helpers for VPN endpoints.

Enforces active/trial subscriptions and revokes peers on expiration.
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

DEMO_MODE = os.getenv("DEMO_MODE", "false").lower() == "true"
WG_MOCK_MODE = os.getenv("WG_MOCK_MODE", "false").lower() == "true"


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

    if DEMO_MODE or WG_MOCK_MODE:
        for peer in peers:
            peer.is_revoked = True
            peer.is_active = False
            peer.revoked_at = datetime.utcnow()
        db.commit()
        return len(peers)

    manager = get_wireguard_server_manager()
    revoked = 0

    for peer in peers:
        server = None
        if peer.server_id:
            server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()

        if server:
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


async def require_active_subscription(db: Session, user: User) -> Subscription:
    """
    Enforce that the user has an active/trialing subscription.
    Revokes peers if subscription is inactive/expired.
    """
    if user.is_admin or DEMO_MODE or WG_MOCK_MODE:
        sub = _get_active_subscription(db, user.id)
        return sub if sub else None

    subscription = _get_active_subscription(db, user.id)

    if not subscription:
        await revoke_user_peers(db, user)
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Active subscription required to use VPN provisioning."
        )

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
