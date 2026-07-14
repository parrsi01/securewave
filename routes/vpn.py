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
import re
import hashlib
import hmac
from datetime import datetime, timedelta
from ipaddress import ip_address, ip_network
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, Response, Request
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from models.wireguard_peer import WireGuardPeer
from models.vpn_server import VPNServer
from models.vpn_connection import VPNConnection
from models.openvpn_credential import OpenVpnCredential
from services.jwt_service import get_current_user
from utils.env_validation import demo_mode_enabled, wg_mock_mode_enabled
from services.subscription_access import require_active_subscription
from services.vpn_peer_manager import get_peer_manager
from services.wireguard_service import WireGuardService
from services.vpn_server_service import VPNServerService
from services.protocol_availability_service import ProtocolAvailabilityService
from services.openvpn_credential_manager import (
    OpenVpnCredentialError,
    OpenVpnCredentialManager,
)
from services.usage_metering_service import (
    UsageMeteringError,
    UsageMeteringService,
)
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
    ServerConnection,
)
from services.wireguard_peer_lifecycle import (
    WireGuardPeerSyncError,
    confirm_peer_assignment,
    revoke_peer_after_remote_removal,
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


def _ikev2_eap_secret() -> Optional[str]:
    return ProtocolAvailabilityService.configured_ikev2_eap_secret()


def _swanctl_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _swanctl_secret_id(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip())
    return normalized[:64] or "securewave-user"


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
    connection_recorded: bool = False
    tunnel_proven: bool = False


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


class VpnEgressEvidenceRequest(BaseModel):
    server_id: str = Field(..., min_length=1, max_length=128)
    device_id: int = Field(..., gt=0)
    protocol: str = Field(..., min_length=2, max_length=16)
    baseline_fingerprint: str = Field(
        ..., min_length=64, max_length=64, pattern=r"^[a-f0-9]{64}$"
    )


class VpnEgressBaselineResponse(BaseModel):
    fingerprint: str


class VpnEgressEvidenceResponse(BaseModel):
    verified: bool


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
    # Deliberately separate from the profile config: Linux writes it to an
    # ephemeral mode-0600 auth file and never logs or caches it with config.
    openvpn_username: Optional[str] = None
    openvpn_password: Optional[str] = None
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
        logger.info("Peer registration simulated server_id=%s", server.server_id)
        return True, "Peer registered (mock mode)"

    if not AUTO_REGISTER_PEERS:
        logger.info("Peer auto-registration disabled server_id=%s", server.server_id)
        return False, "Auto-registration disabled"

    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)

        success, message = await manager.add_peer(conn, public_key, allowed_ips)
        return success, message
    except Exception as exc:
        logger.error(
            "Failed to register peer server_id=%s exception_type=%s",
            server.server_id,
            type(exc).__name__,
        )
        return False, "registration_error"

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
    Fail-closed Linux kill switch and public-IPv6 block via wg-quick hooks.

    This uses the WireGuard fwmark to allow the tunnel handshake while
    rejecting non-tunnel traffic while the interface is active.
    """
    return (
        "PostUp = sh -c 'command -v iptables >/dev/null 2>&1 && "
        "iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) "
        "-m addrtype ! --dst-type LOCAL -m comment "
        "--comment securewave-wireguard-ipv4-kill-switch-v1 -j REJECT'\n"
        "PostDown = sh -c 'command -v iptables >/dev/null 2>&1 && "
        "iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) "
        "-m addrtype ! --dst-type LOCAL -m comment "
        "--comment securewave-wireguard-ipv4-kill-switch-v1 -j REJECT || true'\n"
        "PostUp = sh -c 'command -v ip6tables >/dev/null 2>&1 && "
        "ip6tables -I OUTPUT -d 2000::/3 -m mark ! --mark $(wg show %i fwmark) "
        "-m comment --comment securewave-wireguard-ipv6-block-v1 "
        "-j REJECT --reject-with icmp6-adm-prohibited'\n"
        "PostDown = sh -c 'command -v ip6tables >/dev/null 2>&1 && "
        "ip6tables -D OUTPUT -d 2000::/3 -m mark ! --mark $(wg show %i fwmark) "
        "-m comment --comment securewave-wireguard-ipv6-block-v1 "
        "-j REJECT --reject-with icmp6-adm-prohibited || true'\n"
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


async def _confirmed_legacy_wireguard_config(
    db: Session,
    current_user: User,
    server_id: str,
) -> tuple[WireGuardPeer, VPNServer, str]:
    """Regenerate legacy config responses without persisting raw key files."""
    server = VPNServerService.get_server_by_id(db, server_id)
    if server is None:
        raise HTTPException(status_code=404, detail="Server not found")
    readiness = ProtocolAvailabilityService().evaluate(server, "wireguard")
    if not readiness.enabled:
        raise HTTPException(status_code=503, detail=readiness.reason or "WireGuard runtime evidence is unavailable.")
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.server_id == server.id,
        WireGuardPeer.is_active.is_(True),
        WireGuardPeer.is_revoked.is_(False),
    ).order_by(WireGuardPeer.updated_at.desc()).first()
    if peer is None:
        raise HTTPException(status_code=404, detail="Configuration not found. Please allocate a profile first.")
    registered, _ = await register_peer_on_server(server, peer.public_key, peer.ipv4_address)
    if not registered:
        raise HTTPException(status_code=503, detail="VPN peer registration could not be confirmed.")
    return peer, server, _build_wireguard_profile_config(peer, server, device_type=peer.device_type)


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
        return {"wireguard", "openvpn", "ikev2"}
    return {"wireguard", "openvpn"}


def _server_supported_protocols(server: VPNServer) -> list[str]:
    availability = ProtocolAvailabilityService()
    return [
        protocol
        for protocol in ("wireguard", "openvpn", "ikev2")
        if availability.supports(server, protocol)
    ]


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

    host = _endpoint_host(server.openvpn_endpoint or "", server.public_ip).strip()
    try:
        ip_address(host)
    except ValueError:
        if (
            not host
            or len(host) > 253
            or host.endswith(".")
            or any(
                not label
                or len(label) > 63
                or label.startswith("-")
                or label.endswith("-")
                or not re.fullmatch(r"[A-Za-z0-9-]+", label)
                for label in host.split(".")
            )
        ):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenVPN endpoint metadata is invalid.",
            )
    try:
        port = int(server.openvpn_port or 1194)
    except (TypeError, ValueError):
        port = 0
    if not 1 <= port <= 65535:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OpenVPN port metadata is invalid.",
        )
    transport = (server.openvpn_transport or "udp").lower()
    if transport not in {"udp", "tcp"}:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OpenVPN transport metadata is invalid.",
        )
    ca_pem = server.openvpn_ca_cert_pem.strip()
    if (
        not ca_pem
        or "</ca" in ca_pem.lower()
        or "<" in ca_pem
        or ">" in ca_pem
        or any(not char.isprintable() and char not in "\n\r\t" for char in ca_pem)
    ):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OpenVPN CA metadata is invalid.",
        )
    dns_lines = [f"dhcp-option DNS {dns}" for dns in _profile_dns_servers()]
    return "\n".join([
        "client",
        "dev tun",
        f"proto {'tcp-client' if transport == 'tcp' else 'udp'}",
        f"remote {host} {port}",
        "resolv-retry infinite",
        "nobind",
        "persist-key",
        "persist-tun",
        "remote-cert-tls server",
        "auth-user-pass",
        "auth-nocache",
        # The OpenVPN server assigns a unique IPv6 address. A client must
        # never hard-code one here: doing so would duplicate it across peers.
        # Public IPv6 is routed into the TUN device and blocked there. OpenVPN
        # does not claim IPv6 exit capability until that is separately proven.
        "redirect-gateway def1 ipv6",
        "block-ipv6",
        *dns_lines,
        "verb 3",
        "<ca>",
        ca_pem,
        "</ca>",
        "",
    ])


def _build_ikev2_profile_config(server: VPNServer, current_user: User) -> str:
    if not server.supports_ikev2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="IKEv2 is not enabled for this server.",
        )
    remote_id = (server.ikev2_remote_id or server.public_ip or "").strip()
    remote_addrs = _endpoint_host(server.endpoint, server.public_ip).strip()
    if not server.ikev2_ca_cert_pem or not remote_id or not remote_addrs:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="IKEv2 server metadata is incomplete.",
        )
    eap_secret = _ikev2_eap_secret()
    if not eap_secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="IKEv2 EAP profile secret issuance is not configured.",
        )

    dns_servers = ",".join(_profile_dns_servers())
    eap_id = current_user.email
    secret_id = _swanctl_secret_id(eap_id)
    return "\n".join([
        "connections {",
        "  securewave {",
        "    version = 2",
        f"    remote_addrs = {remote_addrs}",
        "    proposals = aes256-sha256-modp2048",
        "    local {",
        "      auth = eap-mschapv2",
        f"      eap_id = {_swanctl_quote(eap_id)}",
        "    }",
        "    remote {",
        "      auth = pubkey",
        f"      id = {_swanctl_quote(remote_id)}",
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
        "secrets {",
        f"  eap-{secret_id} {{",
        f"    id = {_swanctl_quote(eap_id)}",
        f"    secret = {_swanctl_quote(eap_secret)}",
        "  }",
        "}",
        "# ipv6_mode = block",
        f"# dns = {dns_servers}",
        "# ca_cert_pem_begin",
        server.ikev2_ca_cert_pem.strip(),
        "# ca_cert_pem_end",
        "",
    ])


def _canonical_ip(value: str | None) -> str | None:
    try:
        return str(ip_address((value or "").strip()))
    except ValueError:
        return None


def _trusted_proxy_networks() -> list:
    networks = []
    for raw in os.getenv("SECUREWAVE_TRUSTED_PROXY_CIDRS", "").split(","):
        try:
            networks.append(ip_network(raw.strip(), strict=False))
        except ValueError:
            continue
    return networks


def _observed_egress_ip(request: Request) -> str | None:
    """Return a canonical client address without trusting arbitrary headers."""
    direct = _canonical_ip(request.client.host if request.client else None)
    if direct is None:
        return None
    direct_address = ip_address(direct)
    if not any(direct_address in network for network in _trusted_proxy_networks()):
        return direct
    forwarded = request.headers.get("x-forwarded-for", "")
    candidate = forwarded.split(",", 1)[0].strip() if forwarded else ""
    return _canonical_ip(candidate) or direct


def _egress_fingerprint(source_ip: str | None) -> str | None:
    secret = ProtocolAvailabilityService.configured_egress_evidence_secret()
    if not source_ip or not secret:
        return None
    return hmac.new(
        secret.encode("utf-8"), source_ip.encode("ascii"), hashlib.sha256
    ).hexdigest()


# =============================================================================
# Server Listing Endpoints
# =============================================================================


@router.post("/egress/baseline", response_model=VpnEgressBaselineResponse)
@rate_limit("30/minute")
async def capture_vpn_egress_baseline(
    request: Request,
    current_user: User = Depends(get_current_user),
):
    """Capture a redacted authenticated pre-connect egress observation."""
    del current_user
    fingerprint = _egress_fingerprint(_observed_egress_ip(request))
    if fingerprint is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="VPN egress evidence is not configured.",
        )
    return VpnEgressBaselineResponse(fingerprint=fingerprint)


@router.post("/egress/verify", response_model=VpnEgressEvidenceResponse)
@rate_limit("30/minute")
async def verify_vpn_egress(
    payload: VpnEgressEvidenceRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Verify a selected OpenVPN server's post-connect egress fail closed."""
    protocol = _normalize_profile_protocol(payload.protocol)
    if protocol != "openvpn":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Egress verification is required only for OpenVPN.",
        )
    server = db.query(VPNServer).filter(VPNServer.server_id == payload.server_id).first()
    if server is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="VPN server not found.")
    readiness = ProtocolAvailabilityService().evaluate(server, protocol)
    if not readiness.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=readiness.reason or "OpenVPN runtime evidence is unavailable.",
        )
    credential = db.query(OpenVpnCredential).filter(
        OpenVpnCredential.user_id == current_user.id,
        OpenVpnCredential.device_id == payload.device_id,
        OpenVpnCredential.server_id == server.id,
        OpenVpnCredential.is_active.is_(True),
        OpenVpnCredential.revoked_at.is_(None),
        OpenVpnCredential.expires_at > datetime.utcnow(),
    ).first()
    if credential is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="OpenVPN device credential is not active.",
        )

    observed = _observed_egress_ip(request)
    expected = _canonical_ip(server.public_ip)
    current_fingerprint = _egress_fingerprint(observed)
    if expected is None or current_fingerprint is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="VPN egress verification is unavailable.",
        )
    verified = (
        not hmac.compare_digest(payload.baseline_fingerprint, current_fingerprint)
        and hmac.compare_digest(observed or "", expected)
    )
    return VpnEgressEvidenceResponse(verified=verified)

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
            supports_wireguard=_server_supports_protocol(server, "wireguard"),
            supports_openvpn=_server_supports_protocol(server, "openvpn"),
            supports_ikev2=_server_supports_protocol(server, "ikev2"),
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
    availability = ProtocolAvailabilityService()
    for protocol in ("wireguard", "openvpn", "ikev2"):
        platform_supported = protocol in platform_protocols
        readiness = [availability.evaluate(server, protocol) for server in servers]
        server_enabled = any(result.enabled for result in readiness)
        enabled = platform_supported and server_enabled
        reason = None
        if not platform_supported:
            reason = f"{protocol} is not release-ready for Linux."
        elif not server_enabled:
            reason = next(
                (result.reason for result in readiness if result.reason),
                f"No usable {protocol} runtime evidence is configured.",
            )
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
        supports_wireguard=_server_supports_protocol(server, "wireguard"),
        supports_openvpn=_server_supports_protocol(server, "openvpn"),
        supports_ikev2=_server_supports_protocol(server, "ikev2"),
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
    # The historic allocation endpoint remains available, but delegates to
    # the sole profile-issuance path so it cannot bypass runtime evidence or
    # confirmed data-plane peer registration.
    profile = await provision_profile(
        request=request,
        payload=VpnProfileRequest(
            device_name=payload.device_name or "Primary Device",
            protocol="wireguard",
            server_id=payload.server_id,
        ),
        current_user=current_user,
        db=db,
    )
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.id == profile.device_id,
        WireGuardPeer.user_id == current_user.id,
    ).first()
    if peer is None:  # Defensive: profile issuance is owner-scoped.
        raise HTTPException(status_code=503, detail="VPN device state is unavailable.")

    safe_location = profile.server_location.split(",", 1)[0].replace(" ", "-").lower()
    return AllocateConfigResponse(
        status="allocated",
        server_id=profile.server_id,
        server_location=profile.server_location,
        client_ip=peer.ipv4_address,
        client_public_key=peer.public_key,
        config=profile.wireguard_config,
        qr_code=f"data:image/png;base64,{WireGuardService().qr_from_config(profile.wireguard_config)}",
        peer_registered=profile.peer_registered,
        instructions="Import the issued profile in a WireGuard client to initiate a tunnel.",
        download_filename=f"securewave-{safe_location}.conf",
    )


