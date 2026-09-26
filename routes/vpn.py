"""Minimal WireGuard API used by the Linux SecureWave app.

This module intentionally exposes one product path:

- create or reuse an account-owned WireGuard device
- register that peer on a real server before returning private-key config
- record client-reported session usage while the app is open
- mark active sessions disconnected on logout/disconnect
"""

import os
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from database.session import get_db
from models.subscription import Subscription
from models.user import User
from models.vpn_connection import VPNConnection
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.jwt_service import get_current_user
from services.subscription_access import (
    get_effective_device_limit,
    require_active_subscription,
)
from services.usage_metering_service import UsageMeteringError, UsageMeteringService
from services.vpn_peer_manager import get_peer_manager
from services.vpn_server_service import VPNServerService
from services.wireguard_peer_lifecycle import (
    WireGuardPeerSyncError,
    confirm_peer_assignment,
    revoke_peer_after_remote_removal,
)
from services.wireguard_service import WireGuardService
from slowapi import Limiter
from slowapi.util import get_remote_address


router = APIRouter(prefix="/api/vpn", tags=["vpn"])
limiter = Limiter(key_func=get_remote_address)
IS_TESTING = os.getenv("TESTING", "").lower() == "true"
AUTO_REGISTER_PEERS = os.getenv("WG_AUTO_REGISTER_PEERS", "true").lower() == "true"


def rate_limit(rule: str):
    if IS_TESTING:
        def decorator(func):
            return func
        return decorator
    return limiter.limit(rule)


class ServerInfo(BaseModel):
    server_id: str
    location: str
    country: str
    country_code: str
    city: str
    region: Optional[str] = None
    latency_ms: Optional[float] = None
    load_percent: Optional[float] = None
    status: str
    health_status: str
    supports_wireguard: bool = True
    supported_protocols: list[str] = Field(default_factory=lambda: ["wireguard"])


class ServerListResponse(BaseModel):
    servers: list[ServerInfo]
    total: int
    recommended_server_id: Optional[str] = None


class VpnProtocolAvailability(BaseModel):
    protocol: str
    enabled: bool
    server_enabled: bool
    platform_supported: bool
    health_status: str
    reason: Optional[str] = None


class VpnProtocolsResponse(BaseModel):
    user_tier: str
    device_type: Optional[str] = None
    protocols: list[VpnProtocolAvailability]
    runtime_contract: str = "wireguard-only"


class VpnProfileRequest(BaseModel):
    device_id: Optional[int] = Field(None, gt=0)
    device_name: Optional[str] = Field(None, max_length=64)
    device_type: Optional[str] = Field(None, max_length=32)
    protocol: str = Field("wireguard")
    server_id: Optional[str] = Field(None, max_length=128)
    force_rotate_keys: bool = False


class VpnProfileDns(BaseModel):
    mode: str = "tunnel"
    servers: list[str]
    ad_malware_blocking: str = "on"
    enforcement: str = "config"


class VpnProfileKillSwitch(BaseModel):
    mode: str = "enabled"
    enforcement: str = "helper"
    notes: str = "Linux helper owns routes, DNS, and tunnel cleanup."


class VpnProfileResponse(BaseModel):
    device_id: int
    device_name: Optional[str] = None
    device_type: Optional[str] = None
    protocol: str
    server_id: str
    server_location: str
    key_version: int
    issued_at: str
    expires_at: str
    wireguard_config: str
    dns: VpnProfileDns
    kill_switch: VpnProfileKillSwitch
    peer_registered: bool = True
    registration_status: str = "registered"


class VPNConnectRequest(BaseModel):
    server_id: Optional[str] = None
    region: Optional[str] = None
    protocol: str = "wireguard"


class ConnectionStatusResponse(BaseModel):
    status: str
    connected: bool
    server_id: Optional[str] = None
    server_location: Optional[str] = None
    client_ip: Optional[str] = None
    connected_since: Optional[str] = None
    bytes_sent: int = 0
    bytes_received: int = 0
    connection_recorded: bool = False
    tunnel_proven: bool = False


class DeviceResponse(BaseModel):
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
    needs_rotation: bool = False


