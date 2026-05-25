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
from datetime import datetime, timedelta
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, Response, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.wireguard_peer import WireGuardPeer
from models.vpn_server import VPNServer
from models.vpn_connection import VPNConnection
from services.jwt_service import get_current_user
from utils.env_validation import demo_mode_enabled, wg_mock_mode_enabled
from services.subscription_access import require_active_subscription
from services.vpn_peer_manager import get_peer_manager
from services.wireguard_service import WireGuardService
from services.vpn_server_service import VPNServerService
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
    ServerConnection,
)
from slowapi import Limiter
from slowapi.util import get_remote_address

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/vpn", tags=["vpn"])
limiter = Limiter(key_func=get_remote_address)
IS_TESTING = os.getenv("TESTING", "").lower() == "true"


def rate_limit(rule: str):
    if IS_TESTING:
        def decorator(func):
            return func
        return decorator
    return limiter.limit(rule)

# Check if we're in demo/mock mode
DEMO_MODE = demo_mode_enabled() or IS_TESTING
WG_MOCK_MODE = wg_mock_mode_enabled()
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
    supports_wireguard: bool = True
    supports_openvpn: bool = False
    supports_ikev2: bool = False
    supported_protocols: List[str] = Field(default_factory=list)


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


class DeviceCreateRequest(BaseModel):
    """Compatibility request to create a VPN device."""
    name: str = Field(..., min_length=1, max_length=50)
    device_type: Optional[str] = Field(None, description="windows, macos, linux, ios, android")
    server_id: Optional[str] = Field(None, description="Preferred server ID")


class DeviceRevokeRequest(BaseModel):
    """Compatibility request to revoke a VPN device."""
    device_id: int = Field(..., description="Device ID to revoke")


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
    status: Optional[str] = None
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
    protocols: List[VpnProtocolAvailability]

class VpnProfileRequest(BaseModel):
    """Provision an app-consumable VPN tunnel profile (no downloadable files)."""
    device_id: Optional[int] = Field(
        None,
        description="Existing device ID. If omitted, the server will look up or create a device for this user.",
    )
    device_name: Optional[str] = Field(None, max_length=64, description="Device name for registration")
    device_type: Optional[str] = Field(
        None,
        description="Client device type (windows, macos, linux, ios, android)",
    )
    protocol: str = Field("wireguard", description="VPN protocol (wireguard, openvpn, ikev2)")
    server_id: Optional[str] = Field(None, description="Preferred server ID (null = auto)")
    force_rotate_keys: bool = Field(False, description="Rotate device keys before issuing a profile")


class VpnProfileDns(BaseModel):
    mode: str = "tunnel"
    servers: List[str]
    ad_malware_blocking: str = "on"
    enforcement: str = "best_effort"


class VpnProfileKillSwitch(BaseModel):
    mode: str
    enforcement: str
    notes: Optional[str] = None


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
    wireguard_config: str = ""
    openvpn_config: Optional[str] = None
    ikev2_config: Optional[str] = None
    dns: VpnProfileDns
    kill_switch: VpnProfileKillSwitch
    peer_registered: bool = False
    registration_status: Optional[str] = None


# =============================================================================
# Helper Functions
# =============================================================================

def get_user_tier(user: User, db: Session) -> str:
    """Get user's subscription tier.

    Returns the plan_id from the active subscription (e.g. 'basic', 'premium',
    'ultra') or 'free' when the user has no active/trialing subscription.
    For server tier-restriction checks, any paid plan ('basic', 'premium',
    'ultra') grants access to servers with tier_restriction='premium'.
    """
    from models.subscription import Subscription
    sub = db.query(Subscription).filter(
        Subscription.user_id == user.id,
        Subscription.status.in_(["active", "trialing"])
    ).first()

    if sub and sub.plan_id:
        return sub.plan_id  # 'basic', 'premium', 'ultra'
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

def _profile_dns_servers() -> list[str]:
    """Always-on secure DNS for tunnel profiles (ads/malware blocking via DNS)."""
    raw = os.getenv("SECUREWAVE_TUNNEL_DNS", "").strip()
    if not raw:
        raw = "94.140.14.14,94.140.15.15"  # AdGuard DNS (ads + malware)
    parts = [p.strip() for p in raw.split(",") if p.strip()]
    return parts or ["94.140.14.14", "94.140.15.15"]


