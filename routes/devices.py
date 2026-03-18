"""
SecureWave VPN - Device Management API

User-facing endpoints for managing VPN devices:
- List devices
- Add device
- Revoke device
- Rename device
- Get device config/QR
- View device usage
"""

import base64
import logging
import os
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status, Response
from pydantic import BaseModel, Field, ConfigDict
from sqlalchemy.orm import Session
from sqlalchemy import select

from database.session import get_db
from models.user import User
from models.subscription import Subscription
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.device_service import get_device_service
from services.jwt_service import get_current_user
from services.vpn_peer_manager import get_peer_manager
from services.vpn_server_service import VPNServerService
from services.subscription_access import require_active_subscription
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
)
from utils.input_sanitizer import sanitize_device_name

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/vpn/devices", tags=["devices"])


# =============================================================================
# Device Limits by Subscription Tier
# =============================================================================

DEVICE_LIMITS = {
    "free": 1,
    "premium": 5,
}

DEFAULT_DEVICE_LIMIT = 1


def get_device_limit(user: User, db: Session) -> int:
    """Get device limit for user based on subscription"""
    # Check for active subscription
    subscription = db.query(Subscription).filter(
        Subscription.user_id == user.id,
        Subscription.status.in_(["active", "trialing"])
    ).first()

    if not subscription:
        return DEVICE_LIMITS.get("free", DEFAULT_DEVICE_LIMIT)

    plan_name = (subscription.plan_name or "premium").lower()
    if "premium" in plan_name or "pro" in plan_name:
        return DEVICE_LIMITS["premium"]
    return DEFAULT_DEVICE_LIMIT


# =============================================================================
# Request/Response Models
# =============================================================================

class DeviceCreate(BaseModel):
    """Request to add a new device"""
    name: str = Field(..., min_length=1, max_length=50, description="Device name")
    device_type: Optional[str] = Field(
        None,
        description="Device type: windows, macos, linux, ios, android"
    )
    server_id: Optional[str] = Field(None, description="Preferred server ID")


class DeviceRename(BaseModel):
    """Request to rename a device"""
    name: str = Field(..., min_length=1, max_length=50, description="New device name")


class DeviceResponse(BaseModel):
    """Device information response"""
    id: int
    name: Optional[str]
    device_type: Optional[str]
    ip_address: str
    server_id: Optional[str] = None
    server_location: Optional[str] = None
    is_active: bool
    is_revoked: bool
    device_state: str
    created_at: str
    profile_expires_at: Optional[str]
    last_handshake: Optional[str]
    data_sent_mb: float
    data_received_mb: float
    key_version: int
    needs_rotation: bool

    model_config = ConfigDict(from_attributes=True)


class DeviceListResponse(BaseModel):
    """List of devices response"""
    devices: List[DeviceResponse]
    total: int
    limit: int
    remaining: int


class DeviceConfigResponse(BaseModel):
    """Device configuration response"""
    device_id: int
    device_name: Optional[str]
    server_id: str
    server_location: str
    config: str
    qr_code: str
    filename: str


class DeviceServerPreference(BaseModel):
    """Update a device's preferred server (null = auto)."""
    server_id: Optional[str] = Field(None, description="Preferred server ID or null for auto-select")


class DeviceUsageResponse(BaseModel):
    """Device usage statistics"""
    device_id: int
    device_name: Optional[str]
    is_active: bool
    total_data_sent_mb: float
    total_data_received_mb: float
    last_handshake: Optional[str]
    days_since_rotation: int
    connection_count: int


# =============================================================================
# Helpers
# =============================================================================

def _device_response(peer: WireGuardPeer) -> DeviceResponse:
    server_id = peer.server.server_id if getattr(peer, "server", None) else None
    server_location = None
    if getattr(peer, "server", None):
        server_location = f"{peer.server.city}, {peer.server.country}"

    return DeviceResponse(
        id=peer.id,
        name=peer.device_name,
        device_type=peer.device_type,
        ip_address=peer.ipv4_address,
        server_id=server_id,
        server_location=server_location,
        is_active=peer.is_active,
        is_revoked=peer.is_revoked,
        device_state=peer.effective_device_state,
        created_at=peer.created_at.isoformat() if peer.created_at else "",
        profile_expires_at=peer.profile_expires_at.isoformat() if peer.profile_expires_at else None,
        last_handshake=peer.last_handshake_at.isoformat() if peer.last_handshake_at else None,
        data_sent_mb=round(peer.total_data_sent / 1024 / 1024, 2) if peer.total_data_sent else 0,
        data_received_mb=round(peer.total_data_received / 1024 / 1024, 2) if peer.total_data_received else 0,
        key_version=peer.key_version or 1,
        needs_rotation=peer.needs_rotation if hasattr(peer, 'needs_rotation') else False,
    )