@router.post("/profile", response_model=VpnProfileResponse)
@rate_limit("30/minute")
async def provision_profile(
    request: Request,
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
    device_name = (payload.device_name or "This device").strip()[:64]

    # Resolve device/peer
    peer: Optional[WireGuardPeer] = None
    if payload.device_id:
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.id == payload.device_id,
            WireGuardPeer.user_id == current_user.id,
            WireGuardPeer.is_revoked == False,
        ).first()
        if not peer:
            # A supplied identifier must never silently become a new device;
            # that would conceal cross-account/old-client mistakes.
            raise HTTPException(status_code=404, detail="VPN device not found")

    if peer is None:
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.user_id == current_user.id,
            func.lower(WireGuardPeer.device_name) == device_name.lower(),
            WireGuardPeer.is_revoked == False,
        ).first()

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

    if server is None and peer is not None and peer.server_id:
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

    readiness = ProtocolAvailabilityService().evaluate(server, protocol)
    if not readiness.enabled:
        raise HTTPException(
            status_code=503,
            detail=readiness.reason or "Protocol runtime evidence is unavailable.",
        )

    # Validate every helper-accepted OpenVPN directive before creating a
    # device record or sending a credential verifier to the remote server.
    # Invalid server metadata must leave no client or server-side residue.
    validated_openvpn_config: Optional[str] = None
    if protocol == "openvpn":
        validated_openvpn_config = _build_openvpn_profile_config(server)

    # Do not generate or persist device key material until the selected
    # runtime has passed the fail-closed availability gate.  A backend outage
    # must not consume an account's device slot.
    created_peer = False
    if peer is None:
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
        peer = peer_manager.create_peer(
            user=current_user,
            server=None,
            device_name=device_name,
            device_type=device_type,
            max_active_devices=limit,
            reuse_existing_device=True,
        )
        created_peer = True

    peer_registered = False
    registration_status: Optional[str] = None
    if protocol == "wireguard":
        # Confirm the target server before issuing private-key-bearing data.
        # A migration or key rotation adds the new peer before removing the
        # old peer and rolls back both local and remote state on failure.
        try:
            peer = await confirm_peer_assignment(
                db,
                peer_manager,
                peer,
                server,
                rotate_keys=payload.force_rotate_keys,
                auto_register=AUTO_REGISTER_PEERS,
            )
        except WireGuardPeerSyncError as exc:
            # A newly created device has no previously working assignment;
            # preserve it only as an inactive retry record. Existing devices
            # retain their last confirmed assignment through the rollback.
            if peer.server_id is None:
                failed_peer = db.query(WireGuardPeer).filter(
                    WireGuardPeer.id == peer.id
                ).first()
                if failed_peer and failed_peer.server_id is None:
                    failed_peer.is_active = False
                    db.add(failed_peer)
                    db.commit()
            logger.warning(
                "VPN profile issuance denied user_id=%s device_id=%s server_id=%s exception_type=%s",
                current_user.id,
                peer.id,
                server.server_id,
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="VPN peer registration could not be confirmed.",
            ) from exc
        peer_registered = True
        registration_status = "registered"
    wireguard_config = ""
    openvpn_config: Optional[str] = None
    openvpn_username: Optional[str] = None
    openvpn_password: Optional[str] = None
    ikev2_config: Optional[str] = None
    if protocol == "wireguard":
        wireguard_config = _build_wireguard_profile_config(peer, server, device_type=payload.device_type)
    elif protocol == "openvpn":
        try:
            credential = await OpenVpnCredentialManager(db).issue(
                user_id=current_user.id,
                peer=peer,
                server=server,
                force_rotate=payload.force_rotate_keys,
            )
        except OpenVpnCredentialError as exc:
            if created_peer:
                failed_peer = db.query(WireGuardPeer).filter(
                    WireGuardPeer.id == peer.id,
                    WireGuardPeer.server_id.is_(None),
                ).first()
                if failed_peer is not None:
                    failed_peer.is_active = False
                    db.add(failed_peer)
                    db.commit()
            logger.warning(
                "OpenVPN profile issuance denied user_id=%s device_id=%s server_id=%s exception_type=%s",
                current_user.id,
                peer.id,
                server.server_id,
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OpenVPN credential issuance could not be confirmed.",
            ) from exc
        openvpn_config = validated_openvpn_config
        openvpn_username = credential.username
        openvpn_password = credential.password
        registration_status = "openvpn_credential_issued"
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
    if protocol == "openvpn":
        # The runner must fetch a fresh profile after a credential expires;
        # never let a cached configuration outlive server-side authorization.
        expires_at = min(expires_at, credential.expires_at)

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
        openvpn_username=openvpn_username,
        openvpn_password=openvpn_password,
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
    _, server, config_content = await _confirmed_legacy_wireguard_config(db, current_user, server_id)
    safe_location = server.city.replace(" ", "-").lower()
    filename = f"securewave-{safe_location}.conf"

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
    _, _, config_content = await _confirmed_legacy_wireguard_config(db, current_user, server_id)

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
        server = db.query(VPNServer).filter(VPNServer.id == active_connection.server_id).first()
        return ConnectionStatusResponse(
            status="RECORDED",
            connected=False,
            server_id=server.server_id if server else None,
            server_location=f"{server.city}, {server.country}" if server else None,
            client_ip=active_connection.client_ip,
            connected_since=active_connection.connected_at.isoformat() if active_connection.connected_at else None,
            bytes_sent=active_connection.total_bytes_sent,
            bytes_received=active_connection.total_bytes_received,
            connection_recorded=True,
            tunnel_proven=False,
        )

    return ConnectionStatusResponse(status="DISCONNECTED", connected=False)