def _profile_keepalive_seconds() -> int:
    raw = os.getenv("SECUREWAVE_WG_KEEPALIVE", "25").strip()
    try:
        value = int(raw)
        return max(0, min(value, 600))
    except ValueError:
        return 25


def _profile_mtu() -> Optional[int]:
    raw = os.getenv("SECUREWAVE_WG_MTU", "").strip()
    if not raw:
        return None
    try:
        value = int(raw)
        # Common safe range for WireGuard tunnels.
        if 1200 <= value <= 1500:
            return value
    except ValueError:
        return None
    return None


def _linux_kill_switch_snippet() -> str:
    """
    Best-effort Linux kill switch via wg-quick hooks.

    This uses the WireGuard fwmark to allow the tunnel handshake while
    rejecting non-tunnel traffic when the interface is down.
    """
    return (
        "PostUp = sh -c 'command -v iptables >/dev/null 2>&1 && "
        "iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) "
        "-m addrtype ! --dst-type LOCAL -j REJECT'\n"
        "PostDown = sh -c 'command -v iptables >/dev/null 2>&1 && "
        "iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) "
        "-m addrtype ! --dst-type LOCAL -j REJECT || true'\n"
        "PostUp = sh -c 'command -v ip6tables >/dev/null 2>&1 && "
        "ip6tables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) "
        "-m addrtype ! --dst-type LOCAL -j REJECT'\n"
        "PostDown = sh -c 'command -v ip6tables >/dev/null 2>&1 && "
        "ip6tables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) "
        "-m addrtype ! --dst-type LOCAL -j REJECT || true'\n"
    )


def _build_wireguard_profile_config(
    peer: WireGuardPeer,
    server: VPNServer,
    *,
    device_type: Optional[str],
) -> str:
    wg_service = WireGuardService()
    private_key = wg_service.decrypt_private_key(peer.private_key_encrypted)
    dns_servers = _profile_dns_servers()
    keepalive = _profile_keepalive_seconds()
    mtu = _profile_mtu()

    interface_lines = [
        "[Interface]",
        f"PrivateKey = {private_key}",
        f"Address = {peer.ipv4_address}",
        f"DNS = {','.join(dns_servers)}",
    ]
    if mtu is not None:
        interface_lines.append(f"MTU = {mtu}")

    # NOTE: wg-quick supports PostUp/PostDown hooks, but mobile/embedded WireGuard
    # parsers do not. Only include these when the client is Linux and uses wg-quick.
    if (device_type or "").lower() == "linux":
        interface_lines.append(_linux_kill_switch_snippet().rstrip("\n"))

    peer_lines = [
        "",
        "[Peer]",
        f"PublicKey = {server.wg_public_key}",
        f"Endpoint = {server.endpoint}",
        "AllowedIPs = 0.0.0.0/0, ::/0",
    ]
    if keepalive > 0:
        peer_lines.append(f"PersistentKeepalive = {keepalive}")

    prefix = "# SecureWave VPN DEMO CONFIG (testing only)\n" if (DEMO_MODE or WG_MOCK_MODE) else ""
    return prefix + "\n".join(interface_lines + peer_lines) + "\n"


def _normalize_profile_protocol(raw: Optional[str]) -> str:
    value = (raw or "wireguard").lower().strip().replace("_", "")
    if value in ("wireguard", "wg"):
        return "wireguard"
    if value in ("openvpn", "ovpn"):
        return "openvpn"
    if value in ("ikev2", "ipsec", "ikev2/ipsec"):
        return "ikev2"
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=f"Unsupported VPN protocol: {raw}",
    )


def _platform_supported_protocols(device_type: Optional[str]) -> set[str]:
    normalized = (device_type or "").lower().strip()
    if normalized == "linux":
        return {"wireguard", "openvpn"}
    return {"wireguard", "openvpn"}


def _server_supported_protocols(server: VPNServer) -> list[str]:
    protocols: list[str] = []
    if server.supports_wireguard and server.endpoint and server.wg_public_key:
        protocols.append("wireguard")
    if (
        server.supports_openvpn
        and (server.openvpn_endpoint or server.public_ip)
        and server.openvpn_ca_cert_pem
    ):
        protocols.append("openvpn")
    # IKEv2 remains internal/manual for Linux v1. Do not advertise it here.
    return protocols


