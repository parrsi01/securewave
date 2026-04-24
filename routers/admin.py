"""
Admin endpoints for WireGuard peer management.
Allows auto-registration of peers on registered Linux WireGuard hosts.
"""

import ipaddress
import re
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.vpn_server import VPNServer
from services.jwt_service import get_current_user
from services.wireguard_service import WireGuardService
from services.wireguard_server_manager import get_wireguard_server_manager, server_connection_from_db

router = APIRouter()

WG_KEY_PATTERN = re.compile(r"^[A-Za-z0-9+/=]{43,44}$")


class PeerInfo(BaseModel):
    user_id: int
    email: str
    client_public_key: str
    client_ip: str
    registered: bool


class RegisterPeerRequest(BaseModel):
    user_id: int


class RegisterPeerResponse(BaseModel):
    success: bool
    user_id: int
    client_public_key: str
    client_ip: str
    message: str
    wg_command: Optional[str] = None
    server_id: Optional[str] = None


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """Dependency that requires admin privileges."""
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )
    return current_user


def _validate_wg_peer_inputs(public_key: str, client_ip: str) -> None:
    if not WG_KEY_PATTERN.match(public_key):
        raise HTTPException(status_code=400, detail="Invalid WireGuard public key format")
    try:
        ipaddress.ip_network(client_ip, strict=False)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid client IP address") from exc


def _select_registration_server(db: Session) -> VPNServer:
    server = (
        db.query(VPNServer)
        .filter(VPNServer.status == "active")
        .order_by(VPNServer.priority.desc(), VPNServer.server_id.asc())
        .first()
    )
    if not server:
        raise HTTPException(status_code=400, detail="No active VPN server is registered")
    return server


def _peer_info(user: User, wg_service: WireGuardService) -> PeerInfo:
    return PeerInfo(
        user_id=user.id,
        email=user.email,
        client_public_key=user.wg_public_key,
        client_ip=wg_service.allocate_ip(user.id),
        registered=user.wg_peer_registered,
    )


@router.get("/peers/pending", response_model=List[PeerInfo])
def list_pending_peers(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """List users with allocated WireGuard configs that are not registered as peers."""
    wg_service = WireGuardService()
    pending_users = db.query(User).filter(
        User.wg_public_key.isnot(None),
        User.wg_peer_registered == False,
    ).all()
    return [_peer_info(user, wg_service) for user in pending_users]


@router.get("/peers/all", response_model=List[PeerInfo])
def list_all_peers(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """List all users with WireGuard configs."""
    wg_service = WireGuardService()
    users_with_keys = db.query(User).filter(User.wg_public_key.isnot(None)).all()
    return [_peer_info(user, wg_service) for user in users_with_keys]


@router.post("/peers/register", response_model=RegisterPeerResponse)
async def register_peer(
    request: RegisterPeerRequest,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Register a single peer on the selected WireGuard Linux host."""
    user = db.query(User).filter(User.id == request.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.wg_public_key:
        raise HTTPException(status_code=400, detail="User has no WireGuard config allocated")

    wg_service = WireGuardService()
    client_ip = wg_service.allocate_ip(user.id)
    _validate_wg_peer_inputs(user.wg_public_key, client_ip)

    server = _select_registration_server(db)
    manager = get_wireguard_server_manager()
    conn = server_connection_from_db(server)
    success, message = await manager.add_peer(conn, user.wg_public_key, client_ip)

    if success:
        user.wg_peer_registered = True
        db.commit()

    return RegisterPeerResponse(
        success=success,
        user_id=user.id,
        client_public_key=user.wg_public_key,
        client_ip=client_ip,
        message=message,
        wg_command=f"sudo wg set wg0 peer {user.wg_public_key} allowed-ips {client_ip}",
        server_id=server.server_id,
    )


@router.post("/peers/register-all")
async def register_all_pending_peers(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Register all pending peers on the selected WireGuard Linux host."""
    wg_service = WireGuardService()
    pending_users = db.query(User).filter(
        User.wg_public_key.isnot(None),
        User.wg_peer_registered == False,
    ).all()
    if not pending_users:
        return {"message": "No pending peers to register", "registered": 0}

    server = _select_registration_server(db)
    manager = get_wireguard_server_manager()
    conn = server_connection_from_db(server)

    results = []
    registered = 0
    for user in pending_users:
        client_ip = wg_service.allocate_ip(user.id)
        _validate_wg_peer_inputs(user.wg_public_key, client_ip)
        success, message = await manager.add_peer(conn, user.wg_public_key, client_ip)
        if success:
            user.wg_peer_registered = True
            registered += 1
        results.append({
            "user_id": user.id,
            "email": user.email,
            "client_ip": client_ip,
            "success": success,
            "message": message,
        })

    db.commit()
    return {
        "message": f"Registered {registered} of {len(pending_users)} peers",
        "registered": registered,
        "server_id": server.server_id,
        "results": results,
    }


@router.post("/peers/mark-registered/{user_id}")
def mark_peer_registered(
    user_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Manually mark a peer as registered when registration happened externally."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.wg_peer_registered = True
    db.commit()
    return {"message": f"User {user_id} marked as registered", "user_id": user_id}


@router.get("/peers/command/{user_id}")
def get_peer_command(
    user_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Get the wg command for manually registering one peer."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.wg_public_key:
        raise HTTPException(status_code=400, detail="User has no WireGuard config")

    wg_service = WireGuardService()
    client_ip = wg_service.allocate_ip(user.id)
    _validate_wg_peer_inputs(user.wg_public_key, client_ip)

    return {
        "user_id": user_id,
        "email": user.email,
        "client_public_key": user.wg_public_key,
        "client_ip": client_ip,
        "wg_command": f"sudo wg set wg0 peer {user.wg_public_key} allowed-ips {client_ip}",
        "persist_command": "sudo wg-quick save wg0",
    }
