"""Direct WireGuard-only API for SecureWave Beta 1."""

from __future__ import annotations

import logging
import os
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.jwt_service import get_current_user
from services.vpn_peer_manager import get_peer_manager
from services.wireguard_peer_lifecycle import WireGuardPeerSyncError, confirm_peer_assignment

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/vpn", tags=["wireguard"])


class ProfileRequest(BaseModel):
    device_name: str = Field(default="SecureWave Linux", min_length=1, max_length=64)
    device_type: str = Field(default="linux", min_length=1, max_length=32)
    device_id: int | None = Field(default=None, gt=0)


class ProfileResponse(BaseModel):
    device_id: int
    device_name: str
    device_type: str
    server_id: str
    server_location: str
    wireguard_config: str
    issued_at: datetime
    peer_registered: bool


def _configured_server_id() -> str:
    return os.getenv("WIREGUARD_SERVER_ID", "").strip()


def _target_server(db: Session) -> VPNServer:
    configured_id = _configured_server_id()
    query = db.query(VPNServer).filter(VPNServer.status == "active")
    if configured_id:
        server = query.filter(VPNServer.server_id == configured_id).first()
    elif os.getenv("ENVIRONMENT", "development").lower() == "production":
        server = None
    else:
        # Development/tests may use their single seeded fixture. This is not
        # exposed as a picker and production requires an explicit target.
        server = query.order_by(VPNServer.id.asc()).first()
    if server is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The configured SecureWave WireGuard target is unavailable.",
        )
    if not server.supports_wireguard:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The configured target is not enabled for WireGuard.",
        )
    return server


def _peer_for_user(db: Session, user: User, payload: ProfileRequest) -> WireGuardPeer:
    query = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == user.id,
        WireGuardPeer.is_active.is_(True),
        WireGuardPeer.is_revoked.is_(False),
    )
    if payload.device_id is not None:
        peer = query.filter(WireGuardPeer.id == payload.device_id).first()
        if peer is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="WireGuard device not found.")
        return peer
    return query.order_by(WireGuardPeer.created_at.asc()).first() or get_peer_manager(db).create_peer(
        user=user,
        device_name=payload.device_name.strip(),
        device_type=payload.device_type.strip().lower(),
    )

@router.get("/target")
def target(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict[str, object]:
    server = _target_server(db)
    return {
        "name": "SecureWave Beta",
        "server_id": server.server_id,
        "location": f"{server.city}, {server.country}",
        "health": server.health_status,
        "protocol": "wireguard",
    }


@router.get("/health")
def vpn_health(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> dict[str, object]:
    server = _target_server(db)
    return {
        "status": "ok" if server.health_status in {"healthy", "unknown"} else "degraded",
        "protocol": "wireguard",
        "server_id": server.server_id,
        "health_status": server.health_status,
    }


@router.post("/profile", response_model=ProfileResponse)
async def profile(
    payload: ProfileRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ProfileResponse:
    server = _target_server(db)
    try:
        peer = _peer_for_user(db, current_user, payload)
    except ValueError:
        logger.warning("WireGuard peer allocation failed user_id=%s", current_user.id)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="SecureWave could not allocate a WireGuard device.",
        ) from None
    manager = get_peer_manager(db)

    try:
        peer = await confirm_peer_assignment(db, manager, peer, server)
    except WireGuardPeerSyncError as exc:
        logger.warning("WireGuard peer confirmation failed user_id=%s", current_user.id)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The WireGuard target did not confirm this peer.",
        ) from exc

    config = manager.generate_config(peer, server)
    return ProfileResponse(
        device_id=peer.id,
        device_name=peer.device_name or payload.device_name.strip(),
        device_type=peer.device_type or payload.device_type.strip().lower(),
        server_id=server.server_id,
        server_location=f"{server.city}, {server.country}",
        wireguard_config=config,
        issued_at=datetime.utcnow(),
        peer_registered=peer.server_id == server.id,
    )