def _server_supports_protocol(server: VPNServer, protocol: str) -> bool:
    return protocol in _server_supported_protocols(server)


def _endpoint_host(endpoint: str, fallback: str) -> str:
    value = (endpoint or "").strip()
    if not value:
        return fallback
    if value.startswith("[") and "]" in value:
        return value[1:value.index("]")]
    if value.count(":") == 1:
        return value.rsplit(":", 1)[0]
    return value


def _build_openvpn_profile_config(server: VPNServer) -> str:
    if not server.supports_openvpn:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OpenVPN is not enabled for this server.",
        )
    if not server.openvpn_ca_cert_pem:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OpenVPN server metadata is incomplete.",
        )

    host = server.openvpn_endpoint or server.public_ip
    port = int(server.openvpn_port or 1194)
    transport = (server.openvpn_transport or "udp").lower()
    dns_lines = [f"dhcp-option DNS {dns}" for dns in _profile_dns_servers()]
    return "\n".join([
        "client",
        "dev tun",
        f"proto {transport}",
        f"remote {host} {port}",
        "resolv-retry infinite",
        "nobind",
        "persist-key",
        "persist-tun",
        "remote-cert-tls server",
        "auth-user-pass",
        "auth-nocache",
        "redirect-gateway def1",
        *dns_lines,
        "verb 3",
        "<ca>",
        server.openvpn_ca_cert_pem.strip(),
        "</ca>",
        "",
    ])


def _build_ikev2_profile_config(server: VPNServer, current_user: User) -> str:
    if not server.supports_ikev2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="IKEv2 is not enabled for this server.",
        )
    if not server.ikev2_ca_cert_pem:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="IKEv2 server metadata is incomplete.",
        )

    remote_id = server.ikev2_remote_id or server.public_ip
    remote_addrs = _endpoint_host(server.endpoint, server.public_ip)
    dns_servers = ",".join(_profile_dns_servers())
    return "\n".join([
        "connections {",
        "  securewave {",
        "    version = 2",
        f"    remote_addrs = {remote_addrs}",
        "    proposals = aes256-sha256-modp2048",
        "    local {",
        "      auth = eap-mschapv2",
        f"      eap_id = {current_user.email}",
        "    }",
        "    remote {",
        "      auth = pubkey",
        f"      id = {remote_id}",
        "      cacerts = securewave-ikev2-ca.pem",
        "    }",
        "    children {",
        "      securewave {",
        "        remote_ts = 0.0.0.0/0,::/0",
        "        esp_proposals = aes256-sha256-modp2048",
        "      }",
        "    }",
        "  }",
        "}",
        f"# dns = {dns_servers}",
        "# ca_cert_pem_begin",
        server.ikev2_ca_cert_pem.strip(),
        "# ca_cert_pem_end",
        "",
    ])


# =============================================================================
# Server Listing Endpoints
# =============================================================================