class DeviceListResponse(BaseModel):
    devices: list[DeviceResponse]
    total: int
    limit: int
    remaining: int


class DeviceRevokeRequest(BaseModel):
    device_id: int = Field(..., gt=0)


class UsageSessionStartRequest(BaseModel):
    device_id: int = Field(..., gt=0)
    server_id: str = Field(..., min_length=1, max_length=128)
    protocol: str = Field("wireguard", min_length=2, max_length=16)
    idempotency_key: str = Field(..., min_length=8, max_length=128, pattern=r"^[A-Za-z0-9._:-]+$")


class UsageIncrementRequest(BaseModel):
    sequence: int = Field(..., gt=0)
    bytes_sent: int = Field(0, ge=0, le=10 * 1024 * 1024 * 1024)
    bytes_received: int = Field(0, ge=0, le=10 * 1024 * 1024 * 1024)
    idempotency_key: str = Field(..., min_length=8, max_length=128, pattern=r"^[A-Za-z0-9._:-]+$")


class UsageFinalizeRequest(BaseModel):
    idempotency_key: Optional[str] = Field(None, min_length=8, max_length=128, pattern=r"^[A-Za-z0-9._:-]+$")
    reason: str = Field("client_disconnect", min_length=1, max_length=32, pattern=r"^[a-z_]+$")


def _normalize_wireguard(raw: Optional[str]) -> str:
    protocol = (raw or "wireguard").strip().lower().replace("_", "")
    if protocol not in {"wireguard", "wg"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="SecureWave is WireGuard-only in this build.",
        )
    return "wireguard"


def _get_user_tier(db: Session, user: User) -> str:
    sub = (
        db.query(Subscription)
        .filter(
            Subscription.user_id == user.id,
            Subscription.status.in_(["active", "trialing"]),
        )
        .first()
    )
    return (sub.plan_id or "premium") if sub else "free"


def _wireguard_ready(server: VPNServer) -> bool:
    return bool(
        server.supports_wireguard
        and server.endpoint
        and server.wg_public_key
        and server.status == "active"
        and server.health_status in {"healthy", "degraded"}
    )


def _active_wireguard_servers(db: Session, user: User) -> list[VPNServer]:
    servers = VPNServerService.get_active_servers(db, _get_user_tier(db, user))
    return [server for server in servers if _wireguard_ready(server)]


def _server_info(server: VPNServer) -> ServerInfo:
    load_percent = (
        server.current_connections / server.max_connections * 100
        if server.max_connections
        else 0
    )
    return ServerInfo(
        server_id=server.server_id,
        location=server.location,
        country=server.country,
        country_code=server.country_code,
        city=server.city,
        region=server.region,
        latency_ms=server.latency_ms,
        load_percent=round(load_percent, 1),
        status=server.status,
        health_status=server.health_status,
        supports_wireguard=True,
        supported_protocols=["wireguard"],
    )


def _select_server(db: Session, user: User, server_id: Optional[str]) -> VPNServer:
    candidates = _active_wireguard_servers(db, user)
    if server_id:
        server = VPNServerService.get_server_by_id(db, server_id)
        if server is None or server not in candidates:
            raise HTTPException(status_code=404, detail="WireGuard server not found")
        return server
    if not candidates:
        raise HTTPException(
            status_code=503,
            detail="No WireGuard servers are available.",
        )
    candidates.sort(
        key=lambda item: (
            1 if item.health_status == "healthy" else 0,
            float(item.performance_score or 0),
            -float(item.latency_ms or 0),
        ),
        reverse=True,
    )
    return candidates[0]


def _dns_servers() -> list[str]:
    raw = os.getenv("SECUREWAVE_TUNNEL_DNS", "94.140.14.14,94.140.15.15")
    servers = [item.strip() for item in raw.split(",") if item.strip()]
    return servers or ["94.140.14.14", "94.140.15.15"]


def _profile_ttl() -> datetime:
    ttl = int(os.getenv("SECUREWAVE_PROFILE_TTL_SECONDS", "3600"))
    return datetime.utcnow() + timedelta(seconds=max(ttl, 60))