@router.post("/connect")
async def connect_vpn(
    request: Request,
    payload: VPNConnectRequest = VPNConnectRequest(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Compatibility endpoint for demo flows and tests.

    - In demo/mock mode: uses the demo VPN session logic.
    - In live mode: issues a confirmed profile but cannot prove a client tunnel.
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

    server = VPNServerService.allocate_server_for_user(
        db, current_user, preferred_location=payload.region
    )
    if not server:
        servers = VPNServerService.get_active_servers(db, get_user_tier(current_user, db))
        if not servers:
            raise HTTPException(status_code=503, detail="No VPN servers available. Please try again later.")
        servers.sort(key=lambda s: (s.performance_score or 0), reverse=True)
        server = servers[0]
    profile = await provision_profile(
        request=request,
        payload=VpnProfileRequest(
            device_name="Primary Device",
            protocol="wireguard",
            server_id=server.server_id,
        ),
        current_user=current_user,
        db=db,
    )
    peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == profile.device_id).one()

    return {
        "mode": "live",
        "status": "PROFILE_ISSUED",
        "legacy_status": "CONNECTED",
        "tunnel_proven": False,
        "region": server.region or server.location,
        "server_id": server.server_id,
        "client_ip": peer.ipv4_address,
        "profile_expires_at": profile.expires_at,
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

    disconnected_at = datetime.utcnow()
    db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None),
    ).update(
        {
            VPNConnection.disconnected_at: disconnected_at,
            VPNConnection.finalization_reason: "legacy_disconnect",
        },
        synchronize_session=False,
    )
    db.commit()

    return {
        "mode": "live",
        "status": "DISCONNECTED",
        "disconnected_at": disconnected_at.isoformat(),
    }