@router.get("/servers", response_model=ServerListResponse)
async def list_servers(
    region: Optional[str] = None,
    device_type: Optional[str] = None,
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
    platform_protocols = _platform_supported_protocols(device_type)

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
            supports_wireguard=bool(server.supports_wireguard),
            supports_openvpn=bool(server.supports_openvpn),
            supports_ikev2=False,
            supported_protocols=[
                protocol
                for protocol in _server_supported_protocols(server)
                if protocol in platform_protocols
            ],
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


@router.get("/protocols", response_model=VpnProtocolsResponse)
async def list_protocols(
    device_type: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return protocol availability for the current user and device type."""
    user_tier = get_user_tier(current_user, db)
    platform_protocols = _platform_supported_protocols(device_type)
    servers = VPNServerService.get_active_servers(db, user_tier)

    protocol_rows: list[VpnProtocolAvailability] = []
    for protocol in ("wireguard", "openvpn", "ikev2"):
        platform_supported = protocol in platform_protocols
        server_enabled = any(_server_supports_protocol(server, protocol) for server in servers)
        enabled = platform_supported and server_enabled
        reason = None
        if not platform_supported:
            reason = f"{protocol} is not release-ready for Linux."
        elif not server_enabled:
            reason = f"No usable {protocol} server metadata is configured."
        protocol_rows.append(
            VpnProtocolAvailability(
                protocol=protocol,
                enabled=enabled,
                server_enabled=server_enabled,
                platform_supported=platform_supported,
                health_status="available" if enabled else "unavailable",
                reason=reason,
            )
        )

    return VpnProtocolsResponse(
        user_tier=user_tier,
        device_type=device_type,
        protocols=protocol_rows,
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
        supports_wireguard=bool(server.supports_wireguard),
        supports_openvpn=bool(server.supports_openvpn),
        supports_ikev2=False,
        supported_protocols=_server_supported_protocols(server),
    )


# =============================================================================
# Configuration Allocation Endpoints
# =============================================================================

@router.post("/allocate", response_model=AllocateConfigResponse)
@rate_limit("10/minute")
async def allocate_config(
    request: Request,
    payload: AllocateConfigRequest = AllocateConfigRequest(),
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
    await require_active_subscription(db, current_user)
    wg_service = WireGuardService()
    user_tier = get_user_tier(current_user, db)
    peer_manager = get_peer_manager(db)

    # Select server
    if payload.server_id:
        server = VPNServerService.get_server_by_id(db, payload.server_id)
        if not server:
            raise HTTPException(status_code=404, detail="Server not found")

        # Check tier restriction
        if server.tier_restriction and server.tier_restriction != user_tier and user_tier == "free":
            raise HTTPException(
                status_code=403,
                detail=f"This server requires a {server.tier_restriction} subscription"
            )
    else:
        # Auto-select best available server via optimizer (Phase 3)
        server = VPNServerService.allocate_server_for_user(db, current_user)
        if not server:
            raise HTTPException(
                status_code=503,
                detail="No VPN servers available. Please try again later."
            )

    # Resolve or create a peer device for this user
    device_name = payload.device_name or "Primary Device"
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.device_name == device_name,
        WireGuardPeer.is_revoked == False
    ).first()

    if not peer:
        from routes.devices import get_device_limit
        existing_peers = peer_manager.list_user_peers(current_user.id)
        active_count = len([p for p in existing_peers if p.is_active and not p.is_revoked])
        device_limit = get_device_limit(current_user, db)
        if active_count >= device_limit:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Device limit reached ({device_limit}). Upgrade your plan or revoke an existing device."
            )
        peer = peer_manager.create_peer(
            user=current_user,
            server=server,
            device_name=device_name,
            device_type=None
        )
    elif peer.server_id != server.id:
        # Remove from old server to avoid stale peer entries.
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

    private_key = wg_service.decrypt_private_key(peer.private_key_encrypted)
    public_key = peer.public_key

    # Allocate IP address
    client_ip = peer.ipv4_address

    # Generate client configuration for this specific server
    config_prefix = ""
    if DEMO_MODE or WG_MOCK_MODE:
        config_prefix = "# SecureWave VPN DEMO CONFIG (testing only)\n"

    dns_servers = _profile_dns_servers()
    keepalive = _profile_keepalive_seconds()
    mtu = _profile_mtu()

    interface_lines = [
        "[Interface]",
        f"PrivateKey = {private_key}",
        f"Address = {client_ip}",
        f"DNS = {','.join(dns_servers)}",
    ]
    if mtu is not None:
        interface_lines.append(f"MTU = {mtu}")

    peer_lines = [
        "",
        "[Peer]",
        f"PublicKey = {server.wg_public_key}",
        f"Endpoint = {server.endpoint}",
        "AllowedIPs = 0.0.0.0/0, ::/0",
    ]
    if keepalive > 0:
        peer_lines.append(f"PersistentKeepalive = {keepalive}")

    config_content = config_prefix + "\n".join(interface_lines + peer_lines) + "\n"

    # Save config file
    config_path = wg_service.config_path_for_server(current_user.id, server.server_id)
    # Defensive: ensure private keys are never written with world-readable permissions.
    wg_service._write_secret_file(config_path, config_content)

    # Generate QR code
    qr_base64 = wg_service.qr_from_config(config_content)

    # Register peer on the WireGuard server (optional)
    peer_registered = False
    registration_message = None
    if AUTO_REGISTER_PEERS:
        success, message = await register_peer_on_server(
            server=server,
            public_key=public_key,
            allowed_ips=client_ip,
        )
        if success:
            peer_registered = True
            logger.info(f"Peer registered for user {current_user.id} on server {server.server_id}")
        else:
            registration_message = message
            logger.warning(f"Peer registration deferred for user {current_user.id}: {message}")
    else:
        registration_message = "Auto-registration disabled"

    # Sync legacy keys for compatibility
    if not current_user.wg_public_key:
        current_user.wg_public_key = public_key
    if not current_user.wg_private_key_encrypted:
        current_user.wg_private_key_encrypted = wg_service.encrypt_private_key(private_key)

    # Commit user changes
    db.add(current_user)
    db.commit()

    # Generate download filename
    safe_location = server.city.replace(" ", "-").lower()
    filename = f"securewave-{safe_location}.conf"

    instructions = (
        "Sign in to the SecureWave app and toggle VPN on to connect."
    )
    if registration_message and not peer_registered:
        instructions += f" Registration is pending: {registration_message}."

    return AllocateConfigResponse(
        status="allocated",
        server_id=server.server_id,
        server_location=f"{server.city}, {server.country}",
        client_ip=client_ip,
        client_public_key=public_key,
        config=config_content,
        qr_code=f"data:image/png;base64,{qr_base64}",
        peer_registered=peer_registered,
        instructions=instructions,
        download_filename=filename,
    )


@router.post("/profile", response_model=VpnProfileResponse)
@rate_limit("30/minute")
async def provision_profile(
    payload: VpnProfileRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Provision an app-consumable VPN profile.

    This endpoint is the primary control-plane API used by native apps:
    - Registers/looks up a per-device WireGuard peer (keys encrypted at rest)
    - Selects an allowed server by tier (or uses device/server preference)
    - Returns a WireGuard config blob + metadata (no downloadable files)
    """
    await require_active_subscription(db, current_user)

    protocol = _normalize_profile_protocol(payload.protocol)
    device_type = (payload.device_type or "").lower().strip() or None
    if protocol not in _platform_supported_protocols(device_type):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"{protocol} is not release-ready for Linux. "
                "Use WireGuard or OpenVPN on the Linux release path."
            ),
        )

    user_tier = get_user_tier(current_user, db)
    peer_manager = get_peer_manager(db)

    # Resolve device/peer
    peer: Optional[WireGuardPeer] = None
    if payload.device_id:
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.id == payload.device_id,
            WireGuardPeer.user_id == current_user.id,
            WireGuardPeer.is_revoked == False,
        ).first()
        if not peer:
            logger.warning(
                "Ignoring stale VPN device reference user_id=%s device_id=%s; "
                "falling back to device name lookup",
                current_user.id,
                payload.device_id,
            )

    if peer is None:
        device_name = (payload.device_name or "This device").strip()[:64]
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.user_id == current_user.id,
            WireGuardPeer.device_name == device_name,
            WireGuardPeer.is_revoked == False,
        ).first()

        if not peer:
            from services.subscription_access import get_effective_device_limit
            limit = get_effective_device_limit(db, current_user)
            active_count = db.query(WireGuardPeer).filter(
                WireGuardPeer.user_id == current_user.id,
                WireGuardPeer.is_revoked == False,
                WireGuardPeer.is_active == True,
            ).count()
            if active_count >= limit:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Device limit reached ({limit}). Upgrade your plan or revoke an existing device.",
                )

            device_type = (payload.device_type or "").lower().strip() or None
            peer = peer_manager.create_peer(
                user=current_user,
                server=None,
                device_name=device_name,
                device_type=device_type,
            )

    # Resolve server
    server: Optional[VPNServer] = None
    if payload.server_id:
        server = VPNServerService.get_server_by_id(db, payload.server_id)
        if not server:
            raise HTTPException(status_code=404, detail="Server not found")
        if server.tier_restriction and user_tier == "free":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"This server requires a {server.tier_restriction} subscription",
            )

    if server is None and peer.server_id:
        server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
        if server and server.tier_restriction and user_tier == "free":
            server = None

    if server is None:
        candidates = VPNServerService.get_active_servers(db, user_tier)
        candidates = [
            candidate for candidate in candidates
            if _server_supports_protocol(candidate, protocol)
        ]
        if not candidates:
            raise HTTPException(
                status_code=503,
                detail=(
                    f"No usable {protocol} VPN servers available. "
                    "Check server health and protocol endpoint metadata."
                ),
            )
        # Prefer healthy + high performance score.
        candidates.sort(
            key=lambda s: (
                1 if s.health_status == "healthy" else 0,
                float(s.performance_score or 0),
                -float(s.latency_ms or 0),
            ),
            reverse=True,
        )
        server = candidates[0]

    assert server is not None

    if protocol == "wireguard" and not server.supports_wireguard:
        raise HTTPException(status_code=400, detail="WireGuard is not enabled for this server.")
    if protocol == "wireguard" and not _server_supports_protocol(server, "wireguard"):
        raise HTTPException(
            status_code=503,
            detail="WireGuard server endpoint metadata is incomplete for the selected server.",
        )
    if protocol == "openvpn" and not server.supports_openvpn:
        raise HTTPException(status_code=400, detail="OpenVPN is not enabled for this server.")
    if protocol == "openvpn" and not _server_supports_protocol(server, "openvpn"):
        raise HTTPException(
            status_code=503,
            detail="OpenVPN server endpoint or certificate metadata is incomplete for the selected server.",
        )

    # Optional key rotation
    if payload.force_rotate_keys:
        old_public_key = peer.public_key
        peer = peer_manager.rotate_peer_keys(peer.id)
        if peer.server_id:
            old_server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
            if old_server:
                try:
                    manager = get_wireguard_server_manager()
                    conn = server_connection_from_db(old_server)
                    await manager.remove_peer(conn, old_public_key)
                except Exception as e:
                    logger.warning(f"Peer rotation cleanup deferred for device {peer.id}: {e}")

    # Ensure peer is associated with selected server.
    if peer.server_id != server.id:
        # Best-effort remove old peer from old server.
        if peer.server_id:
            old_server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
            if old_server:
                try:
                    manager = get_wireguard_server_manager()
                    conn = server_connection_from_db(old_server)
                    await manager.remove_peer(conn, peer.public_key)
                except Exception as e:
                    logger.warning(f"Failed to remove peer {peer.id} from server {old_server.server_id}: {e}")

        peer.server_id = server.id
        peer.is_active = True
        db.add(peer)
        db.commit()
        db.refresh(peer)

    # Register WireGuard peers on the data-plane server (best effort).
    peer_registered = False
    registration_status: Optional[str] = None
    if protocol == "wireguard" and AUTO_REGISTER_PEERS:
        success, message = await register_peer_on_server(server, peer.public_key, peer.ipv4_address)
        peer_registered = success
        registration_status = message

    wireguard_config = ""
    openvpn_config: Optional[str] = None
    ikev2_config: Optional[str] = None
    if protocol == "wireguard":
        wireguard_config = _build_wireguard_profile_config(peer, server, device_type=payload.device_type)
    elif protocol == "openvpn":
        openvpn_config = _build_openvpn_profile_config(server)
        registration_status = "openvpn_profile_issued"
    elif protocol == "ikev2":
        ikev2_config = _build_ikev2_profile_config(server, current_user)
        registration_status = "ikev2_profile_issued"

    dns_servers = _profile_dns_servers()

    device_type = (payload.device_type or peer.device_type or "").lower().strip() or None
    kill_switch = VpnProfileKillSwitch(
        mode="enabled",
        enforcement="wg-quick hooks (best effort)" if device_type == "linux" else "best effort",
        notes=(
            "Linux uses wg-quick firewall hooks when iptables is available."
            if device_type == "linux"
            else "Enable Always-on VPN / 'block without VPN' where supported for maximum protection."
        ),
    )

    issued_at = datetime.utcnow()
    ttl_seconds = int(os.getenv("SECUREWAVE_PROFILE_TTL_SECONDS", "3600"))
    if ttl_seconds < 60:
        ttl_seconds = 60
    expires_at = issued_at + timedelta(seconds=ttl_seconds)

    return VpnProfileResponse(
        device_id=peer.id,
        device_name=peer.device_name,
        device_type=peer.device_type,
        protocol=protocol,
        server_id=server.server_id,
        server_location=f"{server.city}, {server.country}",
        key_version=peer.key_version or 1,
        issued_at=issued_at.isoformat(),
        expires_at=expires_at.isoformat(),
        wireguard_config=wireguard_config,
        openvpn_config=openvpn_config,
        ikev2_config=ikev2_config,
        dns=VpnProfileDns(servers=dns_servers, enforcement="config"),
        kill_switch=kill_switch,
        peer_registered=peer_registered,
        registration_status=registration_status,
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
    await require_active_subscription(db, current_user)
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
    await require_active_subscription(db, current_user)
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
    if DEMO_MODE or WG_MOCK_MODE:
        from services.demo_vpn_service import status as demo_status

        session = demo_status(db, current_user.id)
        return ConnectionStatusResponse(
            status=session.status,
            connected=session.status == "CONNECTED",
            server_id=session.assigned_node,
            server_location=session.region,
            client_ip=session.mock_ip,
            connected_since=session.connected_since.isoformat() if session.connected_since else None,
        )

    # Check for active VPN connections (if tracking)
    active_connection = db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None)
    ).first()

    if active_connection:
        server = VPNServerService.get_server_by_id(db, str(active_connection.server_id))
        return ConnectionStatusResponse(
            status="CONNECTED",
            connected=True,
            server_id=server.server_id if server else None,
            server_location=f"{server.city}, {server.country}" if server else None,
            client_ip=active_connection.client_ip,
            connected_since=active_connection.connected_at.isoformat() if active_connection.connected_at else None,
            bytes_sent=active_connection.total_bytes_sent,
            bytes_received=active_connection.total_bytes_received,
        )

    return ConnectionStatusResponse(status="DISCONNECTED", connected=False)


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

    await require_active_subscription(db, current_user)
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
        dns_servers = _profile_dns_servers()
        keepalive = _profile_keepalive_seconds()
        mtu = _profile_mtu()

        interface_lines = [
            "[Interface]",
            f"PrivateKey = {wg_service.decrypt_private_key(current_user.wg_private_key_encrypted)}",
            f"Address = {client_ip}",
            f"DNS = {','.join(dns_servers)}",
        ]
        if mtu is not None:
            interface_lines.append(f"MTU = {mtu}")

        peer_lines = [
            "",
            "[Peer]",
            f"PublicKey = {server.wg_public_key}",
            f"Endpoint = {server.endpoint}",
            "AllowedIPs = 0.0.0.0/0, ::/0",
        ]
        if keepalive > 0:
            peer_lines.append(f"PersistentKeepalive = {keepalive}")

        config_content = "\n".join(interface_lines + peer_lines) + "\n"
        # Defensive: ensure private keys are never written with world-readable permissions.
        wg_service._write_secret_file(config_path, config_content)

    if AUTO_REGISTER_PEERS and not current_user.wg_peer_registered:
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