def _build_wireguard_config(peer: WireGuardPeer, server: VPNServer) -> str:
    private_key = WireGuardService().decrypt_private_key(peer.private_key_encrypted)
    keepalive = int(os.getenv("SECUREWAVE_WG_KEEPALIVE", "25"))
    lines = [
        "[Interface]",
        f"PrivateKey = {private_key}",
        f"Address = {peer.ipv4_address}",
        f"DNS = {','.join(_dns_servers())}",
        "",
        "[Peer]",
        f"PublicKey = {server.wg_public_key}",
        f"Endpoint = {server.endpoint}",
        "AllowedIPs = 0.0.0.0/0, ::/0",
    ]
    if keepalive > 0:
        lines.append(f"PersistentKeepalive = {keepalive}")
    return "\n".join(lines) + "\n"


def _find_or_create_peer(
    db: Session,
    user: User,
    payload: VpnProfileRequest,
) -> WireGuardPeer:
    if payload.device_id:
        peer = (
            db.query(WireGuardPeer)
            .filter(
                WireGuardPeer.id == payload.device_id,
                WireGuardPeer.user_id == user.id,
                WireGuardPeer.is_revoked.is_(False),
            )
            .first()
        )
        if peer is None:
            raise HTTPException(status_code=404, detail="VPN device not found")
        return peer

    device_name = (payload.device_name or "Linux VM").strip()[:64]
    peer = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user.id,
            func.lower(WireGuardPeer.device_name) == device_name.lower(),
            WireGuardPeer.is_revoked.is_(False),
        )
        .first()
    )
    if peer is not None:
        return peer

    query = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == user.id,
        WireGuardPeer.is_active.is_(True),
        WireGuardPeer.is_revoked.is_(False),
    )
    if payload.device_type:
        query = query.filter(WireGuardPeer.device_type == payload.device_type.lower())
    reusable = query.order_by(WireGuardPeer.updated_at.desc()).limit(2).all()
    if len(reusable) == 1:
        return reusable[0]

    limit = get_effective_device_limit(db, user)
    active_count = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user.id,
            WireGuardPeer.is_active.is_(True),
            WireGuardPeer.is_revoked.is_(False),
        )
        .count()
    )
    if active_count >= limit:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Device limit reached ({limit}). Revoke the old device or reuse it.",
        )
    try:
        return get_peer_manager(db).create_peer(
            user=user,
            server=None,
            device_name=device_name,
            device_type=(payload.device_type or "linux").lower(),
            max_active_devices=limit,
            reuse_existing_device=True,
        )
    except ValueError as exc:
        detail = str(exc) or "Could not create VPN device"
        status_code = status.HTTP_403_FORBIDDEN if "limit" in detail.lower() else 400
        raise HTTPException(status_code=status_code, detail=detail) from exc


