"""
SecureWave VPN Routes - Real WireGuard VPN Configuration and Management

This module provides endpoints for:
- Allocating VPN configurations (with automatic peer registration)
- Downloading WireGuard config files
- Server selection and listing
- Connection status tracking
"""

import os
import logging
from datetime import datetime
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, Response
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.vpn_server import VPNServer
from models.vpn_connection import VPNConnection
from services.jwt_service import get_current_user
from services.wireguard_service import WireGuardService
from services.vpn_server_service import VPNServerService
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
    ServerConnection,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/vpn", tags=["vpn"])

# Check if we're in demo/mock mode
DEMO_MODE = os.getenv("DEMO_MODE", "false").lower() == "true"
WG_MOCK_MODE = os.getenv("WG_MOCK_MODE", "false").lower() == "true"
AUTO_REGISTER_PEERS = os.getenv("WG_AUTO_REGISTER_PEERS", "true").lower() == "true"


# =============================================================================
# Request/Response Models
# =============================================================================

class ServerInfo(BaseModel):
    """Public server information for client display"""
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


class AllocateConfigRequest(BaseModel):
    """Request to allocate a VPN configuration"""
    server_id: Optional[str] = Field(
        None,
        description="Specific server to connect to. If not provided, auto-selects best server."
    )
    device_name: Optional[str] = Field(
        None,
        description="User-friendly name for this device",
        max_length=64
    )


class VPNConnectRequest(BaseModel):
    """Compatibility request to initiate a VPN connection."""
    region: Optional[str] = Field(
        None,
        description="Preferred region or server identifier (best effort)."
    )


class AllocateConfigResponse(BaseModel):
    """Response containing the allocated VPN configuration"""
    status: str
    server_id: str
    server_location: str
    client_ip: str
    client_public_key: str
    config: str
    qr_code: str
    peer_registered: bool
    instructions: str
    download_filename: str


class ConnectionStatusResponse(BaseModel):
    """VPN connection status response"""
    connected: bool
    server_id: Optional[str] = None
    server_location: Optional[str] = None
    client_ip: Optional[str] = None
    connected_since: Optional[str] = None
    bytes_sent: Optional[int] = None
    bytes_received: Optional[int] = None


class ServerListResponse(BaseModel):
    """List of available VPN servers"""
    servers: List[ServerInfo]
    total: int
    recommended_server_id: Optional[str] = None


# =============================================================================
# Helper Functions
# =============================================================================

def get_user_tier(user: User, db: Session) -> str:
    """Get user's subscription tier"""
    from models.subscription import Subscription
    sub = db.query(Subscription).filter(
        Subscription.user_id == user.id,
        Subscription.status == "active"
    ).first()

    if sub:
        return sub.plan_id or "free"
    return "free"


async def register_peer_on_server(
    server: VPNServer,
    public_key: str,
    allowed_ips: str,
) -> tuple[bool, str]:
    """
    Register a peer on the WireGuard server.

    Returns:
        Tuple of (success, message)
    """
    if WG_MOCK_MODE or DEMO_MODE:
        logger.info(f"[MOCK] Would register peer {public_key[:20]}... on server {server.server_id}")
        return True, "Peer registered (mock mode)"

    if not AUTO_REGISTER_PEERS:
        logger.info(f"Auto-registration disabled. Peer {public_key[:20]}... needs manual registration.")
        return False, "Auto-registration disabled"

    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)

        success, message = await manager.add_peer(conn, public_key, allowed_ips)
        return success, message
    except Exception as e:
        logger.error(f"Failed to register peer on server {server.server_id}: {e}")
        return False, str(e)


# =============================================================================
# Server Listing Endpoints
# =============================================================================

