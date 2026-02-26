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
import json
import time
import base64
from datetime import datetime, timedelta, timezone
from typing import Optional, List, Any, Dict, Literal, Union

from fastapi import APIRouter, Depends, HTTPException, status, Response, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session
from sqlalchemy import func

from database.session import get_db
from models.user import User
from models.wireguard_peer import WireGuardPeer
from models.vpn_credential import VPNCredential
from models.vpn_server import VPNServer
from models.vpn_connection import VPNConnection
from services.jwt_service import get_current_user
from utils.api_errors import ApiException, api_error_responses
from utils.input_sanitizer import (
    sanitize_allowed_ips,
    sanitize_device_name,
    sanitize_endpoint,
    sanitize_identifier,
    sanitize_region,
    sanitize_wireguard_key,
)
from services.subscription_access import require_active_subscription
from services.vpn_peer_manager import get_peer_manager
from services.wireguard_service import WireGuardService
from services.vpn_server_service import VPNServerService
from services.vpn_credential_service import VpnCredentialService
from services.runtime_metrics import get_runtime_metrics
from services.wireguard_tuning import tune_wireguard
from services.latency_optimizer import get_latency_optimizer
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
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

AUTO_REGISTER_PEERS = os.getenv("WG_AUTO_REGISTER_PEERS", "true").lower() == "true"
AUTO_PROVISION_CREDENTIALS = (
    os.getenv("VPN_AUTO_PROVISION_CREDENTIALS", "true").strip().lower() == "true"
    and not IS_TESTING
)

CANONICAL_PROTOCOLS = ("wireguard", "openvpn", "ikev2", "auto")
SUPPORTED_PROTOCOLS = ("wireguard", "openvpn", "ikev2")


def normalize_vpn_protocol(value: Optional[str]) -> str:
    raw = (value or "").strip().lower()
    if not raw or raw == "auto":
        return "auto"
    if raw in {"wireguard", "wg", "wire_guard"}:
        return "wireguard"
    if raw in {"openvpn", "open_vpn"}:
        return "openvpn"
    if raw in {"ikev2", "ikev2/ipsec", "ipsec"}:
        return "ikev2"
    raise ApiException(
        status_code=status.HTTP_400_BAD_REQUEST,
        code="unsupported_protocol",
        message=f"Unsupported protocol. Supported: {', '.join(CANONICAL_PROTOCOLS)}.",
        details={"protocol": value},
    )


def _parse_protocol_csv(raw: str) -> set[str]:
    out: set[str] = set()
    for item in (raw or "").split(","):
        text = item.strip().lower()
        if not text:
            continue
        try:
            normalized = normalize_vpn_protocol(text)
        except ApiException:
            continue
        if normalized == "auto":
            continue
        out.add(normalized)
    return out


def _enabled_protocols() -> set[str]:
    raw = os.getenv("SECUREWAVE_ENABLED_PROTOCOLS", "wireguard,openvpn,ikev2")
    out = _parse_protocol_csv(raw)
    return out or {"wireguard"}


def _plan_allowed_protocols(user_tier: str) -> set[str]:
    tier = (user_tier or "free").strip().lower()
    env_name = {
        "free": "SECUREWAVE_PLAN_PROTOCOLS_FREE",
        "basic": "SECUREWAVE_PLAN_PROTOCOLS_BASIC",
        "premium": "SECUREWAVE_PLAN_PROTOCOLS_PREMIUM",
        "pro": "SECUREWAVE_PLAN_PROTOCOLS_PRO",
        "ultra": "SECUREWAVE_PLAN_PROTOCOLS_ULTRA",
    }.get(tier)
    if env_name:
        raw = os.getenv(env_name, "").strip()
    else:
        raw = ""
    if not raw:
        raw = "wireguard,openvpn,ikev2"
    out = _parse_protocol_csv(raw)
    return out or {"wireguard"}