@router.get("/servers", response_model=ServerListResponse)
async def list_servers(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    servers = _active_wireguard_servers(db, current_user)
    infos = [_server_info(server) for server in servers]
    recommended = infos[0].server_id if infos else None
    return ServerListResponse(servers=infos, total=len(infos), recommended_server_id=recommended)


@router.get("/protocols", response_model=VpnProtocolsResponse)
async def list_protocols(
    device_type: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    has_server = bool(_active_wireguard_servers(db, current_user))
    return VpnProtocolsResponse(
        user_tier=_get_user_tier(db, current_user),
        device_type=device_type,
        protocols=[
            VpnProtocolAvailability(
                protocol="wireguard",
                enabled=has_server,
                server_enabled=has_server,
                platform_supported=True,
                health_status="available" if has_server else "unavailable",
                reason=None if has_server else "No WireGuard server is available.",
            ),
        ],
    )


@router.post("/profile", response_model=VpnProfileResponse)
@rate_limit("30/minute")
async def provision_profile(
    request: Request,
    payload: VpnProfileRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _normalize_wireguard(payload.protocol)
    await require_active_subscription(db, current_user)
    server = _select_server(db, current_user, payload.server_id)
    peer = _find_or_create_peer(db, current_user, payload)

    try:
        peer = await confirm_peer_assignment(
            db,
            get_peer_manager(db),
            peer,
            server,
            rotate_keys=payload.force_rotate_keys,
            auto_register=AUTO_REGISTER_PEERS,
        )
    except WireGuardPeerSyncError as exc:
        raise HTTPException(
            status_code=503,
            detail="WireGuard peer registration could not be confirmed.",
        ) from exc

    issued_at = datetime.utcnow()
    return VpnProfileResponse(
        device_id=peer.id,
        device_name=peer.device_name,
        device_type=peer.device_type,
        protocol="wireguard",
        server_id=server.server_id,
        server_location=f"{server.city}, {server.country}",
        key_version=peer.key_version or 1,
        issued_at=issued_at.isoformat(),
        expires_at=_profile_ttl().isoformat(),
        wireguard_config=_build_wireguard_config(peer, server),
        dns=VpnProfileDns(servers=_dns_servers()),
        kill_switch=VpnProfileKillSwitch(),
    )


@router.post("/connect")
async def connect_vpn(
    payload: VPNConnectRequest = VPNConnectRequest(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _normalize_wireguard(payload.protocol)
    peer = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == current_user.id,
            WireGuardPeer.server_id.isnot(None),
            WireGuardPeer.is_active.is_(True),
            WireGuardPeer.is_revoked.is_(False),
        )
        .order_by(WireGuardPeer.updated_at.desc())
        .first()
    )
    return {
        "mode": "live",
        "status": "CLIENT_CONNECTED",
        "tunnel_proven": False,
        "server_id": payload.server_id or payload.region or (peer.server.server_id if peer and peer.server else None),
        "device_id": peer.id if peer else None,
    }


@router.post("/disconnect")
async def disconnect_vpn(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    disconnected_at = datetime.utcnow()
    db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None),
    ).update(
        {
            VPNConnection.disconnected_at: disconnected_at,
            VPNConnection.finalization_reason: "client_disconnect",
        },
        synchronize_session=False,
    )
    db.commit()
    return {"mode": "live", "status": "DISCONNECTED", "disconnected_at": disconnected_at.isoformat()}


@router.get("/status", response_model=ConnectionStatusResponse)
async def get_connection_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    connection = (
        db.query(VPNConnection)
        .filter(
            VPNConnection.user_id == current_user.id,
            VPNConnection.disconnected_at.is_(None),
        )
        .order_by(VPNConnection.connected_at.desc())
        .first()
    )
    if connection is None:
        return ConnectionStatusResponse(status="DISCONNECTED", connected=False)
    server = connection.server
    return ConnectionStatusResponse(
        status="RECORDED",
        connected=True,
        server_id=server.server_id if server else None,
        server_location=f"{server.city}, {server.country}" if server else None,
        client_ip=connection.device.ipv4_address if connection.device else None,
        connected_since=connection.connected_at.isoformat() if connection.connected_at else None,
        bytes_sent=int(connection.total_bytes_sent or 0),
        bytes_received=int(connection.total_bytes_received or 0),
        connection_recorded=True,
        tunnel_proven=False,
    )


@router.get("/devices", response_model=DeviceListResponse)
async def list_devices(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    limit = get_effective_device_limit(db, current_user)
    peers = (
        db.query(WireGuardPeer)
        .filter(WireGuardPeer.user_id == current_user.id, WireGuardPeer.is_revoked.is_(False))
        .order_by(WireGuardPeer.created_at.desc())
        .all()
    )
    active = [peer for peer in peers if peer.is_active and not peer.is_revoked]
    return DeviceListResponse(
        devices=[
            DeviceResponse(
                id=peer.id,
                name=peer.device_name,
                device_type=peer.device_type,
                ip_address=peer.ipv4_address,
                server_id=peer.server.server_id if peer.server else None,
                server_location=f"{peer.server.city}, {peer.server.country}" if peer.server else None,
                is_active=peer.is_active,
                is_revoked=peer.is_revoked,
                created_at=peer.created_at.isoformat() if peer.created_at else "",
                last_handshake=peer.last_handshake_at.isoformat() if peer.last_handshake_at else None,
                data_sent_mb=round((peer.total_data_sent or 0) / 1024 / 1024, 2),
                data_received_mb=round((peer.total_data_received or 0) / 1024 / 1024, 2),
                key_version=peer.key_version or 1,
                needs_rotation=peer.needs_rotation,
            )
            for peer in peers
        ],
        total=len(active),
        limit=limit,
        remaining=max(0, limit - len(active)),
    )


@router.post("/revoke-device")
async def revoke_device(
    payload: DeviceRevokeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    peer = (
        db.query(WireGuardPeer)
        .filter(WireGuardPeer.id == payload.device_id, WireGuardPeer.user_id == current_user.id)
        .first()
    )
    if peer is None:
        raise HTTPException(status_code=404, detail="Device not found")
    if peer.is_revoked:
        return {"device_id": peer.id, "status": "already_revoked"}
    try:
        await revoke_peer_after_remote_removal(get_peer_manager(db), peer)
    except WireGuardPeerSyncError as exc:
        raise HTTPException(
            status_code=503,
            detail="WireGuard peer removal could not be confirmed.",
        ) from exc
    return {"device_id": peer.id, "status": "revoked"}


def _usage_session_response(result) -> dict:
    connection = result.connection
    return {
        "status": "recorded",
        "session_id": connection.id,
        "device_id": connection.device_id,
        "server_id": connection.server.server_id if connection.server else connection.server_id,
        "protocol": connection.protocol,
        "connected_at": connection.connected_at.isoformat() if connection.connected_at else None,
        "disconnected_at": connection.disconnected_at.isoformat() if connection.disconnected_at else None,
        "bytes_sent": int(connection.total_bytes_sent or 0),
        "bytes_received": int(connection.total_bytes_received or 0),
        "last_sequence": int(connection.last_meter_sequence or 0),
        "idempotent": result.idempotent,
    }


@router.post("/usage/sessions/start")
async def start_usage_session(
    payload: UsageSessionStartRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _normalize_wireguard(payload.protocol)
    await require_active_subscription(db, current_user)
    server = VPNServerService.get_server_by_id(db, payload.server_id)
    if server is None:
        raise HTTPException(status_code=404, detail="WireGuard server not found")
    try:
        result = UsageMeteringService(db).start_session(
            user_id=current_user.id,
            device_id=payload.device_id,
            server_id=server.id,
            protocol="wireguard",
            idempotency_key=payload.idempotency_key,
        )
    except UsageMeteringError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return _usage_session_response(result)


@router.post("/usage/sessions/{session_id}/increment")
async def increment_usage_session(
    session_id: int,
    payload: UsageIncrementRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        result = UsageMeteringService(db).increment(
            user_id=current_user.id,
            connection_id=session_id,
            sequence=payload.sequence,
            bytes_sent=payload.bytes_sent,
            bytes_received=payload.bytes_received,
            idempotency_key=payload.idempotency_key,
        )
    except UsageMeteringError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return _usage_session_response(result)


@router.post("/usage/sessions/{session_id}/disconnect")
async def finalize_usage_session(
    session_id: int,
    payload: UsageFinalizeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        result = UsageMeteringService(db).finalize(
            user_id=current_user.id,
            connection_id=session_id,
            idempotency_key=payload.idempotency_key,
            reason=payload.reason,
        )
    except UsageMeteringError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return _usage_session_response(result)


@router.get("/usage")
async def get_usage(
    device_id: Optional[int] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    await require_active_subscription(db, current_user)
    query = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.is_revoked.is_(False),
    )
    if device_id:
        query = query.filter(WireGuardPeer.id == device_id)
    peers = query.all()
    sent = sum(peer.total_data_sent or 0 for peer in peers)
    received = sum(peer.total_data_received or 0 for peer in peers)
    total_bytes = sent + received
    return {
        "total_devices": len(peers),
        "total_data_sent_mb": round(sent / 1024 / 1024, 2),
        "total_data_received_mb": round(received / 1024 / 1024, 2),
        "total_data_gb": round(total_bytes / 1024 / 1024 / 1024, 3),
    }


@router.get("/health")
async def vpn_health(db: Session = Depends(get_db)):
    servers = db.query(VPNServer).filter(VPNServer.supports_wireguard.is_(True)).all()
    ready = [server for server in servers if _wireguard_ready(server)]
    return {
        "status": "ok" if ready else "degraded",
        "protocol": "wireguard",
        "servers": len(servers),
        "ready_servers": len(ready),
    }