@router.post("/disconnect")
async def disconnect_vpn(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Mark the current VPN connection as disconnected.

    Note: This does not terminate a WireGuard tunnel on the client device.
    """
    if DEMO_MODE or WG_MOCK_MODE:
        from services.demo_vpn_service import disconnect as demo_disconnect

        session = demo_disconnect(db, current_user.id)
        return {
            "mode": "demo",
            "status": session.status,
            "disconnected_at": datetime.utcnow().isoformat(),
            "last_error": session.last_error,
        }

    active_connection = db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None)
    ).first()

    if active_connection:
        active_connection.disconnected_at = datetime.utcnow()
        db.add(active_connection)
        db.commit()

    return {
        "mode": "live",
        "status": "DISCONNECTED",
        "disconnected_at": datetime.utcnow().isoformat(),
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

    # Live mode requires active subscription
    from database.session import SessionLocal
    db = SessionLocal()
    try:
        await require_active_subscription(db, current_user)
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
    await require_active_subscription(db, current_user)
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
# Compatibility Device & Usage Endpoints (Phase 2)
# =============================================================================

@router.post("/create-device")
async def create_device(
    payload: DeviceCreateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Compatibility endpoint to create a device."""
    await require_active_subscription(db, current_user)
    peer_manager = get_peer_manager(db)

    # Enforce device limits
    from routes.devices import get_device_limit
    existing_peers = peer_manager.list_user_peers(current_user.id)
    active_count = len([p for p in existing_peers if p.is_active and not p.is_revoked])
    device_limit = get_device_limit(current_user, db)
    if active_count >= device_limit:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Device limit reached ({device_limit}). Upgrade your plan or revoke an existing device."
        )

    server = None
    if payload.server_id:
        server = VPNServerService.get_server_by_id(db, payload.server_id)
        if not server:
            raise HTTPException(status_code=404, detail="Server not found")

    peer = peer_manager.create_peer(
        user=current_user,
        server=server,
        device_name=payload.name,
        device_type=payload.device_type,
    )

    if server:
        try:
            manager = get_wireguard_server_manager()
            conn = server_connection_from_db(server)
            await manager.add_peer(conn, peer.public_key, peer.ipv4_address)
        except Exception as e:
            logger.warning(f"Peer registration deferred for device {peer.id}: {e}")

    return {
        "device_id": peer.id,
        "device_name": peer.device_name,
        "ip_address": peer.ipv4_address,
        "server_id": server.server_id if server else None,
        "status": "created",
    }