VPN_ERROR_RESPONSES = api_error_responses(
    {
        400: "Invalid request payload",
        401: "Authentication required",
        403: "Request forbidden for current subscription/device state",
        404: "Requested resource not found",
        429: "Too many requests",
        503: "No VPN nodes available",
    }
)


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
    supported_protocols: List[str] = Field(default_factory=list, description="Protocols supported by this server")
    public_ip: Optional[str] = None
    latency_priority: Optional[int] = None


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

    @field_validator("server_id")
    @classmethod
    def _validate_server_id(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_identifier(value, field_name="server_id")

    @field_validator("device_name")
    @classmethod
    def _validate_device_name(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_device_name(value)


class VPNConnectRequest(BaseModel):
    """Compatibility request to initiate a VPN connection."""
    region: Optional[str] = Field(
        None,
        description="Preferred region or server identifier (best effort)."
    )
    server_id: Optional[str] = Field(
        None,
        description="Exact server_id for connection notification (preferred over region hint).",
    )
    protocol: Optional[str] = Field(
        None,
        description="Effective protocol used by the client (wireguard/openvpn/ikev2/auto).",
    )

    @field_validator("region")
    @classmethod
    def _validate_region(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_region(value)

    @field_validator("server_id")
    @classmethod
    def _validate_server_id(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_identifier(value, field_name="server_id")

    @field_validator("protocol")
    @classmethod
    def _validate_protocol(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return normalize_vpn_protocol(value)


class DeviceCreateRequest(BaseModel):
    """Compatibility request to create a VPN device."""
    name: str = Field(..., min_length=1, max_length=50)
    device_type: Optional[str] = Field(None, description="windows, macos, linux, ios, android")
    server_id: Optional[str] = Field(None, description="Preferred server ID")

    @field_validator("name")
    @classmethod
    def _validate_name(cls, value: str) -> str:
        return sanitize_device_name(value)

    @field_validator("server_id")
    @classmethod
    def _validate_server_id(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_identifier(value, field_name="server_id")


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


class RegionProtocolSupport(BaseModel):
    wireguard: bool
    openvpn: bool
    ikev2: bool


class RegionRegistryEntry(BaseModel):
    id: str
    display_name: str
    public_ip: str
    protocol_support: RegionProtocolSupport
    health_status: str
    latency_priority: int
    region: Optional[str] = None
    city: Optional[str] = None
    country: Optional[str] = None
    country_code: Optional[str] = None
    private_ip: Optional[str] = None
    hcloud_location: Optional[str] = None
    tier_restriction: Optional[str] = None  # None=free, 'premium'=premium only


class RegionRegistryResponse(BaseModel):
    regions: List[RegionRegistryEntry]
    total: int
    recommended_id: Optional[str] = None


class RecommendedServerCandidate(BaseModel):
    server_id: str
    score: float
    rtt_ms: float
    rtt_source: str
    rtt_samples: int
    load_percent: float
    health_status: str
    consecutive_health_failures: int
    region: Optional[str] = None


class RecommendedServerResponse(BaseModel):
    generated_at: str
    user_region_hint: Optional[str] = None
    recommended_server_id: Optional[str] = None
    baselines: dict
    rtt_window_seconds: int
    rtt_min_samples: int
    candidates: Optional[List[RecommendedServerCandidate]] = None


class VpnProtocolRequirement(BaseModel):
    key: str
    description: str


class VpnProtocolAvailability(BaseModel):
    protocol: str
    enabled: bool
    server_enabled: bool
    plan_enabled: bool
    platform_supported: bool
    transports: Optional[List[str]] = None
    requirements: List[VpnProtocolRequirement] = Field(default_factory=list)
    reason: Optional[str] = None


class VpnProtocolsResponse(BaseModel):
    user_tier: str
    device_type: Optional[str] = None
    protocols: List[VpnProtocolAvailability]


class ProtocolCapabilityStatus(BaseModel):
    wireguard: bool
    openvpn: bool
    ikev2: bool
    server_counts: Dict[str, int]
    checked_at: str


class VpnCredentialProvisionRequest(BaseModel):
    protocol: str = Field(..., description="Protocol to provision (openvpn or ikev2)")
    device_id: Optional[int] = Field(None, description="Existing device ID")
    device_name: Optional[str] = Field(None, max_length=64, description="Device name when creating/finding a device")
    device_type: Optional[str] = Field(None, description="windows, macos, linux, ios, android")
    server_id: Optional[str] = Field(None, description="Preferred server ID")
    rotate_if_exists: bool = Field(False, description="Rotate active credential before issuing a new one")

    @field_validator("protocol")
    @classmethod
    def _validate_protocol(cls, value: str) -> str:
        normalized = normalize_vpn_protocol(value)
        if normalized not in {"openvpn", "ikev2"}:
            raise ValueError("Provisioning supports openvpn and ikev2 only.")
        return normalized

    @field_validator("device_name")
    @classmethod
    def _validate_device_name(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_device_name(value)

    @field_validator("server_id")
    @classmethod
    def _validate_server_id(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_identifier(value, field_name="server_id")

    @field_validator("device_type")
    @classmethod
    def _validate_device_type(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().lower()
        allowed = {"windows", "macos", "linux", "ios", "android"}
        if normalized not in allowed:
            raise ValueError(
                f"Unsupported device_type '{value}'. Supported: {', '.join(sorted(allowed))}."
            )
        return normalized


class VpnCredentialSummary(BaseModel):
    id: int
    protocol: str
    credential_type: str
    device_id: int
    server_id: int
    username: str
    cert_serial: Optional[str] = None
    cert_fingerprint_sha256: Optional[str] = None
    profile_expires_at: Optional[str] = None
    revoked_at: Optional[str] = None
    revoke_reason: Optional[str] = None
    revision: int
    last_provisioned_at: Optional[str] = None
    last_rotated_at: Optional[str] = None


class VpnCredentialProvisionResponse(BaseModel):
    status: str
    credential: VpnCredentialSummary
    profile: Optional[Dict[str, Any]] = None


class VpnCredentialListResponse(BaseModel):
    credentials: List[VpnCredentialSummary]
    total: int


class VpnCredentialLifecycleResponse(BaseModel):
    status: str
    credential: VpnCredentialSummary


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
    protocol: Optional[str] = Field(
        None,
        description="Desired VPN protocol (auto/wireguard/openvpn/ikev2). Omit or set 'auto' to let the server decide.",
    )
    server_id: Optional[str] = Field(None, description="Preferred server ID (null = auto)")
    force_rotate_keys: bool = Field(False, description="Rotate device keys before issuing a profile")

    @field_validator("device_name")
    @classmethod
    def _validate_device_name(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_device_name(value)

    @field_validator("server_id")
    @classmethod
    def _validate_server_id(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return sanitize_identifier(value, field_name="server_id")

    @field_validator("device_type")
    @classmethod
    def _validate_device_type(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().lower()
        allowed = {"windows", "macos", "linux", "ios", "android"}
        if normalized not in allowed:
            raise ValueError(
                f"Unsupported device_type '{value}'. Supported: {', '.join(sorted(allowed))}."
            )
        return normalized


class VpnProfileDns(BaseModel):
    mode: str = "tunnel"
    servers: List[str]
    ad_malware_blocking: str = "on"
    enforcement: str = "best_effort"


class VpnProfileKillSwitch(BaseModel):
    mode: str
    enforcement: str
    notes: Optional[str] = None


class VpnWireGuardProfilePayload(BaseModel):
    type: Literal["wireguard"] = "wireguard"
    wireguard_config: str


class VpnOpenVpnProfilePayload(BaseModel):
    type: Literal["openvpn"] = "openvpn"
    ovpn_config: str
    auth_method: Literal["mtls", "userpass"] = "userpass"
    username: Optional[str] = None
    password: Optional[str] = None
    cert_serial: Optional[str] = None
    cert_fingerprint_sha256: Optional[str] = None


class VpnIkev2ProfilePayload(BaseModel):
    type: Literal["ikev2"] = "ikev2"
    auth_method: Literal["eap-tls", "eap-mschapv2"] = "eap-mschapv2"
    server: str
    remote_id: Optional[str] = None
    username: Optional[str] = None
    password: Optional[str] = None
    ca_cert_pem: Optional[str] = None
    client_pkcs12_base64: Optional[str] = None
    client_pkcs12_password: Optional[str] = None
    cert_serial: Optional[str] = None
    cert_fingerprint_sha256: Optional[str] = None


VpnProtocolProfilePayload = Union[
    VpnWireGuardProfilePayload,
    VpnOpenVpnProfilePayload,
    VpnIkev2ProfilePayload,
]


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
    wireguard_config: Optional[str] = None
    profile: Optional[VpnProtocolProfilePayload] = None
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


def _sh_quote(value: str) -> str:
    # Minimal POSIX shell escaping for single-quoted arguments.
    return "'" + value.replace("'", "'\"'\"'") + "'"


async def provision_protocol_credentials_on_server(
    *,
    server: VPNServer,
    protocol: str,
    username: str,
    password: str,
) -> tuple[bool, str]:
    """
    Best-effort data-plane provisioning for non-WireGuard credentials.

    Requires the VM provisioning script to install the helper scripts:
    - /usr/local/bin/securewave-openvpn-upsert-user
    - /usr/local/bin/securewave-ikev2-upsert-user
    """
    if not AUTO_PROVISION_CREDENTIALS:
        return False, "Auto provisioning disabled"

    normalized = normalize_vpn_protocol(protocol)
    if normalized == "wireguard" or normalized == "auto":
        return False, "not_applicable"

    script = None
    if normalized == "openvpn":
        script = "securewave-openvpn-upsert-user"
    elif normalized == "ikev2":
        script = "securewave-ikev2-upsert-user"

    if not script:
        return False, "unsupported_protocol"

    password_b64 = base64.b64encode(password.encode("utf-8")).decode("ascii")

    cmd = (
        "sudo "
        + script
        + " --username "
        + _sh_quote(username)
        + " --password-b64 "
        + _sh_quote(password_b64)
    )
    try:
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        success, stdout, stderr = await manager.run_ssh_command(conn, cmd)
        if success:
            message = (stdout or "").strip() or "credential_provisioned"
            return True, message
        message = (stderr or "").strip() or (stdout or "").strip() or "credential_provision_failed"
        return False, message
    except Exception as exc:
        return False, str(exc)

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


def _resolve_wireguard_tuning(
    request: Request,
    server: VPNServer,
    *,
    device_type: Optional[str],
) -> tuple[Optional[int], int, bool, float]:
    tuning = tune_wireguard(
        endpoint=server.endpoint,
        client_ip=request.client.host if request.client else None,
        forwarded_for=request.headers.get("x-forwarded-for"),
        observed_latency_ms=server.latency_ms,
        device_type=device_type,
        packet_loss=server.packet_loss,
        jitter_ms=server.jitter_ms,
        server_health_status=server.health_status,
    )
    return tuning.mtu, tuning.keepalive_seconds, tuning.nat_detected, tuning.mtu_probe_ms


def _log_vpn_event(event: str, **fields) -> None:
    logger.info(json.dumps({"event": event, **fields}, sort_keys=True))


def _utc_iso(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat()


_COUNTRY_NAME_BY_CODE: dict[str, str] = {
    "US": "United States",
    "DE": "Germany",
    "FI": "Finland",
    "SG": "Singapore",
    "NL": "Netherlands",
    "GB": "United Kingdom",
    "FR": "France",
    "CA": "Canada",
    "MX": "Mexico",
    "JP": "Japan",
    "AU": "Australia",
}


def _server_display_location_fields(server: VPNServer) -> tuple[str, str, str, str]:
    city = str(getattr(server, "city", "") or "").strip()
    country_code = str(getattr(server, "country_code", "") or "").strip().upper()
    country = str(getattr(server, "country", "") or "").strip()
    if len(country) == 2 and country.isalpha():
        country = _COUNTRY_NAME_BY_CODE.get(country.upper(), country.upper())
    elif not country and country_code:
        country = _COUNTRY_NAME_BY_CODE.get(country_code, country_code)

    location = str(getattr(server, "location", "") or "").strip()
    if not location:
        parts = [part for part in (city, country or country_code) if part]
        location = ", ".join(parts) if parts else str(getattr(server, "server_id", "") or "Unknown")

    if not city:
        city = location.split(",", 1)[0].strip() if location else "Unknown"
    if not country:
        country = _COUNTRY_NAME_BY_CODE.get(country_code, country_code or "Unknown")
    if not country_code and len(country) == 2 and country.isalpha():
        country_code = country.upper()
    if not country_code:
        country_code = "ZZ"

    return location, country, country_code, city


def _normalized_region_label(server: VPNServer) -> str:
    region = str(getattr(server, "region", "") or "").strip()
    return region or "Other"


def _barbados_latency_priority(server: VPNServer) -> int:
    """
    Lower number = higher preference for Barbados-first routing.

    Priority order:
    10  Ashburn / US East
    20  Miami (if present in future/current fleet)
    30  Montreal (if present)
    100 Germany/Frankfurt-class EU fallback
    150 Other Americas
    200 Other Europe
    300 Everything else
    """
    hcloud_location = str(getattr(server, "hcloud_location", "") or "").strip().lower()
    server_id = str(getattr(server, "server_id", "") or "").strip().lower()
    location = str(getattr(server, "location", "") or "").strip().lower()
    city = str(getattr(server, "city", "") or "").strip().lower()
    country_code = str(getattr(server, "country_code", "") or "").strip().upper()
    region = _normalized_region_label(server).lower()

    tags = f"{hcloud_location} {server_id} {location} {city}"
    if "ash" in tags or "ashburn" in tags:
        return 10
    if "mia" in tags or "miami" in tags:
        return 20
    if "yul" in tags or "ymq" in tags or "montreal" in tags or "montréal" in tags:
        return 30

    if "frankfurt" in tags:
        return 100
    if country_code == "DE" or hcloud_location in {"fsn1", "nbg1"}:
        return 110

    if region in {"caribbean"}:
        return 120
    if region == "americas":
        return 150
    if region == "europe":
        return 200
    if region == "asia-pacific":
        return 300
    if region == "middle east & africa":
        return 320
    return 400


def _server_protocol_support_map(server: VPNServer) -> dict[str, bool]:
    return {
        "wireguard": bool(getattr(server, "supports_wireguard", True)),
        "openvpn": bool(getattr(server, "supports_openvpn", False)),
        "ikev2": bool(getattr(server, "supports_ikev2", False)),
    }


def _server_health_allows_protocol(server: VPNServer) -> bool:
    health = str(getattr(server, "health_status", "") or "unknown").strip().lower()
    return health in {"healthy", "degraded", "unknown"}


def _server_protocol_effective_available(server: VPNServer, protocol: str) -> bool:
    return _server_health_allows_protocol(server) and _server_protocol_material_ready(server, protocol)


def _server_protocol_material_ready(server: VPNServer, protocol: str) -> bool:
    support = _server_protocol_support_map(server)
    protocol = normalize_vpn_protocol(protocol)
    if protocol == "wireguard":
        return support["wireguard"] and bool((getattr(server, "wg_public_key", "") or "").strip()) and bool(
            (getattr(server, "endpoint", "") or "").strip()
        )
    if protocol == "openvpn":
        if not support["openvpn"]:
            return False
        endpoint = str(getattr(server, "openvpn_endpoint", "") or getattr(server, "public_ip", "") or "").strip()
        port = int(getattr(server, "openvpn_port", 0) or 0)
        transport = str(getattr(server, "openvpn_transport", "") or "").strip().lower()
        auth_mode = _openvpn_auth_mode()
        ca_cert = str(getattr(server, "openvpn_ca_cert_pem", "") or "").strip()
        if not endpoint or port <= 0 or transport not in {"udp", "tcp"}:
            return False
        if auth_mode == "mtls" and not ca_cert:
            return False
        return True
    if protocol == "ikev2":
        if not support["ikev2"]:
            return False
        auth_mode = _ikev2_auth_mode()
        remote_id = str(getattr(server, "ikev2_remote_id", "") or "").strip()
        ca_cert = str(getattr(server, "ikev2_ca_cert_pem", "") or "").strip()
        # EAP-MSCHAPv2 can operate with endpoint identity only; EAP-TLS requires CA.
        if auth_mode == "eap-tls" and not ca_cert:
            return False
        return bool(remote_id or ca_cert or getattr(server, "public_ip", None))
    return False


def _region_registry_entry(server: VPNServer) -> RegionRegistryEntry:
    location, country, country_code, city = _server_display_location_fields(server)
    effective_support = {
        protocol: _server_protocol_effective_available(server, protocol)
        for protocol in ("wireguard", "openvpn", "ikev2")
    }
    tier_restriction = str(getattr(server, "tier_restriction", "") or "").strip() or None
    return RegionRegistryEntry(
        id=server.server_id,
        display_name=location,
        public_ip=str(server.public_ip),
        protocol_support=RegionProtocolSupport(**effective_support),
        health_status=str(server.health_status or "unknown"),
        latency_priority=_barbados_latency_priority(server),
        region=_normalized_region_label(server),
        city=city,
        country=country,
        country_code=country_code,
        private_ip=str(server.private_ip).strip() if getattr(server, "private_ip", None) else None,
        hcloud_location=str(getattr(server, "hcloud_location", "") or "").strip() or None,
        tier_restriction=tier_restriction,
    )


def _linux_route_snippet() -> str:
    """
    Linux-safe wg-quick routing hooks that avoid disrupting NetworkManager.

    Root cause of WiFi toggling: wg-quick with AllowedIPs=0.0.0.0/0 replaces
    the default route in the main routing table, causing NetworkManager to detect
    that the WiFi interface has lost its default route and triggering WiFi
    reconnect cycles.

    Fix: Use Table=off to tell wg-quick NOT to manage routing at all, then add
    a minimal host route to the VPN server so the handshake can reach it, plus
    a default route through the tunnel interface in a separate routing table
    (table 51820 is the wg-quick default). We use ip rule to policy-route all
    traffic through the tunnel without touching the main table's default route.

    This keeps NetworkManager's view of the WiFi interface intact while still
    tunnelling all outbound traffic through the VPN.

    Note: PostUp/PostDown run as root (via wg-quick). The %i token expands to
    the interface name (e.g., sw-wg).
    """
    return (
        # Use policy routing table 51820 (wg-quick default).
        # Add a default route through the tunnel in that table.
        "PostUp = ip route add default dev %i table 51820 2>/dev/null || true\n"
        # Add ip rule to send all non-tunnel traffic through table 51820.
        "PostUp = ip rule add not fwmark 51820 table 51820 priority 32764 2>/dev/null || true\n"
        # Cleanup on tunnel down — remove the rule and route.
        "PostDown = ip rule del not fwmark 51820 table 51820 priority 32764 2>/dev/null || true\n"
        "PostDown = ip route del default dev %i table 51820 2>/dev/null || true\n"
    )


def _build_wireguard_profile_config(
    request: Request,
    peer: WireGuardPeer,
    server: VPNServer,
    *,
    device_type: Optional[str],
) -> str:
    wg_service = WireGuardService()
    private_key = wg_service.decrypt_private_key(peer.private_key_encrypted)
    dns_servers = _profile_dns_servers()
    mtu, keepalive, _, _ = _resolve_wireguard_tuning(request, server, device_type=device_type)
    try:
        endpoint = sanitize_endpoint(server.endpoint)
        server_pubkey = sanitize_wireguard_key(server.wg_public_key, field_name="wg_public_key")
        allowed_ips = sanitize_allowed_ips(server.allowed_ips or "0.0.0.0/0, ::/0")
    except ValueError as exc:
        raise ApiException(
            status_code=500,
            code="invalid_server_config",
            message="The selected VPN server has an invalid WireGuard configuration.",
            details={"server_id": server.server_id, "reason": str(exc)},
        )

    is_linux = (device_type or "").lower() == "linux"

    interface_lines = [
        "[Interface]",
        f"PrivateKey = {private_key}",
        f"Address = {peer.ipv4_address}",
        f"DNS = {','.join(dns_servers)}",
    ]
    if mtu is not None:
        interface_lines.append(f"MTU = {mtu}")

    if is_linux:
        # Table=off: tell wg-quick NOT to manage routing or modify the main
        # routing table. This prevents NetworkManager from detecting that the
        # WiFi interface's default route was removed, which caused WiFi to toggle
        # on VPN connect/disconnect. We manage routing ourselves via PostUp/PostDown.
        interface_lines.append("Table = off")
        # FwMark is required when using policy routing with Table=off. Without
        # it, the encrypted UDP packets to the WireGuard endpoint can be routed
        # back into the tunnel (recursive routing), which prevents handshakes.
        interface_lines.append("FwMark = 51820")
        # NOTE: wg-quick supports PostUp/PostDown hooks; mobile/embedded WireGuard
        # parsers do not. Only include these for Linux wg-quick builds.
        interface_lines.append(_linux_route_snippet().rstrip("\n"))

    peer_lines = [
        "",
        "[Peer]",
        f"PublicKey = {server_pubkey}",
        f"Endpoint = {endpoint}",
        f"AllowedIPs = {allowed_ips}",
    ]
    if keepalive > 0:
        peer_lines.append(f"PersistentKeepalive = {keepalive}")

    return "\n".join(interface_lines + peer_lines) + "\n"


def _read_optional_pem_from_env(*, pem_env: str, path_env: str) -> Optional[str]:
    raw = os.getenv(pem_env, "").strip()
    if raw:
        return raw
    path = os.getenv(path_env, "").strip()
    if not path:
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return None


def _build_openvpn_profile(
    server: VPNServer,
    *,
    username: str,
    password: str,
    device_type: Optional[str],
    dns_servers: Optional[list[str]] = None,
) -> VpnOpenVpnProfilePayload:
    transport = (getattr(server, "openvpn_transport", "") or "udp").strip().lower()
    if transport not in {"udp", "tcp"}:
        raise ApiException(
            status_code=500,
            code="invalid_server_config",
            message="The selected VPN server has an invalid OpenVPN transport configuration.",
            details={"server_id": server.server_id, "transport": transport},
        )

    port = int(getattr(server, "openvpn_port", 1194) or 1194)
    host = (getattr(server, "openvpn_endpoint", None) or server.public_ip or "").strip()
    if not host:
        raise ApiException(
            status_code=500,
            code="invalid_server_config",
            message="The selected VPN server is missing an OpenVPN endpoint.",
            details={"server_id": server.server_id},
        )

    # Validate host:port string for basic safety.
    try:
        sanitize_endpoint(f"{host}:{port}")
    except ValueError as exc:
        raise ApiException(
            status_code=500,
            code="invalid_server_config",
            message="The selected VPN server has an invalid OpenVPN endpoint.",
            details={"server_id": server.server_id, "reason": str(exc)},
        )

    ca_cert = (getattr(server, "openvpn_ca_cert_pem", None) or "").strip()
    if not ca_cert:
        ca_cert = _read_optional_pem_from_env(
            pem_env="SECUREWAVE_OPENVPN_CA_CERT_PEM",
            path_env="SECUREWAVE_OPENVPN_CA_CERT_PATH",
        ) or ""
    if not ca_cert:
        raise ApiException(
            status_code=500,
            code="invalid_server_config",
            message="The selected VPN server is missing an OpenVPN CA certificate.",
            details={"server_id": server.server_id},
        )

    proto_line = "proto tcp-client" if transport == "tcp" else "proto udp"

    extra: list[str] = []
    if (device_type or "").strip().lower() == "windows":
        # Best-effort DNS leak mitigation on Windows when using OpenVPN.
        extra.append("setenv opt block-outside-dns")

    ovpn_lines = [
        "client",
        "dev tun",
        proto_line,
        f"remote {host} {port}",
        "resolv-retry infinite",
        "nobind",
        "persist-key",
        "persist-tun",
        "remote-cert-tls server",
        "auth-user-pass",
        "auth-nocache",
        "verb 3",
        *[f"dhcp-option DNS {dns}" for dns in (dns_servers or []) if dns.strip()],
        *extra,
        "<ca>",
        ca_cert.strip(),
        "</ca>",
        "",
    ]

    return VpnOpenVpnProfilePayload(
        ovpn_config="\n".join(ovpn_lines),
        auth_method="userpass",
        username=username,
        password=password,
    )


def _build_ikev2_profile(
    server: VPNServer,
    *,
    username: str,
    password: str,
) -> VpnIkev2ProfilePayload:
    ca_cert = (getattr(server, "ikev2_ca_cert_pem", None) or "").strip()
    if not ca_cert:
        ca_cert = _read_optional_pem_from_env(
            pem_env="SECUREWAVE_IKEV2_CA_CERT_PEM",
            path_env="SECUREWAVE_IKEV2_CA_CERT_PATH",
        ) or ""

    remote_id = (getattr(server, "ikev2_remote_id", None) or "").strip() or None
    server_host = remote_id or (server.public_ip or "").strip()
    if not server_host:
        raise ApiException(
            status_code=500,
            code="invalid_server_config",
            message="The selected VPN server is missing an IKEv2 endpoint.",
            details={"server_id": server.server_id},
        )

    return VpnIkev2ProfilePayload(
        auth_method="eap-mschapv2",
        server=server_host,
        remote_id=remote_id,
        username=username,
        password=password,
        ca_cert_pem=ca_cert or None,
    )


def _safe_server_peer_values(server: VPNServer) -> tuple[str, str, str]:
    try:
        return (
            sanitize_wireguard_key(server.wg_public_key, field_name="wg_public_key"),
            sanitize_endpoint(server.endpoint),
            sanitize_allowed_ips(server.allowed_ips or "0.0.0.0/0, ::/0"),
        )
    except ValueError as exc:
        raise ApiException(
            status_code=500,
            code="invalid_server_config",
            message="The selected VPN server has an invalid WireGuard configuration.",
            details={"server_id": server.server_id, "reason": str(exc)},
        )


def _server_supported_protocols(server: VPNServer) -> list[str]:
    out: list[str] = []
    if getattr(server, "supports_wireguard", True):
        out.append("wireguard")
    if getattr(server, "supports_openvpn", False):
        out.append("openvpn")
    if getattr(server, "supports_ikev2", False):
        out.append("ikev2")
    return out


def _server_supports_protocol(server: VPNServer, protocol: str) -> bool:
    normalized = normalize_vpn_protocol(protocol)
    if normalized == "auto":
        return True
    supported = _server_supported_protocols(server)
    return normalized in supported


def _server_effective_supported_protocols(server: VPNServer) -> list[str]:
    out: list[str] = []
    for protocol in ("wireguard", "openvpn", "ikev2"):
        if _server_protocol_effective_available(server, protocol):
            out.append(protocol)
    return out


def _auto_protocol_order() -> list[str]:
    raw = os.getenv("SECUREWAVE_AUTO_PROTOCOL_ORDER", "").strip()
    if not raw:
        raw = "wireguard,openvpn,ikev2"
    out: list[str] = []
    for part in raw.split(","):
        part = part.strip().lower()
        if not part:
            continue
        try:
            normalized = normalize_vpn_protocol(part)
        except ApiException:
            continue
        if normalized == "auto":
            continue
        if normalized not in out:
            out.append(normalized)
    if not out:
        out = ["wireguard", "openvpn", "ikev2"]
    return out


def _platform_supported_protocols(device_type: Optional[str]) -> set[str]:
    dt = (device_type or "").strip().lower()
    if dt in {"windows", "linux", "macos"}:
        return set(SUPPORTED_PROTOCOLS)
    if dt in {"android", "ios"}:
        return {"wireguard"}
    # Default to the safest/common denominator.
    return {"wireguard"}


def _protocol_requirements(protocol: str) -> list[VpnProtocolRequirement]:
    if protocol == "wireguard":
        return [
            VpnProtocolRequirement(
                key="native_tunnel_runtime",
                description="WireGuard runtime must be installed and available on the device.",
            )
        ]
    if protocol == "openvpn":
        return [
            VpnProtocolRequirement(
                key="openvpn_client",
                description="OpenVPN client/runtime must be installed on the device.",
            ),
            VpnProtocolRequirement(
                key="server_ca_certificate",
                description="Backend/server must provide a valid OpenVPN CA certificate.",
            ),
        ]
    if protocol == "ikev2":
        return [
            VpnProtocolRequirement(
                key="ikev2_runtime",
                description="OS must support IKEv2/IPsec with username/password credentials.",
            ),
            VpnProtocolRequirement(
                key="server_identity",
                description="Server endpoint/remote identity and CA trust chain must be valid.",
            ),
        ]
    return []


def _protocol_server_unavailable_code(protocol: str, *, scope: str) -> str:
    normalized = normalize_vpn_protocol(protocol)
    if normalized not in {"openvpn", "ikev2"}:
        return "protocol_temporarily_unavailable"
    if scope == "region":
        return f"{normalized}_unavailable_region"
    if scope == "health":
        return f"{normalized}_healthcheck_fail"
    if scope == "config":
        return f"{normalized}_server_misconfigured"
    return f"{normalized}_temporarily_unavailable"


def _debug_client_label(request: Request) -> str:
    ua = (request.headers.get("user-agent") or "").lower()
    if "securewave" in ua:
        return "securewave-client"
    if "flutter" in ua:
        return "flutter-client"
    return "generic-client"


def _log_vpn_catalog_debug(
    *,
    request: Request,
    endpoint: str,
    user_tier: str,
    device_type: Optional[str],
    servers: list[VPNServer],
    protocol_payload: Optional[list[VpnProtocolAvailability]] = None,
) -> None:
    # Controlled debug signal for protocol/location visibility mismatches in app clients.
    if os.getenv("SECUREWAVE_LOG_VPN_CATALOG_DEBUG", "true").strip().lower() not in {"1", "true", "yes", "on"}:
        return

    sample_locations = [str(getattr(s, "location", "") or "") for s in servers[:5]]
    supported_counts = {
        "wireguard": sum(1 for s in servers if getattr(s, "supports_wireguard", True)),
        "openvpn": sum(1 for s in servers if getattr(s, "supports_openvpn", False)),
        "ikev2": sum(1 for s in servers if getattr(s, "supports_ikev2", False)),
    }
    protocol_summary = None
    if protocol_payload is not None:
        protocol_summary = {
            item.protocol: {
                "enabled": item.enabled,
                "server_enabled": item.server_enabled,
                "plan_enabled": item.plan_enabled,
                "platform_supported": item.platform_supported,
                "reason": item.reason,
            }
            for item in protocol_payload
        }

    logger.info(
        "vpn_catalog_debug endpoint=%s client=%s device_type=%s user_tier=%s total_servers=%d supported_counts=%s sample_locations=%s protocols=%s",
        endpoint,
        _debug_client_label(request),
        device_type or "-",
        user_tier,
        len(servers),
        supported_counts,
        sample_locations,
        protocol_summary if protocol_summary is not None else "-",
    )


def choose_effective_protocol(
    *,
    server: VPNServer,
    requested_protocol: str,
    device_type: Optional[str],
    allowed_protocols: set[str],
) -> str:
    requested = normalize_vpn_protocol(requested_protocol)
    supported_by_platform = _platform_supported_protocols(device_type)
    if requested != "auto":
        if requested not in allowed_protocols:
            raise ApiException(
                status_code=403,
                code="protocol_plan_restricted",
                message="Requested protocol is not enabled for this account plan.",
                details={"protocol": requested},
            )
        if requested not in supported_by_platform:
            raise ApiException(
                status_code=400,
                code="protocol_not_supported_on_platform",
                message="Requested protocol is not supported on this platform.",
                details={"protocol": requested, "device_type": device_type},
            )
        if not _server_supports_protocol(server, requested):
            raise ApiException(
                status_code=409,
                code="protocol_not_supported_on_server",
                message="Requested protocol is not enabled on the selected server.",
                details={"protocol": requested, "server_id": server.server_id},
            )
        return requested

    preferred_raw = (getattr(server, "protocol", None) or "").strip()
    if preferred_raw:
        try:
            preferred = normalize_vpn_protocol(preferred_raw)
        except ApiException:
            preferred = "auto"
        if (
            preferred != "auto"
            and preferred in supported_by_platform
            and preferred in allowed_protocols
            and _server_protocol_effective_available(server, preferred)
        ):
            return preferred

    for candidate in _auto_protocol_order():
        if (
            candidate in supported_by_platform
            and candidate in allowed_protocols
            and _server_protocol_effective_available(server, candidate)
        ):
            return candidate

    # Defensive fallback to preserve backward compatibility.
    supported = _server_effective_supported_protocols(server)
    for candidate in supported:
        if candidate in supported_by_platform and candidate in allowed_protocols:
            return candidate
    raise ApiException(
        status_code=409,
        code="no_protocol_available",
        message="No VPN protocol is available for this platform/account/server combination.",
        details={"server_id": server.server_id, "device_type": device_type},
    )


def _openvpn_auth_mode() -> str:
    # Default to userpass so provisioning works without a CA/PKI infrastructure.
    # Set SECUREWAVE_OPENVPN_AUTH_MODE=mtls in production when CA certs are
    # configured on all VPN servers via sync_vpn_servers.py --openvpn-ca-cert-path.
    raw = os.getenv("SECUREWAVE_OPENVPN_AUTH_MODE", "userpass").strip().lower()
    if raw in {"mtls", "tls", "cert"}:
        return "mtls"
    return "userpass"


def _ikev2_auth_mode() -> str:
    # Default to eap-mschapv2 (username+password) so provisioning works without
    # a CA/PKI infrastructure. Set SECUREWAVE_IKEV2_AUTH_MODE=eap-tls in
    # production when CA certs are configured on all VPN servers.
    raw = os.getenv("SECUREWAVE_IKEV2_AUTH_MODE", "eap-mschapv2").strip().lower()
    if raw in {"eap-mschapv2", "mschapv2", "userpass"}:
        return "eap-mschapv2"
    return "eap-tls"


def _credential_summary(record: VPNCredential) -> VpnCredentialSummary:
    return VpnCredentialSummary(
        id=record.id,
        protocol=record.protocol,
        credential_type=record.credential_type or "username_password",
        device_id=record.device_id,
        server_id=record.server_id,
        username=record.username,
        cert_serial=record.cert_serial,
        cert_fingerprint_sha256=record.cert_fingerprint_sha256,
        profile_expires_at=_utc_iso(record.profile_expires_at) if record.profile_expires_at else None,
        revoked_at=_utc_iso(record.revoked_at) if record.revoked_at else None,
        revoke_reason=record.revoke_reason,
        revision=int(record.revision or 1),
        last_provisioned_at=_utc_iso(record.last_provisioned_at) if record.last_provisioned_at else None,
        last_rotated_at=_utc_iso(record.last_rotated_at) if record.last_rotated_at else None,
    )


def _select_server_for_protocol(
    *,
    db: Session,
    user_tier: str,
    protocol: str,
    preferred_server_id: Optional[str],
    region_hint: Optional[str] = None,
) -> VPNServer:
    server: Optional[VPNServer] = None
    if preferred_server_id:
        server = VPNServerService.get_server_by_id(db, preferred_server_id)
        if not server:
            raise ApiException(
                status_code=404,
                code="server_not_found",
                message="Server not found",
            )
        if server.tier_restriction and user_tier == "free":
            raise ApiException(
                status_code=status.HTTP_403_FORBIDDEN,
                code="server_tier_restricted",
                message=f"This server requires a {server.tier_restriction} subscription",
                details={"tier_required": server.tier_restriction},
            )
        if not _server_supports_protocol(server, protocol):
            raise ApiException(
                status_code=409,
                code="protocol_not_supported_on_server",
                message="Requested protocol is not enabled on the selected server.",
                details={"protocol": protocol, "server_id": server.server_id},
            )
        return server

    candidates = VPNServerService.get_active_servers(db, user_tier, protocol=protocol)
    if not candidates:
        raise ApiException(
            status_code=409,
            code="protocol_temporarily_unavailable",
            message="Requested protocol is currently unavailable on active servers.",
            details={"protocol": protocol},
        )

    latency_optimizer = get_latency_optimizer()
    scored = latency_optimizer.rank_servers(
        candidates,
        user_region_hint=region_hint,
    )
    score_map = {item.server_id: item.score for item in scored}
    candidates.sort(
        key=lambda s: (
            1 if s.health_status == "healthy" else 0,
            score_map.get(s.server_id, float("-inf")),
        ),
        reverse=True,
    )
    return candidates[0]


def _resolve_or_create_peer(
    *,
    db: Session,
    current_user: User,
    peer_manager,
    device_id: Optional[int],
    device_name: Optional[str],
    device_type: Optional[str],
) -> WireGuardPeer:
    peer: Optional[WireGuardPeer] = None
    if device_id:
        peer = db.query(WireGuardPeer).filter(
            WireGuardPeer.id == device_id,
            WireGuardPeer.user_id == current_user.id,
            WireGuardPeer.is_revoked == False,
        ).first()
        if not peer:
            raise ApiException(
                status_code=404,
                code="device_not_found",
                message="Device not found or revoked",
            )
        return peer

    resolved_name = (device_name or "This device").strip()[:64]
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.device_name == resolved_name,
        WireGuardPeer.is_revoked == False,
    ).first()
    if peer:
        return peer

    from services.subscription_access import get_effective_device_limit
    limit = get_effective_device_limit(db, current_user)
    active_count = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == current_user.id,
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.is_active == True,
    ).count()
    if active_count >= limit:
        raise ApiException(
            status_code=status.HTTP_403_FORBIDDEN,
            code="device_limit_reached",
            message=f"Device limit reached ({limit}). Upgrade your plan or revoke an existing device.",
            details={"limit": limit, "active_devices": active_count},
        )

    return peer_manager.create_peer(
        user=current_user,
        server=None,
        device_name=resolved_name,
        device_type=device_type,
    )


# =============================================================================
# Server Listing Endpoints
# =============================================================================

@router.get(
    "/protocols",
    response_model=VpnProtocolsResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def list_protocols(
    request: Request,
    device_type: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    user_tier = get_user_tier(current_user, db)
    normalized_device_type = (device_type or "").strip().lower() or None
    if normalized_device_type and normalized_device_type not in {"windows", "macos", "linux", "ios", "android"}:
        raise ApiException(
            status_code=400,
            code="invalid_device_type",
            message="Unsupported device_type. Supported: windows, macos, linux, ios, android.",
            details={"device_type": device_type},
        )

    enabled_protocols = _enabled_protocols()
    plan_allowed = _plan_allowed_protocols(user_tier)
    platform_supported = _platform_supported_protocols(normalized_device_type)

    servers = VPNServerService.get_active_servers(db, user_tier)
    server_flag_enabled: dict[str, bool] = {
        protocol: any(_server_protocol_support_map(server).get(protocol, False) for server in servers)
        for protocol in SUPPORTED_PROTOCOLS
    }
    server_material_ready: dict[str, bool] = {
        protocol: any(_server_protocol_material_ready(server, protocol) for server in servers)
        for protocol in SUPPORTED_PROTOCOLS
    }
    server_enabled: dict[str, bool] = {
        protocol: any(_server_protocol_effective_available(server, protocol) for server in servers)
        for protocol in SUPPORTED_PROTOCOLS
    }

    protocol_payload: list[VpnProtocolAvailability] = []
    for protocol in SUPPORTED_PROTOCOLS:
        enabled = (
            protocol in enabled_protocols
            and protocol in plan_allowed
            and protocol in platform_supported
            and server_enabled.get(protocol, False)
        )
        reason = None
        if protocol not in enabled_protocols:
            reason = "disabled_server_side"
        elif protocol not in plan_allowed:
            reason = "restricted_by_plan"
        elif protocol not in platform_supported:
            reason = "not_supported_on_platform"
        elif not server_flag_enabled.get(protocol, False):
            reason = "no_active_server_support"
        elif not server_material_ready.get(protocol, False):
            reason = "server_material_incomplete"
        elif not server_enabled.get(protocol, False):
            reason = "protocol_healthcheck_fail"

        transports = ["udp", "tcp"] if protocol == "openvpn" else None
        protocol_payload.append(
            VpnProtocolAvailability(
                protocol=protocol,
                enabled=enabled,
                server_enabled=server_enabled.get(protocol, False),
                plan_enabled=protocol in plan_allowed and protocol in enabled_protocols,
                platform_supported=protocol in platform_supported,
                transports=transports,
                requirements=_protocol_requirements(protocol),
                reason=reason,
            )
        )

    _log_vpn_catalog_debug(
        request=request,
        endpoint="/api/vpn/protocols",
        user_tier=user_tier,
        device_type=normalized_device_type,
        servers=servers,
        protocol_payload=protocol_payload,
    )

    return VpnProtocolsResponse(
        user_tier=user_tier,
        device_type=normalized_device_type,
        protocols=protocol_payload,
    )


@router.get(
    "/protocol-capabilities",
    response_model=ProtocolCapabilityStatus,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def protocol_capabilities(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Lightweight protocol capability view for frontend/ops diagnostics.

    This reports effective backend capability (policy + active server support +
    required server-side config material), not local client runtime support.
    """
    user_tier = get_user_tier(current_user, db)
    enabled_protocols = _enabled_protocols()
    plan_allowed = _plan_allowed_protocols(user_tier)
    active_servers = VPNServerService.get_active_servers(db, user_tier)

    supported_counts = {
        protocol: sum(1 for server in active_servers if _server_protocol_effective_available(server, protocol))
        for protocol in SUPPORTED_PROTOCOLS
    }

    def _effective(protocol: str) -> bool:
        return (
            protocol in enabled_protocols
            and protocol in plan_allowed
            and supported_counts.get(protocol, 0) > 0
        )

    return ProtocolCapabilityStatus(
        wireguard=_effective("wireguard"),
        openvpn=_effective("openvpn"),
        ikev2=_effective("ikev2"),
        server_counts=supported_counts,
        checked_at=_utc_iso(datetime.utcnow()),
    )


@router.get(
    "/regions",
    response_model=RegionRegistryResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def list_regions(
    request: Request,
    region: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Canonical backend region registry derived from active vpn_servers rows.

    One row == one active VPN node/region option shown in the client.
    """
    if region:
        try:
            region = sanitize_region(region)
        except ValueError as exc:
            raise ApiException(status_code=400, code="invalid_region", message=str(exc))

    user_tier = get_user_tier(current_user, db)
    # Fetch all active servers regardless of tier so premium servers are shown
    # in the client with a lock badge (instead of being hidden entirely).
    # Provisioning endpoints still enforce tier gating when a connection is made.
    servers_accessible = VPNServerService.get_active_servers(db, user_tier)
    # Also fetch premium-restricted servers so free users see them as locked.
    servers_all = VPNServerService.get_active_servers(db, "premium")
    accessible_ids = {str(s.server_id) for s in servers_accessible}
    # Merge: accessible servers + premium-only servers (those not in accessible)
    premium_only = [s for s in servers_all if str(s.server_id) not in accessible_ids]
    servers = servers_accessible + premium_only

    if region:
        servers = [s for s in servers if (_normalized_region_label(s)).lower() == region.lower()]

    latency_optimizer = get_latency_optimizer()
    baselines = latency_optimizer.collect_baselines()
    region_hint = region or request.headers.get("X-Geo-Region") or "barbados"

    recommended_id = None
    best_score = float("-inf")
    for server in servers_accessible:  # Only recommend servers the user can access
        if str(getattr(server, "health_status", "") or "").lower() not in {"healthy", "degraded", "unknown"}:
            continue
        score = latency_optimizer.score_server(
            server,
            baselines=baselines,
            user_region_hint=region_hint,
        )
        # Barbados-specific deterministic preference applied as a tiebreaker/boost.
        priority = _barbados_latency_priority(server)
        adjusted = score - (priority * 0.1)
        if adjusted > best_score:
            best_score = adjusted
            recommended_id = str(server.server_id)

    entries = [_region_registry_entry(server) for server in servers]
    entries.sort(
        key=lambda item: (
            int(item.latency_priority),
            0 if item.health_status == "healthy" else 1 if item.health_status == "degraded" else 2,
            item.display_name.lower(),
            item.id.lower(),
        )
    )

    return RegionRegistryResponse(
        regions=entries,
        total=len(entries),
        recommended_id=recommended_id,
    )


@router.get(
    "/servers",
    response_model=ServerListResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def list_servers(
    request: Request,
    region: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List available VPN servers.

    Filters servers based on user's subscription tier and optionally by region.
    Returns servers sorted by performance score and latency.
    """
    if region:
        try:
            region = sanitize_region(region)
        except ValueError as exc:
            raise ApiException(status_code=400, code="invalid_region", message=str(exc))

    user_tier = get_user_tier(current_user, db)

    # Get active servers for this user's tier
    servers = VPNServerService.get_active_servers(db, user_tier)

    # Filter by region if specified
    if region:
        servers = [s for s in servers if _normalized_region_label(s).lower() == region.lower()]

    # Convert to response format
    server_list = []
    recommended_id = None
    best_score = float("-inf")
    latency_optimizer = get_latency_optimizer()
    baselines = latency_optimizer.collect_baselines()
    region_hint = region or request.headers.get("X-Geo-Region")

    for server in servers:
        # Calculate load percentage
        load_percent = (server.current_connections / server.max_connections * 100) if server.max_connections > 0 else 0
        location, country, country_code, city = _server_display_location_fields(server)

        server_info = ServerInfo(
            server_id=server.server_id,
            location=location,
            country=country,
            country_code=country_code,
            city=city,
            region=_normalized_region_label(server),
            latency_ms=server.latency_ms,
            load_percent=round(load_percent, 1),
            status=server.status,
            health_status=server.health_status,
            supported_protocols=_server_supported_protocols(server),
            public_ip=server.public_ip,
            latency_priority=_barbados_latency_priority(server),
        )
        server_list.append(server_info)

        # Track best server for recommendation using geo RTT weighting.
        score = latency_optimizer.score_server(
            server,
            baselines=baselines,
            user_region_hint=region_hint,
        )
        if server.health_status in {"healthy", "degraded"} and score > best_score:
            best_score = score
            recommended_id = server.server_id

    _log_vpn_catalog_debug(
        request=request,
        endpoint="/api/vpn/servers",
        user_tier=user_tier,
        device_type=None,
        servers=servers,
    )

    return ServerListResponse(
        servers=sorted(
            server_list,
            key=lambda item: (
                int(item.latency_priority or 999),
                0 if item.health_status == "healthy" else 1 if item.health_status == "degraded" else 2,
                float(item.latency_ms or 9999.0),
                item.location.lower(),
            ),
        ),
        total=len(server_list),
        recommended_server_id=recommended_id,
    )


@router.get(
    "/recommended-server",
    response_model=RecommendedServerResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def recommended_server(
    request: Request,
    region: Optional[str] = None,
    include_candidates: bool = False,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Recommend the best server for Barbados/EU corridors using:
    - geo_latency_probe baselines (if present)
    - rolling RTT history from recent health probes
    - live load/health/failure signals
    """
    region_hint = region
    if region_hint:
        try:
            region_hint = sanitize_region(region_hint)
        except ValueError as exc:
            raise ApiException(status_code=400, code="invalid_region", message=str(exc))
    else:
        region_hint = request.headers.get("X-Geo-Region")

    user_tier = get_user_tier(current_user, db)
    from services.geo_recommendation import recommend_server as geo_reco

    payload = geo_reco(
        db,
        user_tier=user_tier,
        user_region_hint=region_hint,
        include_candidates=include_candidates,
    )
    return payload


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
    location, country, country_code, city = _server_display_location_fields(server)

    return ServerInfo(
        server_id=server.server_id,
        location=location,
        country=country,
        country_code=country_code,
        city=city,
        region=_normalized_region_label(server),
        latency_ms=server.latency_ms,
        load_percent=round(load_percent, 1),
        status=server.status,
        health_status=server.health_status,
        supported_protocols=_server_supported_protocols(server),
        public_ip=server.public_ip,
        latency_priority=_barbados_latency_priority(server),
    )


@router.get(
    "/metrics/vpn",
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("30/minute")
async def vpn_metrics(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Export VPN fleet and tunnel performance metrics for operators.
    """
    runtime = get_runtime_metrics().snapshot()
    peer_manager = get_peer_manager(db)
    pool = peer_manager.get_ip_pool_stats()

    peer_total = db.query(WireGuardPeer).filter(WireGuardPeer.is_revoked == False).count()
    healthy = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.health_status == "healthy",
    ).count()
    degraded = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.health_status == "degraded",
    ).count()
    unstable = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.health_status == "unstable",
    ).count()
    stale_seconds = int(os.getenv("WG_HANDSHAKE_UNSTABLE_SECONDS", "300"))
    stale_cutoff = datetime.utcnow() - timedelta(seconds=stale_seconds)
    stale_handshakes = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        (
            (WireGuardPeer.last_handshake_at.is_(None))
            | (WireGuardPeer.last_handshake_at < stale_cutoff)
        ),
    ).count()

    avg_handshake = (
        db.query(func.avg(WireGuardPeer.last_handshake_latency_ms))
        .filter(WireGuardPeer.is_revoked == False)
        .scalar()
    ) or 0.0

    overall_health = "healthy"
    if peer_total > 0 and unstable / peer_total >= 0.25:
        overall_health = "unstable"
    elif degraded > 0 or unstable > 0:
        overall_health = "degraded"

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "health_classification": overall_health,
        "peers": {
            "total": peer_total,
            "healthy": healthy,
            "degraded": degraded,
            "unstable": unstable,
            "stale_handshakes": stale_handshakes,
            "avg_handshake_latency_ms": round(float(avg_handshake), 2),
        },
        "ip_pool": pool,
        "runtime": runtime,
    }


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
    started = time.monotonic()
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
    dns_servers = _profile_dns_servers()
    mtu, keepalive, nat_detected, mtu_probe_ms = _resolve_wireguard_tuning(
        request,
        server,
        device_type=None,
    )

    interface_lines = [
        "[Interface]",
        f"PrivateKey = {private_key}",
        f"Address = {client_ip}",
        f"DNS = {','.join(dns_servers)}",
    ]
    if mtu is not None:
        interface_lines.append(f"MTU = {mtu}")

    server_public_key, server_endpoint, server_allowed_ips = _safe_server_peer_values(server)
    peer_lines = [
        "",
        "[Peer]",
        f"PublicKey = {server_public_key}",
        f"Endpoint = {server_endpoint}",
        f"AllowedIPs = {server_allowed_ips}",
    ]
    if keepalive > 0:
        peer_lines.append(f"PersistentKeepalive = {keepalive}")

    config_content = "\n".join(interface_lines + peer_lines) + "\n"

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
        register_start = time.monotonic()
        success, message = await register_peer_on_server(
            server=server,
            public_key=public_key,
            allowed_ips=client_ip,
        )
        registration_latency_ms = (time.monotonic() - register_start) * 1000.0
        get_runtime_metrics().record_handshake_latency(registration_latency_ms)
        peer.last_handshake_latency_ms = round(registration_latency_ms, 2)
        db.add(peer)
        db.commit()
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

    _log_vpn_event(
        "vpn_profile_issued",
        user_id=current_user.id,
        server_id=server.server_id,
        device_id=peer.id,
        nat_detected=nat_detected,
        mtu=mtu,
        keepalive=keepalive,
        mtu_probe_ms=mtu_probe_ms,
        auto_registered=peer_registered,
    )

    response_payload = AllocateConfigResponse(
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
    elapsed_ms = (time.monotonic() - started) * 1000.0
    get_runtime_metrics().record_profile_issue(latency_ms=elapsed_ms, success=True)
    return response_payload


@router.post(
    "/profile",
    response_model=VpnProfileResponse,
    responses=VPN_ERROR_RESPONSES,
)
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
    - Registers/looks up a per-device identity (WireGuard keys encrypted at rest)
    - Selects an allowed server by tier (or uses device/server preference)
    - Issues a protocol-specific profile payload (WireGuard/OpenVPN/IKEv2)
    """
    started = time.monotonic()
    await require_active_subscription(db, current_user)

    requested_protocol = normalize_vpn_protocol(payload.protocol)
    user_tier = get_user_tier(current_user, db)
    enabled_protocols = _enabled_protocols()
    plan_allowed_protocols = _plan_allowed_protocols(user_tier)
    requested_explicit = requested_protocol != "auto"

    if requested_explicit and requested_protocol not in enabled_protocols:
        raise ApiException(
            status_code=403,
            code="protocol_disabled_server_side",
            message="Requested protocol is disabled by server policy.",
            details={"protocol": requested_protocol},
        )
    if requested_explicit and requested_protocol not in plan_allowed_protocols:
        raise ApiException(
            status_code=403,
            code="protocol_plan_restricted",
            message="Requested protocol is not enabled for this account plan.",
            details={"protocol": requested_protocol, "tier": user_tier},
        )

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
            raise ApiException(
                status_code=404,
                code="device_not_found",
                message="Device not found or revoked",
            )
    else:
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
                raise ApiException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    code="device_limit_reached",
                    message=f"Device limit reached ({limit}). Upgrade your plan or revoke an existing device.",
                    details={"limit": limit, "active_devices": active_count},
                )

            device_type = (payload.device_type or "").lower().strip() or None
            peer = peer_manager.create_peer(
                user=current_user,
                server=None,
                device_name=device_name,
                device_type=device_type,
            )

    device_type = (payload.device_type or peer.device_type or "").lower().strip() or None
    platform_supported_protocols = _platform_supported_protocols(device_type)

    if requested_explicit and requested_protocol not in platform_supported_protocols:
        raise ApiException(
            status_code=400,
            code="protocol_not_supported_on_platform",
            message="Requested protocol is not supported on this platform.",
            details={"protocol": requested_protocol, "device_type": device_type},
        )

    allowed_protocols = enabled_protocols.intersection(plan_allowed_protocols)
    if requested_protocol == "auto":
        allowed_protocols = allowed_protocols.intersection(platform_supported_protocols)
        if not allowed_protocols:
            raise ApiException(
                status_code=409,
                code="no_protocol_available",
                message="No VPN protocol is available for this account/platform combination.",
                details={"tier": user_tier, "device_type": device_type},
            )

    # Resolve server
    server: Optional[VPNServer] = None
    if payload.server_id:
        server = VPNServerService.get_server_by_id(db, payload.server_id)
        if not server:
            raise ApiException(
                status_code=404,
                code="server_not_found",
                message="Server not found",
            )
        if server.tier_restriction and user_tier == "free":
            raise ApiException(
                status_code=status.HTTP_403_FORBIDDEN,
                code="server_tier_restricted",
                message=f"This server requires a {server.tier_restriction} subscription",
                details={"tier_required": server.tier_restriction},
            )
        if requested_explicit and not _server_supports_protocol(server, requested_protocol):
            raise ApiException(
                status_code=409,
                code="protocol_not_supported_on_server",
                message="Requested protocol is not enabled on the selected server.",
                details={"protocol": requested_protocol, "server_id": server.server_id},
            )

    if server is None and peer.server_id:
        server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
        if server and server.tier_restriction and user_tier == "free":
            server = None
        if server and requested_explicit and not _server_supports_protocol(server, requested_protocol):
            server = None

    candidates = VPNServerService.get_active_servers(
        db,
        user_tier,
        protocol=requested_protocol if requested_explicit else None,
    )
    if requested_protocol == "auto":
        candidates = [
            item
            for item in candidates
            if any(
                proto in allowed_protocols
                for proto in _server_effective_supported_protocols(item)
            )
        ]

    if not candidates:
        if requested_explicit:
            unavailable_scope = "health" if request.headers.get("X-Geo-Region") else "default"
            raise ApiException(
                status_code=409,
                code=_protocol_server_unavailable_code(
                    requested_protocol,
                    scope=unavailable_scope,
                ),
                message="Requested protocol is currently unavailable on active servers.",
                details={"protocol": requested_protocol},
            )
        raise ApiException(
            status_code=503,
            code="no_servers_available",
            message="No VPN servers available. Please try again later.",
        )

    if server is None or all(server.id != item.id for item in candidates):
        latency_optimizer = get_latency_optimizer()
        scored = latency_optimizer.rank_servers(
            candidates,
            user_region_hint=request.headers.get("X-Geo-Region"),
        )
        score_map = {item.server_id: item.score for item in scored}
        candidates.sort(
            key=lambda s: (
                1 if s.health_status == "healthy" else 0,
                score_map.get(s.server_id, float("-inf")),
            ),
            reverse=True,
        )
        server = candidates[0]

    assert server is not None
    effective_protocol = choose_effective_protocol(
        server=server,
        requested_protocol=requested_protocol,
        device_type=device_type,
        allowed_protocols=allowed_protocols,
    )

    # Optional key rotation
    if payload.force_rotate_keys and effective_protocol == "wireguard":
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
        # Best-effort remove old WireGuard peer from old server.
        if peer.server_id and effective_protocol == "wireguard":
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

    peer_registered = False
    registration_status: Optional[str] = None
    wireguard_config: Optional[str] = None
    profile_payload: Optional[VpnProtocolProfilePayload] = None
    dns_servers = _profile_dns_servers()

    if effective_protocol == "wireguard":
        # Register WireGuard peer on the data-plane server (best effort).
        if AUTO_REGISTER_PEERS:
            register_start = time.monotonic()
            success, message = await register_peer_on_server(server, peer.public_key, peer.ipv4_address)
            registration_latency_ms = (time.monotonic() - register_start) * 1000.0
            get_runtime_metrics().record_handshake_latency(registration_latency_ms)
            peer.last_handshake_latency_ms = round(registration_latency_ms, 2)
            db.add(peer)
            db.commit()
            peer_registered = success
            registration_status = message

        wireguard_config = _build_wireguard_profile_config(
            request,
            peer,
            server,
            device_type=device_type,
        )
        profile_payload = VpnWireGuardProfilePayload(wireguard_config=wireguard_config)
    else:
        creds_service = VpnCredentialService(db)
        if not _server_protocol_material_ready(server, effective_protocol):
            raise ApiException(
                status_code=409,
                code=_protocol_server_unavailable_code(effective_protocol, scope="config"),
                message=f"{effective_protocol.upper()} is enabled but missing required server configuration.",
                details={"protocol": effective_protocol, "server_id": server.server_id},
            )
        if not _server_health_allows_protocol(server):
            raise ApiException(
                status_code=409,
                code=_protocol_server_unavailable_code(effective_protocol, scope="health"),
                message=f"{effective_protocol.upper()} is temporarily unavailable because the selected server healthcheck is failing.",
                details={
                    "protocol": effective_protocol,
                    "server_id": server.server_id,
                    "health_status": str(getattr(server, 'health_status', '') or 'unknown'),
                },
            )
        if effective_protocol == "openvpn":
            openvpn_mode = _openvpn_auth_mode()
            if openvpn_mode == "mtls":
                try:
                    issued = await creds_service.issue_openvpn_certificate_profile(
                        user_id=current_user.id,
                        device_id=peer.id,
                        server=server,
                    )
                except Exception as exc:
                    raise ApiException(
                        status_code=502,
                        code="openvpn_server_misconfigured",
                        message="OpenVPN backend provisioning is unavailable or misconfigured for the selected server.",
                        details={"protocol": "openvpn", "reason": str(exc)},
                    )
                profile_payload = VpnOpenVpnProfilePayload(
                    ovpn_config=issued.ovpn_config,
                    auth_method="mtls",
                    username=issued.common_name,
                    cert_serial=issued.cert_serial,
                    cert_fingerprint_sha256=issued.cert_fingerprint_sha256,
                )
                peer_registered = issued.provisioned_on_server
                registration_status = issued.status_message
            else:
                creds = creds_service.get_or_create(
                    user_id=current_user.id,
                    device_id=peer.id,
                    server_id=server.id,
                    protocol=effective_protocol,
                )
                profile_payload = _build_openvpn_profile(
                    server,
                    username=creds.username,
                    password=creds.password,
                    device_type=device_type,
                    dns_servers=dns_servers,
                )
                provisioned, message = await provision_protocol_credentials_on_server(
                    server=server,
                    protocol=effective_protocol,
                    username=creds.username,
                    password=creds.password,
                )
                if not provisioned and str(message or "").strip() not in {"", "Auto provisioning disabled", "not_applicable"}:
                    raise ApiException(
                        status_code=502,
                        code="openvpn_healthcheck_fail",
                        message="OpenVPN server-side user provisioning failed on the selected server.",
                        details={"protocol": "openvpn", "server_id": server.server_id, "reason": message},
                    )
                peer_registered = provisioned
                registration_status = message
        elif effective_protocol == "ikev2":
            ikev2_mode = _ikev2_auth_mode()
            if ikev2_mode == "eap-tls":
                try:
                    issued = await creds_service.issue_ikev2_certificate_profile(
                        user_id=current_user.id,
                        device_id=peer.id,
                        server=server,
                    )
                except Exception as exc:
                    raise ApiException(
                        status_code=502,
                        code="ikev2_server_misconfigured",
                        message="IKEv2 backend provisioning is unavailable or misconfigured for the selected server.",
                        details={"protocol": "ikev2", "reason": str(exc)},
                    )
                profile_payload = VpnIkev2ProfilePayload(
                    auth_method="eap-tls",
                    server=issued.server,
                    remote_id=issued.remote_id,
                    ca_cert_pem=issued.ca_cert_pem,
                    client_pkcs12_base64=issued.client_pkcs12_base64,
                    client_pkcs12_password=issued.client_pkcs12_password,
                    cert_serial=issued.cert_serial,
                    cert_fingerprint_sha256=issued.cert_fingerprint_sha256,
                    username=issued.common_name,
                )
                peer_registered = issued.provisioned_on_server
                registration_status = issued.status_message
            else:
                creds = creds_service.get_or_create(
                    user_id=current_user.id,
                    device_id=peer.id,
                    server_id=server.id,
                    protocol=effective_protocol,
                )
                profile_payload = _build_ikev2_profile(
                    server,
                    username=creds.username,
                    password=creds.password,
                )
                provisioned, message = await provision_protocol_credentials_on_server(
                    server=server,
                    protocol=effective_protocol,
                    username=creds.username,
                    password=creds.password,
                )
                if not provisioned and str(message or "").strip() not in {"", "Auto provisioning disabled", "not_applicable"}:
                    raise ApiException(
                        status_code=502,
                        code="ikev2_healthcheck_fail",
                        message="IKEv2 server-side user provisioning failed on the selected server.",
                        details={"protocol": "ikev2", "server_id": server.server_id, "reason": message},
                    )
                peer_registered = provisioned
                registration_status = message

        if profile_payload is None:
            raise ApiException(
                status_code=500,
                code="unsupported_protocol",
                message="Unsupported protocol for this profile request.",
                details={"protocol": effective_protocol},
            )

    if effective_protocol == "ikev2":
        # IKEv2 profile payload does not enforce DNS resolvers cross-platform.
        dns_servers = []

    dns_enforcement = "config" if dns_servers else "none"
    dns_mode = "tunnel" if dns_servers else "platform_default"
    ad_malware_blocking = "on" if dns_servers else "off"

    ks_mode = "disabled"
    ks_enforcement = "none"
    ks_notes = (
        "SecureWave does not enforce a kill switch for this protocol/platform. "
        "Use OS always-on VPN controls where available."
    )
    if effective_protocol == "wireguard" and device_type == "linux":
        ks_mode = "enabled"
        ks_enforcement = "wg-quick hooks"
        ks_notes = "Linux WireGuard profiles include wg-quick iptables hooks for kill-switch behavior."

    kill_switch = VpnProfileKillSwitch(
        mode=ks_mode,
        enforcement=ks_enforcement,
        notes=ks_notes,
    )

    ttl_seconds = int(os.getenv("SECUREWAVE_PROFILE_TTL_SECONDS", "3600"))
    if ttl_seconds < 60:
        ttl_seconds = 60
    issued_at = datetime.now(timezone.utc)
    expires_at = issued_at + timedelta(seconds=ttl_seconds)

    response_payload = VpnProfileResponse(
        device_id=peer.id,
        device_name=peer.device_name,
        device_type=peer.device_type,
        protocol=effective_protocol,
        server_id=server.server_id,
        server_location=f"{server.city}, {server.country}",
        key_version=peer.key_version or 1,
        issued_at=_utc_iso(issued_at),
        expires_at=_utc_iso(expires_at),
        wireguard_config=wireguard_config,
        profile=profile_payload,
        dns=VpnProfileDns(
            mode=dns_mode,
            servers=dns_servers,
            ad_malware_blocking=ad_malware_blocking,
            enforcement=dns_enforcement,
        ),
        kill_switch=kill_switch,
        peer_registered=peer_registered,
        registration_status=registration_status,
    )
    _log_vpn_event(
        "vpn_profile_issued",
        user_id=current_user.id,
        server_id=server.server_id,
        device_id=peer.id,
        key_version=peer.key_version,
        protocol=effective_protocol,
        peer_registered=peer_registered,
    )
    elapsed_ms = (time.monotonic() - started) * 1000.0
    get_runtime_metrics().record_profile_issue(latency_ms=elapsed_ms, success=True)
    return response_payload


@router.post(
    "/credentials/provision",
    response_model=VpnCredentialProvisionResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("20/minute")
async def provision_vpn_credential(
    request: Request,
    payload: VpnCredentialProvisionRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    await require_active_subscription(db, current_user)
    protocol = normalize_vpn_protocol(payload.protocol)
    if protocol not in {"openvpn", "ikev2"}:
        raise ApiException(
            status_code=400,
            code="unsupported_protocol",
            message="Credential provisioning supports openvpn and ikev2 only.",
            details={"protocol": payload.protocol},
        )

    user_tier = get_user_tier(current_user, db)
    enabled = _enabled_protocols()
    allowed_by_plan = _plan_allowed_protocols(user_tier)
    if protocol not in enabled:
        raise ApiException(
            status_code=403,
            code="protocol_disabled_server_side",
            message="Requested protocol is disabled by server policy.",
            details={"protocol": protocol},
        )
    if protocol not in allowed_by_plan:
        raise ApiException(
            status_code=403,
            code="protocol_plan_restricted",
            message="Requested protocol is not enabled for this account plan.",
            details={"protocol": protocol, "tier": user_tier},
        )

    peer_manager = get_peer_manager(db)
    peer = _resolve_or_create_peer(
        db=db,
        current_user=current_user,
        peer_manager=peer_manager,
        device_id=payload.device_id,
        device_name=payload.device_name,
        device_type=(payload.device_type or "").strip().lower() or None,
    )
    device_type = (payload.device_type or peer.device_type or "").strip().lower() or None
    if protocol not in _platform_supported_protocols(device_type):
        raise ApiException(
            status_code=400,
            code="protocol_not_supported_on_platform",
            message="Requested protocol is not supported on this platform.",
            details={"protocol": protocol, "device_type": device_type},
        )

    server = _select_server_for_protocol(
        db=db,
        user_tier=user_tier,
        protocol=protocol,
        preferred_server_id=payload.server_id,
        region_hint=request.headers.get("X-Geo-Region"),
    )
    if peer.server_id != server.id:
        peer.server_id = server.id
        peer.is_active = True
        db.add(peer)
        db.commit()
        db.refresh(peer)

    creds_service = VpnCredentialService(db)

    if payload.rotate_if_exists:
        existing_active = [
            item
            for item in creds_service.list_user_credentials(
                user_id=current_user.id,
                device_id=peer.id,
                protocol=protocol,
            )
            if item.server_id == server.id and item.revoked_at is None
        ]
        for item in existing_active:
            ok, message = await creds_service.revoke_certificate(
                credential=item,
                server=server,
                reason="rotated_before_reissue",
            )
            if not ok:
                raise ApiException(
                    status_code=409,
                    code="credential_revoke_failed",
                    message="Failed to rotate existing credential before reissue.",
                    details={"credential_id": item.id, "reason": message},
                )

    issued_profile: Optional[Dict[str, Any]] = None
    status_message = "provisioned"
    if protocol == "openvpn":
        if _openvpn_auth_mode() == "mtls":
            try:
                issued = await creds_service.issue_openvpn_certificate_profile(
                    user_id=current_user.id,
                    device_id=peer.id,
                    server=server,
                )
            except Exception as exc:
                raise ApiException(
                    status_code=502,
                    code="credential_provision_failed",
                    message="Failed to provision OpenVPN certificate profile.",
                    details={"protocol": "openvpn", "reason": str(exc)},
                )
            issued_profile = VpnOpenVpnProfilePayload(
                ovpn_config=issued.ovpn_config,
                auth_method="mtls",
                username=issued.common_name,
                cert_serial=issued.cert_serial,
                cert_fingerprint_sha256=issued.cert_fingerprint_sha256,
            ).model_dump()
            status_message = issued.status_message
        else:
            creds = creds_service.get_or_create(
                user_id=current_user.id,
                device_id=peer.id,
                server_id=server.id,
                protocol="openvpn",
            )
            issued_profile = _build_openvpn_profile(
                server,
                username=creds.username,
                password=creds.password,
                device_type=device_type,
                dns_servers=_profile_dns_servers(),
            ).model_dump()
            await provision_protocol_credentials_on_server(
                server=server,
                protocol="openvpn",
                username=creds.username,
                password=creds.password,
            )
            status_message = "credential_provisioned"
    else:
        if _ikev2_auth_mode() == "eap-tls":
            try:
                issued = await creds_service.issue_ikev2_certificate_profile(
                    user_id=current_user.id,
                    device_id=peer.id,
                    server=server,
                )
            except Exception as exc:
                raise ApiException(
                    status_code=502,
                    code="credential_provision_failed",
                    message="Failed to provision IKEv2 certificate profile.",
                    details={"protocol": "ikev2", "reason": str(exc)},
                )
            issued_profile = VpnIkev2ProfilePayload(
                auth_method="eap-tls",
                server=issued.server,
                remote_id=issued.remote_id,
                ca_cert_pem=issued.ca_cert_pem,
                client_pkcs12_base64=issued.client_pkcs12_base64,
                client_pkcs12_password=issued.client_pkcs12_password,
                cert_serial=issued.cert_serial,
                cert_fingerprint_sha256=issued.cert_fingerprint_sha256,
                username=issued.common_name,
            ).model_dump()
            status_message = issued.status_message
        else:
            creds = creds_service.get_or_create(
                user_id=current_user.id,
                device_id=peer.id,
                server_id=server.id,
                protocol="ikev2",
            )
            issued_profile = _build_ikev2_profile(
                server,
                username=creds.username,
                password=creds.password,
            ).model_dump()
            await provision_protocol_credentials_on_server(
                server=server,
                protocol="ikev2",
                username=creds.username,
                password=creds.password,
            )
            status_message = "credential_provisioned"

    record = (
        db.query(VPNCredential)
        .filter(
            VPNCredential.user_id == current_user.id,
            VPNCredential.device_id == peer.id,
            VPNCredential.server_id == server.id,
            VPNCredential.protocol == protocol,
        )
        .order_by(VPNCredential.revision.desc(), VPNCredential.updated_at.desc())
        .first()
    )
    if not record:
        raise ApiException(
            status_code=500,
            code="credential_persistence_failed",
            message="Provisioned credential metadata could not be loaded.",
            details={"protocol": protocol, "server_id": server.server_id},
        )

    return VpnCredentialProvisionResponse(
        status=status_message,
        credential=_credential_summary(record),
        profile=issued_profile,
    )


@router.get(
    "/credentials",
    response_model=VpnCredentialListResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("30/minute")
async def list_vpn_credentials(
    request: Request,
    protocol: Optional[str] = None,
    device_id: Optional[int] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    normalized_protocol: Optional[str] = None
    if protocol:
        normalized_protocol = normalize_vpn_protocol(protocol)
        if normalized_protocol == "auto":
            raise ApiException(
                status_code=400,
                code="unsupported_protocol",
                message="Protocol filter must be openvpn or ikev2.",
                details={"protocol": protocol},
            )

    service = VpnCredentialService(db)
    rows = service.list_user_credentials(
        user_id=current_user.id,
        device_id=device_id,
        protocol=normalized_protocol,
    )
    summaries = [_credential_summary(item) for item in rows]
    return VpnCredentialListResponse(credentials=summaries, total=len(summaries))


@router.post(
    "/credentials/{credential_id}/revoke",
    response_model=VpnCredentialLifecycleResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("20/minute")
async def revoke_vpn_credential(
    request: Request,
    credential_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = VpnCredentialService(db)
    credential = service.get_user_credential(user_id=current_user.id, credential_id=credential_id)
    if not credential:
        raise ApiException(
            status_code=404,
            code="credential_not_found",
            message="Credential not found",
            details={"credential_id": credential_id},
        )
    server = db.query(VPNServer).filter(VPNServer.id == credential.server_id).first()
    if not server:
        raise ApiException(
            status_code=404,
            code="server_not_found",
            message="Server for credential not found",
            details={"credential_id": credential_id},
        )

    ok, message = await service.revoke_certificate(
        credential=credential,
        server=server,
        reason="manual_revoke",
    )
    if not ok:
        raise ApiException(
            status_code=409,
            code="credential_revoke_failed",
            message="Credential revoke failed.",
            details={"credential_id": credential_id, "reason": message},
        )
    return VpnCredentialLifecycleResponse(
        status=message,
        credential=_credential_summary(credential),
    )


@router.post(
    "/credentials/{credential_id}/rotate",
    response_model=VpnCredentialProvisionResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("20/minute")
async def rotate_vpn_credential(
    request: Request,
    credential_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    await require_active_subscription(db, current_user)
    service = VpnCredentialService(db)
    credential = service.get_user_credential(user_id=current_user.id, credential_id=credential_id)
    if not credential:
        raise ApiException(
            status_code=404,
            code="credential_not_found",
            message="Credential not found",
            details={"credential_id": credential_id},
        )
    if credential.protocol not in {"openvpn", "ikev2"}:
        raise ApiException(
            status_code=400,
            code="unsupported_protocol",
            message="Credential rotation supports openvpn and ikev2 only.",
            details={"credential_id": credential_id, "protocol": credential.protocol},
        )

    server = db.query(VPNServer).filter(VPNServer.id == credential.server_id).first()
    if not server:
        raise ApiException(
            status_code=404,
            code="server_not_found",
            message="Server for credential not found",
            details={"credential_id": credential_id},
        )

    user_tier = get_user_tier(current_user, db)
    enabled = _enabled_protocols()
    allowed_by_plan = _plan_allowed_protocols(user_tier)
    if credential.protocol not in enabled or credential.protocol not in allowed_by_plan:
        raise ApiException(
            status_code=403,
            code="protocol_plan_restricted",
            message="Credential protocol is not currently allowed for this account.",
            details={"protocol": credential.protocol, "tier": user_tier},
        )

    ok, message = await service.rotate_certificate(
        credential=credential,
        server=server,
    )
    if not ok:
        raise ApiException(
            status_code=409,
            code="credential_rotate_failed",
            message="Credential rotation failed.",
            details={"credential_id": credential_id, "reason": message},
        )

    issued_profile: Optional[Dict[str, Any]] = None
    if credential.protocol == "openvpn":
        if _openvpn_auth_mode() == "mtls":
            try:
                issued = await service.issue_openvpn_certificate_profile(
                    user_id=current_user.id,
                    device_id=credential.device_id,
                    server=server,
                )
            except Exception as exc:
                raise ApiException(
                    status_code=502,
                    code="credential_provision_failed",
                    message="Failed to provision rotated OpenVPN certificate.",
                    details={"credential_id": credential_id, "reason": str(exc)},
                )
            issued_profile = VpnOpenVpnProfilePayload(
                ovpn_config=issued.ovpn_config,
                auth_method="mtls",
                username=issued.common_name,
                cert_serial=issued.cert_serial,
                cert_fingerprint_sha256=issued.cert_fingerprint_sha256,
            ).model_dump()
        else:
            creds = service.get_or_create(
                user_id=current_user.id,
                device_id=credential.device_id,
                server_id=credential.server_id,
                protocol="openvpn",
            )
            issued_profile = _build_openvpn_profile(
                server,
                username=creds.username,
                password=creds.password,
                device_type=None,
                dns_servers=_profile_dns_servers(),
            ).model_dump()
            await provision_protocol_credentials_on_server(
                server=server,
                protocol="openvpn",
                username=creds.username,
                password=creds.password,
            )
    else:
        if _ikev2_auth_mode() == "eap-tls":
            try:
                issued = await service.issue_ikev2_certificate_profile(
                    user_id=current_user.id,
                    device_id=credential.device_id,
                    server=server,
                )
            except Exception as exc:
                raise ApiException(
                    status_code=502,
                    code="credential_provision_failed",
                    message="Failed to provision rotated IKEv2 certificate.",
                    details={"credential_id": credential_id, "reason": str(exc)},
                )
            issued_profile = VpnIkev2ProfilePayload(
                auth_method="eap-tls",
                server=issued.server,
                remote_id=issued.remote_id,
                ca_cert_pem=issued.ca_cert_pem,
                client_pkcs12_base64=issued.client_pkcs12_base64,
                client_pkcs12_password=issued.client_pkcs12_password,
                cert_serial=issued.cert_serial,
                cert_fingerprint_sha256=issued.cert_fingerprint_sha256,
                username=issued.common_name,
            ).model_dump()
        else:
            creds = service.get_or_create(
                user_id=current_user.id,
                device_id=credential.device_id,
                server_id=credential.server_id,
                protocol="ikev2",
            )
            issued_profile = _build_ikev2_profile(
                server,
                username=creds.username,
                password=creds.password,
            ).model_dump()
            await provision_protocol_credentials_on_server(
                server=server,
                protocol="ikev2",
                username=creds.username,
                password=creds.password,
            )

    record = (
        db.query(VPNCredential)
        .filter(
            VPNCredential.user_id == current_user.id,
            VPNCredential.id == credential.id,
        )
        .first()
    )
    assert record is not None
    return VpnCredentialProvisionResponse(
        status="rotated",
        credential=_credential_summary(record),
        profile=issued_profile,
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
    request: Request,
    payload: VPNConnectRequest = VPNConnectRequest(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Allocate a config (if needed) and mark a connection as active.

    Note: This does not establish a tunnel on the client device. The WireGuard
    client in the SecureWave app performs the actual connect/disconnect.
    """
    await require_active_subscription(db, current_user)
    wg_service = WireGuardService()
    user_tier = get_user_tier(current_user, db)
    requested_protocol = normalize_vpn_protocol(payload.protocol) if payload.protocol else "auto"

    server: Optional[VPNServer] = None
    if payload.server_id:
        server = VPNServerService.get_server_by_id(db, payload.server_id)
        if not server:
            raise HTTPException(status_code=404, detail="Server not found")
        if server.tier_restriction and user_tier == "free":
            raise HTTPException(status_code=403, detail="Server requires a paid subscription tier")
        if requested_protocol != "auto" and not _server_supports_protocol(server, requested_protocol):
            raise HTTPException(
                status_code=409,
                detail="Requested protocol is not enabled on the selected server.",
            )

    if server is None:
        server = VPNServerService.allocate_server_for_user(
            db, current_user, preferred_location=payload.region
        )
        if server and requested_protocol != "auto" and not _server_supports_protocol(server, requested_protocol):
            server = None

    if not server:
        servers = VPNServerService.get_active_servers(
            db,
            user_tier,
            protocol=requested_protocol if requested_protocol != "auto" else None,
        )
        if not servers:
            raise HTTPException(status_code=503, detail="No VPN servers available. Please try again later.")
        latency_optimizer = get_latency_optimizer()
        region_hint = payload.region or request.headers.get("X-Geo-Region")
        scored = latency_optimizer.rank_servers(servers, user_region_hint=region_hint)
        score_map = {item.server_id: item.score for item in scored}
        servers.sort(
            key=lambda s: (
                0 if str(s.health_status or "").lower() == "healthy" else 1,
                _barbados_latency_priority(s),
                -score_map.get(s.server_id, float("-inf")),
                -(float(s.performance_score or 0.0)),
            )
        )
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
        mtu, keepalive, _, _ = _resolve_wireguard_tuning(request, server, device_type=None)

        interface_lines = [
            "[Interface]",
            f"PrivateKey = {wg_service.decrypt_private_key(current_user.wg_private_key_encrypted)}",
            f"Address = {client_ip}",
            f"DNS = {','.join(dns_servers)}",
        ]
        if mtu is not None:
            interface_lines.append(f"MTU = {mtu}")

        server_public_key, server_endpoint, server_allowed_ips = _safe_server_peer_values(server)
        peer_lines = [
            "",
            "[Peer]",
            f"PublicKey = {server_public_key}",
            f"Endpoint = {server_endpoint}",
            f"AllowedIPs = {server_allowed_ips}",
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

    connected_at = datetime.utcnow()
    active_connection = db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None)
    ).first()
    if active_connection and (
        active_connection.server_id != server.id or (active_connection.client_ip or "") != (client_ip or "")
    ):
        active_connection.disconnected_at = connected_at
        if active_connection.server:
            active_connection.server.current_connections = max(
                0,
                int(active_connection.server.current_connections or 0) - 1,
            )
            active_connection.server.updated_at = connected_at
            db.add(active_connection.server)
        db.add(active_connection)
        active_connection = None

    if not active_connection:
        active_connection = VPNConnection(
            user_id=current_user.id,
            server_id=server.id,
            client_ip=client_ip,
            connected_at=connected_at,
        )
        db.add(active_connection)
        server.current_connections = max(0, int(server.current_connections or 0)) + 1
        server.updated_at = connected_at
        db.add(server)

    db.add(current_user)
    db.commit()
    get_runtime_metrics().record_peer_connect()
    _log_vpn_event(
        "vpn_peer_connect",
        mode="live",
        user_id=current_user.id,
        server_id=server.server_id,
        client_ip=client_ip,
        protocol=requested_protocol,
    )

    return {
        "mode": "live",
        "status": "CONNECTED",
        "region": server.region or server.location,
        "server_id": server.server_id,
        "protocol": requested_protocol,
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
    disconnected_at = datetime.utcnow()
    active_connection = db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None)
    ).first()

    if active_connection:
        active_connection.disconnected_at = disconnected_at
        if active_connection.server:
            active_connection.server.current_connections = max(
                0,
                int(active_connection.server.current_connections or 0) - 1,
            )
            active_connection.server.updated_at = disconnected_at
            db.add(active_connection.server)
        db.add(active_connection)
        db.commit()
        get_runtime_metrics().record_peer_disconnect()
        _log_vpn_event(
            "vpn_peer_disconnect",
            mode="live",
            user_id=current_user.id,
            server_id=active_connection.server.server_id if active_connection.server else active_connection.server_id,
        )

    return {
        "mode": "live",
        "status": "DISCONNECTED",
        "disconnected_at": disconnected_at.isoformat(),
    }


@router.get("/config")
async def get_vpn_config(
    current_user: User = Depends(get_current_user),
):
    """
    Returns the latest allocated WireGuard config.
    """
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