@router.get("/servers", response_model=ServerListResponse)
async def list_servers(
    region: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List available VPN servers.

    Filters servers based on user's subscription tier and optionally by region.
    Returns servers sorted by performance score and latency.
    """
    user_tier = get_user_tier(current_user, db)

    # Get active servers for this user's tier
    servers = VPNServerService.get_active_servers(db, user_tier)

    # Filter by region if specified
    if region:
        servers = [s for s in servers if s.region and s.region.lower() == region.lower()]

    # Convert to response format
    server_list = []
    recommended_id = None
    best_score = -1

    for server in servers:
        # Calculate load percentage
        load_percent = (server.current_connections / server.max_connections * 100) if server.max_connections > 0 else 0

        server_info = ServerInfo(
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
        )
        server_list.append(server_info)

        # Track best server for recommendation
        score = server.performance_score or 0
        if server.health_status == "healthy" and score > best_score:
            best_score = score
            recommended_id = server.server_id

    return ServerListResponse(
        servers=server_list,
        total=len(server_list),
        recommended_server_id=recommended_id,
    )


@router.get("/servers/{server_id}", response_model=ServerInfo)
async def get_server(
    server_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get details for a specific VPN server."""
    server = VPNServerService.get_server_by_id(db, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    load_percent = (server.current_connections / server.max_connections * 100) if server.max_connections > 0 else 0

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
    )


# =============================================================================
# Configuration Allocation Endpoints
# =============================================================================

@router.post("/allocate", response_model=AllocateConfigResponse)
async def allocate_config(
    request: AllocateConfigRequest = AllocateConfigRequest(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Allocate a new WireGuard VPN configuration for the user.

    This endpoint:
    1. Generates or retrieves the user's WireGuard keys
    2. Selects the best server (or uses specified server_id)
    3. Generates a client configuration file
    4. Automatically registers the peer on the WireGuard server
    5. Returns the config with QR code for mobile setup

    The configuration can be imported into the WireGuard app on any platform.
    """
    wg_service = WireGuardService()
    user_tier = get_user_tier(current_user, db)

    # Select server
    if request.server_id:
        server = VPNServerService.get_server_by_id(db, request.server_id)
        if not server:
            raise HTTPException(status_code=404, detail="Server not found")

        # Check tier restriction
        if server.tier_restriction and server.tier_restriction != user_tier and user_tier == "free":
            raise HTTPException(
                status_code=403,
                detail=f"This server requires a {server.tier_restriction} subscription"
            )
    else:
        # Auto-select best available server
        servers = VPNServerService.get_active_servers(db, user_tier)
        if not servers:
            raise HTTPException(
                status_code=503,
                detail="No VPN servers available. Please try again later."
            )

        # Sort by performance score and select best
        servers.sort(key=lambda s: (s.performance_score or 0), reverse=True)
        server = servers[0]

    # Generate or retrieve user's WireGuard keys
    if not current_user.wg_private_key_encrypted or not current_user.wg_public_key:
        private_key, public_key = wg_service.generate_keypair()
        current_user.wg_private_key_encrypted = wg_service.encrypt_private_key(private_key)
        current_user.wg_public_key = public_key
        current_user.wg_peer_registered = False
    else:
        private_key = wg_service.decrypt_private_key(current_user.wg_private_key_encrypted)
        public_key = current_user.wg_public_key

    # Allocate IP address
    client_ip = wg_service.allocate_ip(current_user.id)

    # Generate client configuration for this specific server
    config_content = (
        "[Interface]\n"
        f"PrivateKey = {private_key}\n"
        f"Address = {client_ip}\n"
        f"DNS = {wg_service.dns}\n\n"
        "[Peer]\n"
        f"PublicKey = {server.wg_public_key}\n"
        f"Endpoint = {server.endpoint}\n"
        "AllowedIPs = 0.0.0.0/0, ::/0\n"
        "PersistentKeepalive = 25\n"
    )

    # Save config file
    config_path = wg_service.config_path_for_server(current_user.id, server.server_id)
    config_path.write_text(config_content)

    # Generate QR code
    qr_base64 = wg_service.qr_from_config(config_content)

    # Register peer on the WireGuard server
    peer_registered = current_user.wg_peer_registered
    if not peer_registered:
        success, message = await register_peer_on_server(
            server=server,
            public_key=public_key,
            allowed_ips=client_ip,
        )
        if success:
            current_user.wg_peer_registered = True
            peer_registered = True
            logger.info(f"Peer registered for user {current_user.id} on server {server.server_id}")
        else:
            logger.warning(f"Peer registration failed for user {current_user.id}: {message}")

    # Commit user changes
    db.add(current_user)
    db.commit()

    # Generate download filename
    safe_location = server.city.replace(" ", "-").lower()
    filename = f"securewave-{safe_location}.conf"

    return AllocateConfigResponse(
        status="allocated",
        server_id=server.server_id,
        server_location=f"{server.city}, {server.country}",
        client_ip=client_ip,
        client_public_key=public_key,
        config=config_content,
        qr_code=f"data:image/png;base64,{qr_base64}",
        peer_registered=peer_registered,
        instructions=(
            "Import this configuration into your WireGuard app:\n"
            "1. Download the .conf file or scan the QR code\n"
            "2. Open WireGuard and click 'Add Tunnel'\n"
            "3. Import from file or scan QR code\n"
            "4. Activate the tunnel to connect"
        ),
        download_filename=filename,
    )


@router.get("/config/download/{server_id}")
async def download_config(
    server_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Download the WireGuard configuration file for a specific server.

    Returns the .conf file as a downloadable attachment.
    """
    wg_service = WireGuardService()

    # Check if config exists for this server
    if not wg_service.config_exists_for_server(current_user.id, server_id):
        raise HTTPException(
            status_code=404,
            detail="Configuration not found. Please allocate a config first."
        )

    try:
        config_content = wg_service.get_config_for_server(current_user.id, server_id)
    except FileNotFoundError:
        raise HTTPException(
            status_code=404,
            detail="Configuration file not found. Please allocate a new config."
        )

    # Get server info for filename
    server = VPNServerService.get_server_by_id(db, server_id)
    if server:
        safe_location = server.city.replace(" ", "-").lower()
        filename = f"securewave-{safe_location}.conf"
    else:
        filename = f"securewave-{server_id}.conf"

    return Response(
        content=config_content,
        media_type="application/octet-stream",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"'
        }
    )


@router.get("/config/qr/{server_id}")
async def get_qr_code(
    server_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Get the QR code for a specific server configuration.

    Returns a base64-encoded PNG image of the QR code.
    """
    wg_service = WireGuardService()

    if not wg_service.config_exists_for_server(current_user.id, server_id):
        raise HTTPException(
            status_code=404,
            detail="Configuration not found. Please allocate a config first."
        )

    try:
        config_content = wg_service.get_config_for_server(current_user.id, server_id)
    except FileNotFoundError:
        raise HTTPException(
            status_code=404,
            detail="Configuration file not found."
        )

    qr_base64 = wg_service.qr_from_config(config_content)

    return {
        "qr_code": f"data:image/png;base64,{qr_base64}",
        "server_id": server_id,
    }


# =============================================================================
# Connection Status Endpoints
# =============================================================================

@router.get("/status", response_model=ConnectionStatusResponse)
async def get_connection_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Get the user's current VPN connection status.

    Note: This checks if the user has an active configuration allocated.
    Actual tunnel status is managed by the WireGuard client on the user's device.
    """
    # Check for active VPN connections (if tracking)
    active_connection = db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None)
    ).first()

    if active_connection:
        server = VPNServerService.get_server_by_id(db, str(active_connection.server_id))
        return ConnectionStatusResponse(
            connected=True,
            server_id=server.server_id if server else None,
            server_location=f"{server.city}, {server.country}" if server else None,
            client_ip=active_connection.client_ip,
            connected_since=active_connection.connected_at.isoformat() if active_connection.connected_at else None,
            bytes_sent=active_connection.total_bytes_sent,
            bytes_received=active_connection.total_bytes_received,
        )

    return ConnectionStatusResponse(connected=False)


@router.post("/connect")
async def connect_vpn(
    payload: VPNConnectRequest = VPNConnectRequest(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Compatibility endpoint for demo flows and tests.

    - In demo/mock mode: uses the demo VPN session logic.
    - In live mode: allocates a config and marks a connection as active.
    """
    if DEMO_MODE or WG_MOCK_MODE:
        from services.demo_vpn_service import connect as demo_connect

        session = demo_connect(db, current_user.id, payload.region)
        return {
            "mode": "demo",
            "status": session.status,
            "session_id": session.id,
            "connected_since": session.connected_since.isoformat() if session.connected_since else None,
            "region": session.region,
            "assigned_node": session.assigned_node,
            "mock_ip": session.mock_ip,
        }

    wg_service = WireGuardService()
    user_tier = get_user_tier(current_user, db)

    server = VPNServerService.allocate_server_for_user(
        db, current_user, preferred_location=payload.region
    )
    if not server:
        servers = VPNServerService.get_active_servers(db, user_tier)
        if not servers:
            raise HTTPException(status_code=503, detail="No VPN servers available. Please try again later.")
        servers.sort(key=lambda s: (s.performance_score or 0), reverse=True)
        server = servers[0]

    # Ensure keys/config exist
    if not current_user.wg_private_key_encrypted or not current_user.wg_public_key:
        private_key, public_key = wg_service.generate_keypair()
        current_user.wg_private_key_encrypted = wg_service.encrypt_private_key(private_key)
        current_user.wg_public_key = public_key
        current_user.wg_peer_registered = False
    else:
        public_key = current_user.wg_public_key

    client_ip = wg_service.allocate_ip(current_user.id)
    config_path = wg_service.config_path_for_server(current_user.id, server.server_id)
    if not config_path.exists():
        config_content = (
            "[Interface]\n"
            f"PrivateKey = {wg_service.decrypt_private_key(current_user.wg_private_key_encrypted)}\n"
            f"Address = {client_ip}\n"
            f"DNS = {wg_service.dns}\n\n"
            "[Peer]\n"
            f"PublicKey = {server.wg_public_key}\n"
            f"Endpoint = {server.endpoint}\n"
            "AllowedIPs = 0.0.0.0/0, ::/0\n"
            "PersistentKeepalive = 25\n"
        )
        config_path.write_text(config_content)

    if not current_user.wg_peer_registered:
        success, _ = await register_peer_on_server(
            server=server,
            public_key=public_key,
            allowed_ips=client_ip,
        )
        if success:
            current_user.wg_peer_registered = True

    active_connection = db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None)
    ).first()
    if not active_connection:
        active_connection = VPNConnection(
            user_id=current_user.id,
            server_id=server.id,
            client_ip=client_ip,
            connected_at=datetime.utcnow(),
        )
        db.add(active_connection)

    db.add(current_user)
    db.commit()

    return {
        "mode": "live",
        "status": "CONNECTED",
        "region": server.region or server.location,
        "server_id": server.server_id,
        "client_ip": client_ip,
    }


@router.get("/config")
async def get_vpn_config(
    current_user: User = Depends(get_current_user),
):
    """
    Compatibility endpoint for demo flows and tests.
    Returns the latest allocated WireGuard config.
    """
    if DEMO_MODE or WG_MOCK_MODE:
        from services.demo_vpn_service import status as demo_status, build_demo_config
        from database.session import SessionLocal

        db = SessionLocal()
        try:
            session = demo_status(db, current_user.id)
            if session.status != "CONNECTED":
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="VPN not connected")
            return {"mode": "demo", "config": build_demo_config(session)}
        finally:
            db.close()

    wg_service = WireGuardService()
    configs = sorted(
        wg_service.users_dir.glob(f"{current_user.id}_*.conf"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not configs:
        default_config = wg_service.users_dir / f"{current_user.id}.conf"
        if default_config.exists():
            configs = [default_config]
    if not configs:
        raise HTTPException(status_code=404, detail="Configuration not found. Please allocate a config first.")

    return {"mode": "live", "config": configs[0].read_text()}


@router.get("/my-configs")
async def list_my_configs(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List all VPN configurations allocated to the current user.
    """
    wg_service = WireGuardService()

    # Find all config files for this user
    configs = []
    users_dir = wg_service.users_dir

    if users_dir.exists():
        for config_file in users_dir.glob(f"{current_user.id}_*.conf"):
            # Extract server_id from filename
            filename = config_file.stem
            parts = filename.split("_", 1)
            if len(parts) == 2:
                server_id = parts[1]
                server = VPNServerService.get_server_by_id(db, server_id)

                configs.append({
                    "server_id": server_id,
                    "server_location": f"{server.city}, {server.country}" if server else server_id,
                    "created_at": datetime.fromtimestamp(config_file.stat().st_mtime).isoformat(),
                })

    # Also check for default config (without server_id)
    default_config = users_dir / f"{current_user.id}.conf"
    if default_config.exists():
        configs.insert(0, {
            "server_id": "default",
            "server_location": "Default Server",
            "created_at": datetime.fromtimestamp(default_config.stat().st_mtime).isoformat(),
        })

    return {
        "configs": configs,
        "total": len(configs),
        "has_keys": bool(current_user.wg_public_key),
        "peer_registered": current_user.wg_peer_registered,
    }


# =============================================================================
# Admin/Debug Endpoints (Protected)
# =============================================================================

@router.get("/debug/server-health/{server_id}")
async def check_server_health(
    server_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Check the health status of a specific VPN server.

    Admin-only endpoint for debugging server connectivity.
    """
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    server = VPNServerService.get_server_by_id(db, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if WG_MOCK_MODE or DEMO_MODE:
        return {
            "server_id": server_id,
            "mode": "mock",
            "healthy": True,
            "message": "Mock mode - health check simulated",
        }

    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        healthy, message = await manager.health_check(conn)

        return {
            "server_id": server_id,
            "healthy": healthy,
            "message": message,
            "communication_method": conn.method,
        }
    except Exception as e:
        return {
            "server_id": server_id,
            "healthy": False,
            "message": str(e),
            "error": True,
        }