@router.get("/config")
async def get_vpn_config(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Compatibility endpoint for demo flows and tests.
    Returns the latest allocated WireGuard config.
    """
    if DEMO_MODE or WG_MOCK_MODE:
        from services.demo_vpn_service import status as demo_status, build_demo_config
        session = demo_status(db, current_user.id)
        if session.status != "CONNECTED":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="VPN not connected")
        return {"mode": "demo", "config": build_demo_config(session)}

    await require_active_subscription(db, current_user)
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.server_id.isnot(None),
        WireGuardPeer.is_active.is_(True),
        WireGuardPeer.is_revoked.is_(False),
    ).order_by(WireGuardPeer.updated_at.desc()).first()
    if peer is None:
        raise HTTPException(status_code=404, detail="Configuration not found. Please allocate a config first.")
    _, _, config = await _confirmed_legacy_wireguard_config(db, current_user, str(peer.server.server_id))
    return {"mode": "live", "config": config}


@router.get("/my-configs")
async def list_my_configs(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List all VPN configurations allocated to the current user.
    """
    await require_active_subscription(db, current_user)
    peers = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.server_id.isnot(None),
        WireGuardPeer.is_active.is_(True),
        WireGuardPeer.is_revoked.is_(False),
    ).order_by(WireGuardPeer.updated_at.desc()).all()
    configs = [
        {
            "server_id": peer.server.server_id,
            "server_location": f"{peer.server.city}, {peer.server.country}",
            "created_at": peer.updated_at.isoformat() if peer.updated_at else None,
        }
        for peer in peers
        if peer.server is not None
    ]

    return {
        "configs": configs,
        "total": len(configs),
        "has_keys": bool(peers),
        "peer_registered": bool(peers),
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
    from routes.devices import _require_wireguard_runtime_evidence, get_device_limit
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
        _require_wireguard_runtime_evidence(server)

    peer = peer_manager.create_peer(
        user=current_user,
        # Keep the new device unassigned until the remote server confirms the
        # key. This compatibility endpoint must follow the primary profile
        # issuance contract as well.
        server=None,
        device_name=payload.name,
        device_type=payload.device_type,
        max_active_devices=device_limit,
    )

    if server:
        try:
            peer = await confirm_peer_assignment(
                db,
                peer_manager,
                peer,
                server,
                auto_register=AUTO_REGISTER_PEERS,
            )
        except WireGuardPeerSyncError as exc:
            peer.server_id = None
            peer.is_active = False
            db.add(peer)
            db.commit()
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="VPN peer registration could not be confirmed.",
            ) from exc

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

    peer_manager = get_peer_manager(db)
    try:
        revoked = await revoke_peer_after_remote_removal(peer_manager, peer)
    except WireGuardPeerSyncError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="VPN peer removal could not be confirmed.",
        ) from exc
    if not revoked:
        raise HTTPException(status_code=500, detail="Failed to revoke device")
    return {"device_id": peer.id, "status": "revoked"}