@router.post("/revoke-device")
async def revoke_device(
    payload: DeviceRevokeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Compatibility endpoint to revoke a device."""
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == payload.device_id,
        WireGuardPeer.user_id == current_user.id
    ).first()
    if not peer:
        raise HTTPException(status_code=404, detail="Device not found")

    if peer.is_revoked:
        return {"device_id": peer.id, "status": "already_revoked"}

    if peer.server_id:
        server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
        if server:
            try:
                manager = get_wireguard_server_manager()
                conn = server_connection_from_db(server)
                await manager.remove_peer(conn, peer.public_key)
            except Exception as e:
                logger.warning(f"Failed to remove peer {peer.id} from server {server.server_id}: {e}")

    peer_manager = get_peer_manager(db)
    peer_manager.revoke_peer(peer.id)
    return {"device_id": peer.id, "status": "revoked"}


@router.get("/download-config")
async def download_config_alias(
    device_id: Optional[int] = None,
    server_id: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Compatibility endpoint to download a device config."""
    await require_active_subscription(db, current_user)
    peer_manager = get_peer_manager(db)

    if device_id:
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.id == device_id,
            WireGuardPeer.user_id == current_user.id,
            WireGuardPeer.is_revoked == False
        ).first()
    else:
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.user_id == current_user.id,
            WireGuardPeer.is_revoked == False
        ).order_by(WireGuardPeer.created_at.desc()).first()

    if not peer:
        raise HTTPException(status_code=404, detail="Device not found or revoked")

    server = None
    if server_id:
        server = VPNServerService.get_server_by_id(db, server_id)
    elif peer.server_id:
        server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()

    if not server:
        raise HTTPException(status_code=404, detail="No available servers")

    filename, config = peer_manager.generate_config_file(peer, server)
    return Response(
        content=config,
        media_type="application/x-wireguard-profile",
        headers={"Content-Disposition": f'attachment; filename=\"{filename}\"'}
    )