# =============================================================================
# Device Endpoints
# =============================================================================

@router.get("", response_model=DeviceListResponse)
async def list_devices(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    List all devices for the current user.

    Returns active and revoked devices with usage statistics.
    """
    peer_manager = get_peer_manager(db)
    peers = peer_manager.list_user_peers(current_user.id, include_revoked=False)

    device_limit = get_device_limit(current_user, db)
    active_count = len([p for p in peers if p.is_active and not p.is_revoked])

    devices = [_device_response(peer) for peer in peers]

    logger.info(
        '[DEVICES] {"event":"list","user_id":%d,"active":%d,"limit":%d,"remaining":%d}',
        current_user.id, active_count, device_limit, max(0, device_limit - active_count),
    )
    return DeviceListResponse(
        devices=devices,
        total=active_count,
        limit=device_limit,
        remaining=max(0, device_limit - active_count)
    )


@router.post("", response_model=DeviceResponse, status_code=status.HTTP_201_CREATED)
async def add_device(
    request: DeviceCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Add a new device.

    Generates WireGuard keys and allocates an IP address.
    Subject to device limits based on subscription tier.
    """
    await require_active_subscription(db, current_user)
    peer_manager = get_peer_manager(db)

    # M-WG-1: Lock the user row first to prevent TOCTOU race on device limit check.
    # Two concurrent add_device requests could both read count=0, both pass limit check,
    # and both insert — exceeding the per-plan device cap without this lock.
    db.query(User).filter(User.id == current_user.id).with_for_update().first()

    # Check device limit (inside the lock)
    existing_peers = peer_manager.list_user_peers(current_user.id)
    active_count = len([p for p in existing_peers if p.is_active and not p.is_revoked])
    device_limit = get_device_limit(current_user, db)

    # L-8: Sanitize device name before any use (strip injection characters)
    try:
        device_name = sanitize_device_name(request.name)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    logger.info(
        '[DEVICES] {"event":"add_check","user_id":%d,"active":%d,"limit":%d,"name":"%s"}',
        current_user.id, active_count, device_limit, device_name,
    )
    if active_count >= device_limit:
        logger.warning(
            '[DEVICES] {"event":"add_blocked","user_id":%d,"active":%d,"limit":%d}',
            current_user.id, active_count, device_limit,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Device limit reached ({device_limit}). Upgrade your plan or revoke an existing device."
        )

    # Check for duplicate name
    for peer in existing_peers:
        if peer.device_name and peer.device_name.lower() == device_name.lower():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Device name already exists"
            )

    # Get server if specified
    server = None
    if request.server_id:
        server = db.query(VPNServer).filter(
            VPNServer.server_id == request.server_id,
            VPNServer.status == "active"
        ).first()
        if not server:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Server not found"
            )

    # Validate device type
    valid_types = ["windows", "macos", "linux", "ios", "android", "router", "other"]
    device_type = request.device_type.lower() if request.device_type else None
    if device_type and device_type not in valid_types:
        device_type = "other"

    # Create peer
    try:
        peer = peer_manager.create_peer(
            user=current_user,
            server=server,
            device_name=device_name,
            device_type=device_type
        )

        logger.info(
            '[DEVICES] {"event":"add_ok","user_id":%d,"device_id":%d,"name":"%s","type":"%s"}',
            current_user.id, peer.id, peer.device_name, device_type or "unknown",
        )
        if server:
            try:
                manager = get_wireguard_server_manager()
                conn = server_connection_from_db(server)
                await manager.add_peer(conn, peer.public_key, peer.ipv4_address)
            except Exception as e:
                logger.warning(f"Peer registration deferred for device {peer.id}: {e}")

        return _device_response(peer)

    except Exception as e:
        logger.error(f"Failed to create device: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create device"
        )


@router.get("/{device_id}", response_model=DeviceResponse)
async def get_device(
    device_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get details for a specific device."""
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == device_id,
        WireGuardPeer.user_id == current_user.id
    ).first()

    if not peer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found"
        )

    return _device_response(peer)


@router.patch("/{device_id}", response_model=DeviceResponse)
async def rename_device(
    device_id: int,
    request: DeviceRename,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Rename a device."""
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == device_id,
        WireGuardPeer.user_id == current_user.id
    ).first()

    if not peer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found"
        )

    # Check for duplicate name
    existing = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.id != device_id,
        WireGuardPeer.device_name == request.name
    ).first()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Device name already exists"
        )

    peer.device_name = request.name
    db.commit()
    db.refresh(peer)

    return _device_response(peer)


