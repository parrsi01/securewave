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
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.subscription import Subscription
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.jwt_service import get_current_user
from services.vpn_peer_manager import get_peer_manager
from services.vpn_server_service import VPNServerService
from services.protocol_availability_service import ProtocolAvailabilityService
from services.openvpn_credential_manager import (
    OpenVpnCredentialError,
    OpenVpnCredentialManager,
)
from services.subscription_access import require_active_subscription
from services.wireguard_peer_lifecycle import (
    WireGuardPeerSyncError,
    confirm_peer_assignment,
    revoke_peer_after_remote_removal,
)

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


def _require_wireguard_runtime_evidence(server: VPNServer) -> None:
    readiness = ProtocolAvailabilityService().evaluate(server, "wireguard")
    if not readiness.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=readiness.reason or "WireGuard runtime evidence is unavailable.",
        )


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
    created_at: str
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
        created_at=peer.created_at.isoformat() if peer.created_at else "",
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
    device_name = request.name.strip()

    # Check device limit
    existing_peers = peer_manager.list_user_peers(current_user.id)
    active_count = len([p for p in existing_peers if p.is_active and not p.is_revoked])
    device_limit = get_device_limit(current_user, db)

    if active_count >= device_limit:
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
        _require_wireguard_runtime_evidence(server)

    # Validate device type
    valid_types = ["windows", "macos", "linux", "ios", "android", "router", "other"]
    device_type = request.device_type.lower() if request.device_type else None
    if device_type and device_type not in valid_types:
        device_type = "other"

    # Create peer
    try:
        peer = peer_manager.create_peer(
            user=current_user,
            # Assignment is committed only after the remote server accepts
            # this key; a DB row alone is never a usable tunnel assignment.
            server=None,
            device_name=device_name,
            device_type=device_type,
            max_active_devices=device_limit,
        )

        if server:
            try:
                peer = await confirm_peer_assignment(db, peer_manager, peer, server)
            except WireGuardPeerSyncError as exc:
                peer.server_id = None
                peer.is_active = False
                db.add(peer)
                db.commit()
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="VPN peer registration could not be confirmed.",
                ) from exc

        return _device_response(peer)

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to create device exception_type=%s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create device"
        )


@router.get("/limits/info")
async def get_device_limits(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get device limits before dynamic ``/{device_id}`` routing can match."""
    return _device_limits_payload(current_user, db)


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
        func.lower(WireGuardPeer.device_name) == request.name.strip().lower(),
    ).first()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Device name already exists"
        )

    peer.device_name = request.name.strip()
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Device name already exists",
        ) from exc
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
        _require_wireguard_runtime_evidence(server)

    if server is None:
        # Clearing a preference must not remove a currently working remote
        # peer.  It only drops the local preference for future selection.
        peer.server_id = None
        db.add(peer)
        db.commit()
        db.refresh(peer)
    else:
        try:
            peer = await confirm_peer_assignment(db, get_peer_manager(db), peer, server)
        except WireGuardPeerSyncError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="VPN peer migration could not be confirmed.",
            ) from exc
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

    peer_manager = get_peer_manager(db)
    try:
        await OpenVpnCredentialManager(db).revoke_device_credentials(
            user_id=current_user.id,
            peer=peer,
        )
        success = await revoke_peer_after_remote_removal(peer_manager, peer)
    except (WireGuardPeerSyncError, OpenVpnCredentialError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="VPN peer removal could not be confirmed.",
        ) from exc

    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to revoke device"
        )

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
    _require_wireguard_runtime_evidence(server)

    peer_manager = get_peer_manager(db)

    try:
        peer = await confirm_peer_assignment(db, peer_manager, peer, server)

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

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        logger.error("Failed to generate config exception_type=%s", type(e).__name__)
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
    _require_wireguard_runtime_evidence(server)

    peer_manager = get_peer_manager(db)
    try:
        peer = await confirm_peer_assignment(db, peer_manager, peer, server)
    except WireGuardPeerSyncError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="VPN peer registration could not be confirmed.",
        ) from exc
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

    try:
        peer_manager = get_peer_manager(db)
        server = peer.server
        if server is None and peer.server_id:
            server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
        if server is None:
            updated_peer = peer_manager.rotate_peer_keys(device_id)
        else:
            updated_peer = await confirm_peer_assignment(
                db,
                peer_manager,
                peer,
                server,
                rotate_keys=True,
            )

        return _device_response(updated_peer)

    except WireGuardPeerSyncError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="VPN key rotation could not be confirmed.",
        ) from exc

    except Exception as e:
        logger.error("Failed to rotate keys exception_type=%s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to rotate keys"
        )


# =============================================================================
# Device Limits Endpoint
# =============================================================================

def _device_limits_payload(current_user: User, db: Session) -> dict:
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