@router.get("/download-config")
async def download_config_alias(
    request: Request,
    device_id: Optional[int] = None,
    server_id: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Compatibility endpoint to download a device config."""
    await require_active_subscription(db, current_user)
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

    profile = await provision_profile(
        request=request,
        payload=VpnProfileRequest(
            device_id=peer.id,
            protocol="wireguard",
            server_id=server_id,
        ),
        current_user=current_user,
        db=db,
    )
    filename = f"securewave-{profile.server_id}.conf"
    return Response(
        content=profile.wireguard_config,
        media_type="application/x-wireguard-profile",
        headers={"Content-Disposition": f'attachment; filename=\"{filename}\"'}
    )


def _usage_session_response(result) -> dict:
    connection = result.connection
    return {
        "status": "recorded",
        "session_id": connection.id,
        "device_id": connection.device_id,
        "server_id": connection.server_id,
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
    """Record client metering state; this does not assert tunnel establishment."""
    await require_active_subscription(db, current_user)
    protocol = _normalize_profile_protocol(payload.protocol)
    server = VPNServerService.get_server_by_id(db, payload.server_id)
    if server is None:
        raise HTTPException(status_code=404, detail="Server not found")
    readiness = ProtocolAvailabilityService().evaluate(server, protocol)
    if not readiness.enabled:
        raise HTTPException(
            status_code=503,
            detail=readiness.reason or "Protocol runtime evidence is unavailable.",
        )
    try:
        result = UsageMeteringService(db).start_session(
            user_id=current_user.id,
            device_id=payload.device_id,
            server_id=server.id,
            protocol=protocol,
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
    """Atomically apply a monotonic, idempotent counter increment."""
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
    """Finalize a recorded session without claiming remote tunnel teardown."""
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