@router.get("/usage")
async def get_usage(
    device_id: Optional[int] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return usage stats for a device or aggregated across all devices."""
    await require_active_subscription(db, current_user)
    user_tier = get_user_tier(current_user, db)

    query = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.is_revoked == False
    )
    if device_id:
        query = query.filter(WireGuardPeer.id == device_id)

    peers = query.all()
    if not peers:
        return {"total_devices": 0, "total_data_sent_mb": 0, "total_data_received_mb": 0}

    sent = sum(p.total_data_sent or 0 for p in peers)
    received = sum(p.total_data_received or 0 for p in peers)
    total_gb = (sent + received) / 1024 / 1024 / 1024
    free_cap_gb = float(os.getenv("FREE_TIER_MONTHLY_GB", "5"))
    remaining_gb = max(0.0, free_cap_gb - total_gb) if user_tier == "free" else None

    return {
        "total_devices": len(peers),
        "total_data_sent_mb": round(sent / 1024 / 1024, 2),
        "total_data_received_mb": round(received / 1024 / 1024, 2),
        "plan": user_tier,
        "cap_gb": free_cap_gb if user_tier == "free" else None,
        "remaining_gb": round(remaining_gb, 2) if remaining_gb is not None else None,
        "last_handshake": max(
            (p.last_handshake_at for p in peers if p.last_handshake_at),
            default=None,
        ).isoformat() if any(p.last_handshake_at for p in peers) else None,
    }


@router.get("/health")
async def vpn_health(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return health summary for active VPN servers."""
    servers = VPNServerService.get_active_servers(db, get_user_tier(current_user, db))
    summary = {
        "total": len(servers),
        "healthy": len([s for s in servers if s.health_status == "healthy"]),
        "degraded": len([s for s in servers if s.health_status == "degraded"]),
        "offline": len([s for s in servers if s.health_status not in ["healthy", "degraded"]]),
    }
    return {
        "status": "ok" if summary["healthy"] > 0 else "degraded",
        "summary": summary,
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