@router.put("/{device_id}/server", response_model=DeviceResponse)
async def set_device_server_preference(
    device_id: int,
    request: DeviceServerPreference,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Set a device's preferred server without exposing downloadable configs.

    - ``server_id``: WireGuard server identifier (e.g. "us-east-1-001")
    - null: auto-select the best server
    """
    await require_active_subscription(db, current_user)

    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == device_id,
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.is_revoked == False,
    ).first()
    if not peer:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found or revoked")

    server = None
    if request.server_id:
        server = db.query(VPNServer).filter(
            VPNServer.server_id == request.server_id,
            VPNServer.status == "active",
        ).first()
        if not server:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Server not found")

        # Enforce tier restriction for free users.
        from services.subscription_access import is_free_tier
        if server.tier_restriction and is_free_tier(db, current_user):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"This server requires a {server.tier_restriction} subscription",
            )

    # Best-effort cleanup on old server to avoid stale peers.
    if peer.server_id and (server is None or peer.server_id != server.id):
        old_server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
        if old_server:
            try:
                manager = get_wireguard_server_manager()
                conn = server_connection_from_db(old_server)
                await manager.remove_peer(conn, peer.public_key)
            except Exception as e:
                logger.warning(
                    f"Failed to remove peer {peer.id} from server {old_server.server_id}: {e}"
                )

    peer.server_id = server.id if server else None
    db.add(peer)
    db.commit()
    db.refresh(peer)
    return _device_response(peer)


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_device(
    device_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Revoke a device.

    The device's WireGuard keys will be invalidated and it will no longer be able to connect.
    """
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == device_id,
        WireGuardPeer.user_id == current_user.id
    ).first()

    if not peer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found"
        )

    if peer.is_revoked:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Device already revoked"
        )

    logger.info(
        '[DEVICES] {"event":"revoke","user_id":%d,"device_id":%d,"name":"%s"}',
        current_user.id, device_id, peer.device_name or "unknown",
    )
    device_service = get_device_service(db)
    await device_service.revoke_device(peer, reason="manual_revoke")

    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{device_id}/revoke", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_device_alias(
    device_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Explicit revocation endpoint for device lifecycle management clients."""
    await revoke_device(device_id=device_id, current_user=current_user, db=db)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{device_id}/config", response_model=DeviceConfigResponse)
async def get_device_config(
    device_id: int,
    server_id: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get WireGuard configuration for a device.

    Returns the .conf file content and QR code for mobile setup.
    """
    await require_active_subscription(db, current_user)
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == device_id,
        WireGuardPeer.user_id == current_user.id
    ).first()

    if not peer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found"
        )

    if peer.is_revoked:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Device is revoked"
        )

    # Get server
    if server_id:
        server = db.query(VPNServer).filter(
            VPNServer.server_id == server_id,
            VPNServer.status == "active"
        ).first()
    else:
        # Get best available server via optimizer (Phase 3)
        server = VPNServerService.allocate_server_for_user(db, current_user)
        if not server:
            server = db.query(VPNServer).filter(
                VPNServer.status == "active",
                VPNServer.health_status.in_(["healthy", "degraded"])
            ).order_by(VPNServer.performance_score.desc()).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No available servers"
        )

    peer_manager = get_peer_manager(db)

    try:
        if peer.server_id != server.id:
            if peer.server_id:
                old_server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
                if old_server:
                    try:
                        manager = get_wireguard_server_manager()
                        conn = server_connection_from_db(old_server)
                        await manager.remove_peer(conn, peer.public_key)
                    except Exception as e:
                        logger.warning(
                            f"Failed to remove peer {peer.id} from server {old_server.server_id}: {e}"
                        )

            peer.server_id = server.id
            db.add(peer)
            db.commit()

        try:
            manager = get_wireguard_server_manager()
            conn = server_connection_from_db(server)
            await manager.add_peer(conn, peer.public_key, peer.ipv4_address)
        except Exception as e:
            logger.warning(f"Peer registration deferred for device {peer.id}: {e}")

        config = peer_manager.generate_config(peer, server)
        qr_bytes = peer_manager.generate_config_qr_code(peer, server)
        qr_base64 = f"data:image/png;base64,{base64.b64encode(qr_bytes).decode()}"

        location = f"{server.city}, {server.country}" if server.city else server.location

        return DeviceConfigResponse(
            device_id=peer.id,
            device_name=peer.device_name,
            server_id=server.server_id,
            server_location=location,
            config=config,
            qr_code=qr_base64,
            filename=f"securewave-{server.server_id}.conf"
        )

    except Exception as e:
        logger.error(f"Failed to generate config: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to generate configuration"
        )


@router.get("/{device_id}/config/download")
async def download_device_config(
    device_id: int,
    server_id: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Download WireGuard configuration file."""
    await require_active_subscription(db, current_user)
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == device_id,
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.is_revoked == False
    ).first()

    if not peer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found or revoked"
        )

    # Get server
    if server_id:
        server = db.query(VPNServer).filter(
            VPNServer.server_id == server_id,
            VPNServer.status == "active"
        ).first()
    else:
        server = db.query(VPNServer).filter(
            VPNServer.status == "active"
        ).first()

    if not server:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No available servers"
        )

    peer_manager = get_peer_manager(db)
    if peer.server_id != server.id:
        if peer.server_id:
            old_server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
            if old_server:
                try:
                    manager = get_wireguard_server_manager()
                    conn = server_connection_from_db(old_server)
                    await manager.remove_peer(conn, peer.public_key)
                except Exception as e:
                    logger.warning(
                        f"Failed to remove peer {peer.id} from server {old_server.server_id}: {e}"
                    )

        peer.server_id = server.id
        db.add(peer)
        db.commit()
    filename, config = peer_manager.generate_config_file(peer, server)

    return Response(
        content=config,
        media_type="application/x-wireguard-profile",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"'
        }
    )


@router.get("/{device_id}/usage", response_model=DeviceUsageResponse)
async def get_device_usage(
    device_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get usage statistics for a device."""
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == device_id,
        WireGuardPeer.user_id == current_user.id
    ).first()

    if not peer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found"
        )

    days_since_rotation = 0
    if peer.last_key_rotation_at:
        days_since_rotation = (datetime.utcnow() - peer.last_key_rotation_at).days
    elif peer.created_at:
        days_since_rotation = (datetime.utcnow() - peer.created_at).days

    return DeviceUsageResponse(
        device_id=peer.id,
        device_name=peer.device_name,
        is_active=peer.is_active and not peer.is_revoked,
        total_data_sent_mb=round(peer.total_data_sent / 1024 / 1024, 2) if peer.total_data_sent else 0,
        total_data_received_mb=round(peer.total_data_received / 1024 / 1024, 2) if peer.total_data_received else 0,
        last_handshake=peer.last_handshake_at.isoformat() if peer.last_handshake_at else None,
        days_since_rotation=days_since_rotation,
        connection_count=peer.connection_count or 0
    )


@router.post("/{device_id}/rotate-keys", response_model=DeviceResponse)
async def rotate_device_keys(
    device_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Rotate WireGuard keys for a device.

    Generates new keypair and invalidates old configuration.
    The SecureWave app will fetch a fresh tunnel profile automatically on the next connect.
    """
    await require_active_subscription(db, current_user)
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == device_id,
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.is_revoked == False
    ).first()

    if not peer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Device not found or revoked"
        )

    peer_manager = get_peer_manager(db)
    old_public_key = peer.public_key

    try:
        updated_peer = peer_manager.rotate_peer_keys(device_id)

        if updated_peer.server_id:
            server = db.query(VPNServer).filter(VPNServer.id == updated_peer.server_id).first()
            if server:
                try:
                    manager = get_wireguard_server_manager()
                    conn = server_connection_from_db(server)
                    await manager.remove_peer(conn, old_public_key)
                    await manager.add_peer(conn, updated_peer.public_key, updated_peer.ipv4_address)
                except Exception as e:
                    logger.warning(f"Peer rotation sync deferred for device {device_id}: {e}")

        return _device_response(updated_peer)

    except Exception as e:
        logger.error(f"Failed to rotate keys: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to rotate keys"
        )


# =============================================================================
# Device Limits Endpoint
# =============================================================================

@router.get("/limits/info")
async def get_device_limits(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get device limits for current user's subscription tier."""
    peer_manager = get_peer_manager(db)
    peers = peer_manager.list_user_peers(current_user.id)
    active_count = len([p for p in peers if p.is_active and not p.is_revoked])
    device_limit = get_device_limit(current_user, db)

    # Get subscription info
    subscription = db.query(Subscription).filter(
        Subscription.user_id == current_user.id,
        Subscription.status.in_(["active", "trialing"])
    ).first()

    tier = "free"
    if subscription:
        tier = "premium"

    return {
        "tier": tier,
        "limit": device_limit,
        "used": active_count,
        "remaining": max(0, device_limit - active_count),
        "can_add": active_count < device_limit,
        "upgrade_url": "/subscription" if active_count >= device_limit else None,
        "data_cap_gb": float(os.getenv("FREE_TIER_MONTHLY_GB", "5")) if tier == "free" else None,
    }
