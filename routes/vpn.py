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
import subprocess
import socket
import errno
import shutil
import ipaddress
from datetime import datetime, timedelta, timezone
from typing import Optional, List, Any, Dict, Literal, Union
from urllib import error as urllib_error
from urllib import request as urllib_request

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
from models.usage_analytics import UserUsageStats
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
from services.tunnel_runtime import (
    SimulatedTunnelRuntime,
    get_tunnel_runtime,
    is_simulated_tunnel_mode,
)
from services.wireguard_tuning import tune_wireguard
from services.latency_optimizer import get_latency_optimizer
from services.wireguard_server_manager import (
    get_wireguard_server_manager,
    server_connection_from_db,
)
from slowapi import Limiter
from slowapi.util import get_remote_address
from utils.time_utils import utcnow

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

_REGION_HEALTH_CACHE: dict[str, dict[str, Any]] = {}
_REGION_RESOLUTION_CACHE: dict[str, dict[str, Any]] = {}
_TEST_REGION_HEALTH_OVERRIDES: dict[str, dict[str, Any]] = {}
_REGION_PROBE_CIRCUITS: dict[str, dict[str, Any]] = {}


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
    region_group: Optional[str] = None
    is_primary_region: bool = False
    priority_weight: int = 100
    latency_score: Optional[float] = None
    latency_ms: Optional[float] = None
    load_percent: Optional[float] = None
    status: str
    health_status: str
    region_health_status: Literal["up", "down", "unknown"] = "unknown"
    region_health_last_checked_at: Optional[str] = None
    region_health_reason_code: Optional[str] = None
    tier_restriction: Optional[str] = None
    premium_only: bool = False
    supported_protocols: List[str] = Field(default_factory=list, description="Protocols supported by this server")


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
    server_id: Optional[str] = Field(None, description="Exact server identifier for connect tracking.")
    protocol: Optional[str] = Field(None, description="Desired protocol used by the client session.")

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


class RegionListResponse(BaseModel):
    """Compatibility list payload for clients expecting `regions`."""
    regions: List[ServerInfo]
    total: int
    recommended_server_id: Optional[str] = None


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
    health_status: str = "unavailable"
    health_reason: Optional[str] = None
    transports: Optional[List[str]] = None
    requirements: List[VpnProtocolRequirement] = Field(default_factory=list)
    reason: Optional[str] = None


class VpnProtocolsResponse(BaseModel):
    user_tier: str
    device_type: Optional[str] = None
    protocols: List[VpnProtocolAvailability]


class VpnProtocolRegionHealth(BaseModel):
    region: str
    status: str
    total_servers: int
    available_servers: int
    healthy_servers: int
    degraded_servers: int
    reason: Optional[str] = None


class VpnProtocolHealth(BaseModel):
    protocol: str
    status: str
    total_servers: int
    available_servers: int
    healthy_servers: int
    degraded_servers: int
    reason: Optional[str] = None
    regions: List[VpnProtocolRegionHealth] = Field(default_factory=list)


class VpnProtocolHealthResponse(BaseModel):
    generated_at: str
    user_tier: str
    protocols: List[VpnProtocolHealth]


class DevRegionHealthOverride(BaseModel):
    server_id: str
    status: Literal["up", "down", "unknown"]
    reason_code: Optional[str] = None


class DevRegionHealthOverrideRequest(BaseModel):
    clear: bool = False
    overrides: List[DevRegionHealthOverride] = Field(default_factory=list)


class SimulatedTrafficRequest(BaseModel):
    session_id: Optional[str] = None
    rx_bytes: int = Field(0, ge=0)
    tx_bytes: int = Field(0, ge=0)
    rx_rate_bytes_per_sec: Optional[int] = Field(None, ge=0)
    tx_rate_bytes_per_sec: Optional[int] = Field(None, ge=0)


class SimulatedFailureRequest(BaseModel):
    auth_failure: Optional[bool] = None
    blocked_protocols: Optional[List[str]] = None
    blocked_regions: Optional[List[str]] = None


class RegionResolutionResponse(BaseModel):
    selected_region_id: str
    reason: str
    protocol: str
    device_type: Optional[str] = None
    preferred_region: Optional[str] = None
    user_geo_group: Optional[str] = None
    user_country_code: Optional[str] = None
    selected_region_group: Optional[str] = None
    cache_hit: bool = False


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


def _parse_script_json_result(text: str) -> Optional[dict[str, Any]]:
    raw = (text or "").strip()
    if not raw:
        return None
    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    for candidate in reversed(lines):
        if not (candidate.startswith("{") and candidate.endswith("}")):
            continue
        try:
            parsed = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed
    return None


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
        parsed = _parse_script_json_result(stdout or "")
        if success:
            if parsed and parsed.get("ok") is False:
                message = (
                    str(parsed.get("code") or "").strip()
                    or str(parsed.get("message") or "").strip()
                    or "credential_provision_failed"
                )
                return False, message
            if parsed:
                message = (
                    str(parsed.get("code") or "").strip()
                    or str(parsed.get("message") or "").strip()
                    or "credential_provisioned"
                )
                return True, message
            message = (stdout or "").strip() or "credential_provisioned"
            return True, message
        if parsed:
            message = (
                str(parsed.get("code") or "").strip()
                or str(parsed.get("message") or "").strip()
                or "credential_provision_failed"
            )
            return False, message
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


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _sync_simulated_usage_for_user(db: Session, user_id: int) -> None:
    if not is_simulated_tunnel_mode():
        return
    runtime = get_tunnel_runtime()
    session_id = runtime.active_session_for_user(user_id)
    if not session_id:
        return
    delta = runtime.pop_traffic_delta(session_id)
    rx_delta = int(delta.rx_delta_bytes or 0)
    tx_delta = int(delta.tx_delta_bytes or 0)
    if rx_delta <= 0 and tx_delta <= 0:
        return

    usage = (
        db.query(UserUsageStats)
        .filter(UserUsageStats.user_id == user_id)
        .first()
    )
    if usage is None:
        usage = UserUsageStats(
            user_id=user_id,
            total_connections=0,
            active_connections=0,
            total_bytes_uploaded=0,
            total_bytes_downloaded=0,
            total_data_gb=0.0,
            current_month_data_gb=0.0,
            first_seen_at=utcnow(),
            last_activity_at=utcnow(),
        )
    usage.total_bytes_downloaded = int(usage.total_bytes_downloaded or 0) + rx_delta
    usage.total_bytes_uploaded = int(usage.total_bytes_uploaded or 0) + tx_delta
    total_bytes = int(usage.total_bytes_downloaded or 0) + int(usage.total_bytes_uploaded or 0)
    usage.total_data_gb = float(total_bytes) / (1024 * 1024 * 1024)
    usage.current_month_data_gb = usage.total_data_gb
    usage.last_activity_at = utcnow()
    usage.updated_at = utcnow()
    db.add(usage)

    active_connection = (
        db.query(VPNConnection)
        .filter(
            VPNConnection.user_id == user_id,
            VPNConnection.disconnected_at.is_(None),
        )
        .order_by(VPNConnection.connected_at.desc())
        .first()
    )
    if active_connection:
        active_connection.total_bytes_received = int(active_connection.total_bytes_received or 0) + rx_delta
        active_connection.total_bytes_sent = int(active_connection.total_bytes_sent or 0) + tx_delta
        db.add(active_connection)

    peers = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user_id,
            WireGuardPeer.is_revoked == False,
        )
        .all()
    )
    if peers:
        target = peers[0]
        target.total_data_received = int(target.total_data_received or 0) + rx_delta
        target.total_data_sent = int(target.total_data_sent or 0) + tx_delta
        db.add(target)

    db.commit()


def _region_health_cache_ttl_seconds() -> float:
    raw = os.getenv("SECUREWAVE_REGION_HEALTH_CACHE_TTL_SECONDS", "10").strip()
    try:
        value = float(raw)
    except ValueError:
        value = 10.0
    return max(0.0, min(value, 120.0))


def _region_health_probe_enabled() -> bool:
    default_enabled = not IS_TESTING
    return _bool_env("SECUREWAVE_REGION_HEALTH_ACTIVE_PROBE", default_enabled)


def _region_health_probe_timeout_seconds() -> float:
    raw = os.getenv("SECUREWAVE_REGION_HEALTH_PROBE_TIMEOUT_SECONDS", "0.5").strip()
    try:
        value = float(raw)
    except ValueError:
        value = 0.5
    return max(0.1, min(value, 3.0))


def _region_probe_failure_threshold() -> int:
    raw = os.getenv("SECUREWAVE_REGION_PROBE_FAILURE_THRESHOLD", "3").strip()
    try:
        value = int(raw)
    except ValueError:
        value = 3
    return max(2, min(value, 10))


def _region_probe_cooldown_seconds() -> float:
    raw = os.getenv("SECUREWAVE_REGION_PROBE_COOLDOWN_SECONDS", "45").strip()
    try:
        value = float(raw)
    except ValueError:
        value = 45.0
    return max(5.0, min(value, 600.0))


def _region_probe_circuit_state(server_id: str, *, now: datetime) -> Optional[dict[str, Any]]:
    state = _REGION_PROBE_CIRCUITS.get(server_id)
    if not state:
        return None
    opened_until = state.get("opened_until")
    if isinstance(opened_until, datetime) and opened_until > now:
        return state
    if isinstance(opened_until, datetime) and opened_until <= now:
        state["opened_until"] = None
        _REGION_PROBE_CIRCUITS[server_id] = state
    return None


def _record_region_probe_outcome(
    server_id: str,
    *,
    status: str,
    reason_code: Optional[str],
    now: datetime,
) -> None:
    threshold = _region_probe_failure_threshold()
    cooldown_seconds = _region_probe_cooldown_seconds()
    payload = dict(_REGION_PROBE_CIRCUITS.get(server_id) or {})
    failures = int(payload.get("failures") or 0)

    if status == "up":
        payload.update(
            {
                "failures": 0,
                "opened_until": None,
                "last_reason_code": reason_code,
                "last_updated_at": now,
            }
        )
        _REGION_PROBE_CIRCUITS[server_id] = payload
        return

    failures += 1
    payload["failures"] = failures
    payload["last_reason_code"] = reason_code
    payload["last_updated_at"] = now
    if failures >= threshold:
        payload["opened_until"] = now + timedelta(seconds=cooldown_seconds)
        get_runtime_metrics().record_region_circuit_open()
    _REGION_PROBE_CIRCUITS[server_id] = payload


def _server_probe_host(server: VPNServer) -> Optional[str]:
    public_ip = (getattr(server, "public_ip", None) or "").strip()
    if public_ip:
        return public_ip
    endpoint = (getattr(server, "endpoint", None) or "").strip()
    if not endpoint:
        return None
    try:
        if endpoint.startswith("[") and "]" in endpoint:
            return endpoint[1:].split("]", 1)[0].strip() or None
        return endpoint.rsplit(":", 1)[0].strip() or None
    except Exception:
        return None


def _wireguard_listener_port(server: VPNServer) -> int:
    raw_port = getattr(server, "wg_listen_port", None)
    if isinstance(raw_port, int) and raw_port > 0:
        return raw_port
    endpoint = (getattr(server, "endpoint", None) or "").strip()
    if endpoint:
        try:
            return int(endpoint.rsplit(":", 1)[1])
        except Exception:
            pass
    return 51820


def _server_listener_targets(server: VPNServer) -> list[tuple[str, int, str]]:
    targets: list[tuple[str, int, str]] = []
    host = _server_probe_host(server)
    if not host:
        return targets

    # WireGuard is UDP-only.
    if getattr(server, "supports_wireguard", True):
        targets.append((host, _wireguard_listener_port(server), "udp"))

    if getattr(server, "supports_openvpn", False):
        openvpn_port = getattr(server, "openvpn_port", None) or 1194
        try:
            ovpn_port = int(openvpn_port)
        except (TypeError, ValueError):
            ovpn_port = 1194
        transport = (getattr(server, "openvpn_transport", None) or "udp").strip().lower()
        if transport not in {"udp", "tcp"}:
            transport = "udp"
        targets.append((host, ovpn_port, transport))

    if getattr(server, "supports_ikev2", False):
        targets.append((host, 500, "udp"))
        targets.append((host, 4500, "udp"))

    deduped: list[tuple[str, int, str]] = []
    seen: set[tuple[str, int, str]] = set()
    for entry in targets:
        if entry in seen:
            continue
        seen.add(entry)
        deduped.append(entry)
    return deduped


def _probe_tcp_port(host: str, port: int, timeout_s: float) -> str:
    sock: Optional[socket.socket] = None
    try:
        sock = socket.create_connection((host, int(port)), timeout=timeout_s)
        return "open"
    except socket.timeout:
        return "timeout"
    except OSError as exc:
        code = getattr(exc, "errno", None)
        if code in {errno.ECONNREFUSED}:
            return "closed"
        if code in {errno.ETIMEDOUT}:
            return "timeout"
        if code in {errno.EHOSTUNREACH, errno.ENETUNREACH, errno.EADDRNOTAVAIL}:
            return "host_unreachable"
        return "error"
    finally:
        if sock:
            try:
                sock.close()
            except OSError:
                pass


def _probe_udp_listener(host: str, port: int, timeout_s: float) -> str:
    sock: Optional[socket.socket] = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout_s)
        sock.sendto(b"\x00", (host, int(port)))
        return "sent"
    except socket.timeout:
        return "timeout"
    except OSError as exc:
        code = getattr(exc, "errno", None)
        if code in {errno.EHOSTUNREACH, errno.ENETUNREACH, errno.EADDRNOTAVAIL}:
            return "host_unreachable"
        return "error"
    finally:
        if sock:
            try:
                sock.close()
            except OSError:
                pass


def _probe_http_health_endpoint(server: VPNServer, timeout_s: float) -> str:
    template = os.getenv("SECUREWAVE_SERVER_HEALTH_ENDPOINT_TEMPLATE", "").strip()
    if not template:
        return "not_configured"
    host = _server_probe_host(server)
    if not host:
        return "missing_host"
    url = template.format(
        server_id=server.server_id,
        host=host,
        public_ip=(getattr(server, "public_ip", None) or "").strip(),
    )
    if not url:
        return "missing_url"
    req = urllib_request.Request(url=url, method="GET")
    try:
        with urllib_request.urlopen(req, timeout=timeout_s) as resp:
            status = int(getattr(resp, "status", 0) or 0)
            if 200 <= status < 300:
                return "up"
            return "down"
    except urllib_error.URLError as exc:
        reason = str(getattr(exc, "reason", "")).strip().lower()
        if "timed out" in reason:
            return "timeout"
        if "unreachable" in reason or "no route" in reason:
            return "host_unreachable"
        return "down"
    except TimeoutError:
        return "timeout"
    except Exception:
        return "down"


def _probe_host_icmp(host: str, timeout_s: float) -> str:
    if not _bool_env("SECUREWAVE_REGION_HEALTH_ICMP_PROBE", True):
        return "disabled"
    ping_path = shutil.which("ping")
    if not ping_path:
        return "missing"
    timeout_sec = str(max(1, int(round(timeout_s))))
    try:
        result = subprocess.run(
            [ping_path, "-c", "1", "-W", timeout_sec, host],
            capture_output=True,
            text=True,
            timeout=max(1.0, timeout_s + 0.5),
            check=False,
        )
    except subprocess.TimeoutExpired:
        return "timeout"
    except Exception:
        return "error"
    return "up" if result.returncode == 0 else "down"


def _stored_region_health(server: VPNServer) -> tuple[str, str]:
    if (getattr(server, "status", "") or "").strip().lower() != "active":
        return "down", "listener_down"
    if (getattr(server, "hcloud_server_state", "") or "").strip().lower() not in {"", "running"}:
        return "down", "host_unreachable"
    raw = (getattr(server, "health_status", "") or "").strip().lower()
    if raw in {"healthy", "degraded"}:
        return "up", "monitor_healthy"
    if raw in {"unhealthy", "unreachable", "offline", "unstable"}:
        return "down", "region_down"
    return "unknown", "health_unknown"


def _probe_region_health(server: VPNServer) -> tuple[str, str]:
    host = _server_probe_host(server)
    if not host:
        return "unknown", "missing_host"
    timeout_s = _region_health_probe_timeout_seconds()

    endpoint_probe = _probe_http_health_endpoint(server, timeout_s)
    if endpoint_probe == "up":
        return "up", "health_endpoint_ok"
    if endpoint_probe == "timeout":
        return "down", "timeout"
    if endpoint_probe == "host_unreachable":
        return "down", "host_unreachable"

    ssh_probe = _probe_tcp_port(host, 22, timeout_s)
    if ssh_probe == "open":
        return "up", "ssh_reachable"

    tcp_results: list[str] = []
    udp_results: list[str] = []
    for target_host, target_port, transport in _server_listener_targets(server):
        if transport == "tcp":
            tcp_results.append(_probe_tcp_port(target_host, target_port, timeout_s))
        else:
            udp_results.append(_probe_udp_listener(target_host, target_port, timeout_s))

    if "open" in tcp_results:
        return "up", "listener_up"
    if "host_unreachable" in tcp_results or "host_unreachable" in udp_results:
        return "down", "host_unreachable"
    if "timeout" in tcp_results or "timeout" in udp_results:
        return "down", "timeout"

    icmp_probe = _probe_host_icmp(host, timeout_s)
    if icmp_probe == "up":
        return "down", "listener_down"
    if icmp_probe == "timeout":
        return "down", "timeout"
    if icmp_probe == "down":
        return "down", "host_unreachable"

    if "closed" in tcp_results:
        return "down", "listener_down"
    if "sent" in udp_results:
        return "unknown", "udp_probe_inconclusive"

    return "unknown", "probe_inconclusive"


def _region_health_override(server: VPNServer) -> Optional[dict[str, Any]]:
    payload = _TEST_REGION_HEALTH_OVERRIDES.get(server.server_id)
    if not payload:
        return None
    status = str(payload.get("status") or "unknown").strip().lower()
    if status not in {"up", "down", "unknown"}:
        status = "unknown"
    return {
        "status": status,
        "last_checked_at": payload.get("last_checked_at"),
        "reason_code": payload.get("reason_code"),
    }


def _region_health_for_server(server: VPNServer, *, force_refresh: bool = False) -> dict[str, Any]:
    override = _region_health_override(server)
    if override is not None:
        return {
            "status": override["status"],
            "last_checked_at": override.get("last_checked_at") or _utc_iso(datetime.now(timezone.utc)),
            "reason_code": override.get("reason_code"),
        }

    now = datetime.now(timezone.utc)
    cache_key = str(server.server_id)
    if _region_health_probe_enabled():
        circuit = _region_probe_circuit_state(cache_key, now=now)
        if circuit is not None:
            opened_until = circuit.get("opened_until")
            opened_until_iso = _utc_iso(opened_until) if isinstance(opened_until, datetime) else _utc_iso(now)
            payload = {
                "status": "down",
                "last_checked_at": opened_until_iso,
                "reason_code": "circuit_open",
            }
            _REGION_HEALTH_CACHE[cache_key] = {"cached_at": now, **payload}
            return payload

    ttl = _region_health_cache_ttl_seconds()
    cached = _REGION_HEALTH_CACHE.get(cache_key)
    if (
        not force_refresh
        and cached is not None
        and ttl > 0
        and isinstance(cached.get("cached_at"), datetime)
        and (now - cached["cached_at"]).total_seconds() <= ttl
    ):
        return {
            "status": cached.get("status", "unknown"),
            "last_checked_at": cached.get("last_checked_at"),
            "reason_code": cached.get("reason_code"),
        }

    if _region_health_probe_enabled():
        status, reason_code = _probe_region_health(server)
        last_checked_at = _utc_iso(now)
        _record_region_probe_outcome(
            cache_key,
            status=status,
            reason_code=reason_code,
            now=now,
        )
    else:
        status, reason_code = _stored_region_health(server)
        last = getattr(server, "last_health_check", None)
        last_checked_at = _utc_iso(last) if isinstance(last, datetime) else _utc_iso(now)

    payload = {
        "status": status,
        "last_checked_at": last_checked_at,
        "reason_code": reason_code,
    }
    _REGION_HEALTH_CACHE[cache_key] = {"cached_at": now, **payload}
    return payload


def _region_health_map(servers: list[VPNServer], *, force_refresh: bool = False) -> dict[str, dict[str, Any]]:
    return {server.server_id: _region_health_for_server(server, force_refresh=force_refresh) for server in servers}


def _region_health_status(server: VPNServer, *, health_map: Optional[dict[str, dict[str, Any]]] = None) -> str:
    if health_map and server.server_id in health_map:
        return str(health_map[server.server_id].get("status") or "unknown")
    return str(_region_health_for_server(server).get("status") or "unknown")


def _effective_protocol_reason(
    protocol: str,
    *,
    servers: list[VPNServer],
    health_map: dict[str, dict[str, Any]],
) -> Optional[str]:
    up_servers = [server for server in servers if _region_health_status(server, health_map=health_map) == "up"]
    if not up_servers:
        return "no_servers_available"

    supporting_up = [server for server in up_servers if _server_supports_protocol(server, protocol)]
    if supporting_up:
        return None

    supporting_any = [server for server in servers if _server_supports_protocol(server, protocol)]
    if not supporting_any:
        return "unavailable_region"

    down_supporting = [
        server
        for server in supporting_any
        if _region_health_status(server, health_map=health_map) == "down"
    ]
    if down_supporting:
        return "region_down"
    return "unavailable_region"


def _protocol_unavailable_status_code(protocol: str, reason: Optional[str]) -> int:
    normalized = normalize_vpn_protocol(protocol)
    text = (reason or "").strip().lower()
    if text == "no_servers_available" and normalized in {"openvpn", "ikev2"}:
        return 409
    return 503 if text == "no_servers_available" else 409


def _protocol_unavailable_error_code(protocol: str, reason: Optional[str]) -> str:
    normalized = normalize_vpn_protocol(protocol)
    text = (reason or "").strip().lower()
    if text == "no_servers_available" and normalized in {"openvpn", "ikev2"}:
        return f"{normalized}_temporarily_unavailable"
    return text or "unavailable_region"


def _resolve_cache_ttl_seconds() -> float:
    raw = os.getenv("SECUREWAVE_REGION_RESOLUTION_CACHE_TTL_SECONDS", "10").strip()
    try:
        value = float(raw)
    except ValueError:
        value = 10.0
    return max(5.0, min(value, 15.0))


def _normalize_geo_group(raw: Optional[str]) -> Optional[str]:
    text = (raw or "").strip().lower()
    if not text:
        return None
    aliases = {
        "caribbean": "caribbean",
        "north_america": "north_america",
        "north-america": "north_america",
        "na": "north_america",
        "americas": "north_america",
        "usa": "north_america",
        "us": "north_america",
        "europe": "europe",
        "eu": "europe",
        "asia": "asia_pacific",
        "asia_pacific": "asia_pacific",
        "asia-pacific": "asia_pacific",
        "apac": "asia_pacific",
    }
    return aliases.get(text, text)


def _infer_geo_group_from_server(server: VPNServer) -> str:
    explicit = _normalize_geo_group(getattr(server, "region_group", None))
    if explicit:
        return explicit
    region = (getattr(server, "region", None) or "").strip().lower()
    if region in {"caribbean"}:
        return "caribbean"
    if region in {"americas", "north america", "north_america", "north-america"}:
        return "north_america"
    if region in {"europe", "eu"}:
        return "europe"
    if region in {"asia", "asia-pacific", "asia_pacific", "apac"}:
        return "asia_pacific"
    return "global"


def _normalize_country_code(raw: Optional[str]) -> Optional[str]:
    text = (raw or "").strip().upper()
    if len(text) != 2 or not text.isalpha():
        return None
    return text


def _resolve_user_geo_group(request: Request, *, country_code: Optional[str] = None) -> str:
    header_candidates = (
        request.headers.get("X-Geo-Group"),
        request.headers.get("X-Geo-Region"),
        request.headers.get("X-User-Region"),
    )
    for candidate in header_candidates:
        normalized = _normalize_geo_group(candidate)
        if normalized:
            return normalized
    if country_code:
        mapped = _country_code_to_geo_group(country_code)
        if mapped:
            return mapped
    env_default = _normalize_geo_group(os.getenv("SECUREWAVE_DEFAULT_GEO_GROUP", "north_america"))
    return env_default or "north_america"


def _lightweight_geoip_cidr_map() -> list[tuple[ipaddress._BaseNetwork, str]]:
    raw = os.getenv("SECUREWAVE_LIGHT_GEOIP_CIDR_MAP", "").strip()
    if not raw:
        return []
    try:
        payload = json.loads(raw)
    except Exception:
        return []
    if not isinstance(payload, dict):
        return []
    out: list[tuple[ipaddress._BaseNetwork, str]] = []
    for cidr, country in payload.items():
        cc = _normalize_country_code(str(country))
        if not cc:
            continue
        try:
            network = ipaddress.ip_network(str(cidr).strip(), strict=False)
        except Exception:
            continue
        out.append((network, cc))
    return out


def _request_client_ip(request: Request) -> Optional[str]:
    candidates = [
        request.headers.get("X-Forwarded-For"),
        request.headers.get("X-Real-IP"),
        request.client.host if request.client else None,
    ]
    for candidate in candidates:
        if not candidate:
            continue
        text = str(candidate).split(",")[0].strip()
        if text:
            return text
    return None


def _country_code_from_ip(ip_text: Optional[str]) -> Optional[str]:
    if not ip_text:
        return None
    try:
        ip_obj = ipaddress.ip_address(ip_text)
    except Exception:
        return None
    for network, country_code in _lightweight_geoip_cidr_map():
        try:
            if ip_obj in network:
                return country_code
        except Exception:
            continue
    return None


def _country_code_to_geo_group(country_code: str) -> Optional[str]:
    cc = _normalize_country_code(country_code)
    if not cc:
        return None
    if cc == "BB":
        return "caribbean"
    if cc in {"US", "CA", "MX"}:
        return "north_america"
    if cc in {"DE", "GB", "FR", "NL", "ES", "IT", "SE", "NO", "FI", "PL", "IE", "PT", "CH", "AT", "BE"}:
        return "europe"
    if cc in {"JP", "SG", "KR", "IN", "AU", "NZ"}:
        return "asia_pacific"
    return None


def _resolve_user_country_code(request: Request, current_user: User) -> Optional[str]:
    account_candidates = (
        getattr(current_user, "country_code", None),
        getattr(current_user, "country", None),
    )
    for candidate in account_candidates:
        cc = _normalize_country_code(candidate)
        if cc:
            return cc

    header_candidates = (
        request.headers.get("CF-IPCountry"),
        request.headers.get("X-Geo-Country"),
        request.headers.get("X-Country-Code"),
        request.headers.get("X-Country"),
    )
    for candidate in header_candidates:
        cc = _normalize_country_code(candidate)
        if cc:
            return cc

    return _country_code_from_ip(_request_client_ip(request))


def _geo_group_priority_order(
    *,
    user_country_code: Optional[str],
    user_geo_group: str,
    healthy_groups: list[str],
) -> list[str]:
    healthy = [item for item in healthy_groups if item]
    if not healthy:
        return []

    ordered: list[str] = []

    def push(group: Optional[str]) -> None:
        if not group:
            return
        normalized = _normalize_geo_group(group)
        if not normalized:
            return
        if normalized in healthy and normalized not in ordered:
            ordered.append(normalized)

    cc = _normalize_country_code(user_country_code)
    if cc == "BB":
        push("north_america")
        push("europe")

    push(user_geo_group)
    push(_country_code_to_geo_group(cc or ""))
    for candidate in ("north_america", "europe", "asia_pacific", "caribbean", "global"):
        push(candidate)
    for candidate in sorted(healthy):
        push(candidate)
    return ordered


def _matches_preferred_region(server: VPNServer, preferred_region: Optional[str]) -> bool:
    preferred = (preferred_region or "").strip().lower()
    if not preferred:
        return False
    candidates = {
        str(getattr(server, "server_id", "") or "").strip().lower(),
        str(getattr(server, "region", "") or "").strip().lower(),
        str(getattr(server, "location", "") or "").strip().lower(),
        str(getattr(server, "city", "") or "").strip().lower(),
    }
    return preferred in {item for item in candidates if item}


def _region_order_key(server: VPNServer) -> tuple[int, float, int, str]:
    latency_raw = getattr(server, "latency_score", None)
    if latency_raw is None:
        latency_raw = getattr(server, "latency_ms", None)
    latency_value: Optional[float] = None
    try:
        if latency_raw is not None:
            parsed = float(latency_raw)
            if parsed >= 0:
                latency_value = parsed
    except (TypeError, ValueError):
        latency_value = None

    try:
        weight = int(getattr(server, "priority_weight", 100) or 100)
    except (TypeError, ValueError):
        weight = 100
    if weight < 0:
        weight = 0
    latency_missing = 1 if latency_value is None else 0
    return (
        latency_missing,
        float(latency_value if latency_value is not None else 10_000.0),
        weight,
        str(getattr(server, "server_id", "") or "").lower(),
    )


def _resolve_region_cache_key(
    *,
    user_id: int,
    protocol: str,
    device_type: Optional[str],
    preferred_region: Optional[str],
    user_geo_group: str,
    user_country_code: Optional[str],
) -> str:
    return "|".join(
        [
            str(user_id),
            normalize_vpn_protocol(protocol),
            (device_type or "").strip().lower(),
            (preferred_region or "").strip().lower(),
            user_geo_group,
            (user_country_code or "").strip().upper(),
        ]
    )


def _select_best_region(
    *,
    servers: list[VPNServer],
    health_map: dict[str, dict[str, Any]],
    preferred_region: Optional[str],
    user_geo_group: str,
    user_country_code: Optional[str],
) -> tuple[VPNServer, str]:
    healthy = [
        server
        for server in servers
        if _region_health_status(server, health_map=health_map) == "up"
    ]
    if not healthy:
        raise ApiException(
            status_code=503,
            code="no_servers_available",
            message="No servers available",
        )

    healthy_sorted = sorted(healthy, key=_region_order_key)

    preferred = [server for server in healthy_sorted if _matches_preferred_region(server, preferred_region)]
    if preferred:
        chosen = preferred[0]
        if bool(getattr(chosen, "is_primary_region", False)):
            return chosen, "preferred_primary"
        return chosen, "preferred_region_healthy"

    by_group: dict[str, list[VPNServer]] = {}
    for server in healthy_sorted:
        by_group.setdefault(_infer_geo_group_from_server(server), []).append(server)

    ordered_groups = _geo_group_priority_order(
        user_country_code=user_country_code,
        user_geo_group=user_geo_group,
        healthy_groups=list(by_group.keys()),
    )
    had_preferred = bool((preferred_region or "").strip())

    for group in ordered_groups:
        group_servers = by_group.get(group) or []
        if not group_servers:
            continue
        group_primary = [item for item in group_servers if bool(getattr(item, "is_primary_region", False))]
        chosen = group_primary[0] if group_primary else group_servers[0]

        if _normalize_country_code(user_country_code) == "BB":
            if group == "north_america":
                return chosen, "barbados_na_primary"
            if group == "europe":
                return chosen, "barbados_eu_fallback"
            return chosen, "barbados_geo_fallback"

        if group == user_geo_group:
            if group_primary:
                return chosen, "failover_primary_down" if had_preferred else "geo_group_primary"
            return chosen, "geo_group_fallback" if had_preferred else "geo_group_candidate"

        return chosen, "geo_group_fallback"

    return healthy_sorted[0], "priority_weight_fallback"


def _resolve_region_with_cache(
    *,
    request: Request,
    current_user: User,
    db: Session,
    user_tier: str,
    protocol: str,
    device_type: Optional[str],
    preferred_region: Optional[str],
) -> tuple[dict[str, Any], bool]:
    normalized_protocol = normalize_vpn_protocol(protocol)
    if normalized_protocol == "auto":
        normalized_protocol = "wireguard"
    user_country_code = _resolve_user_country_code(request, current_user)
    user_geo_group = _resolve_user_geo_group(request, country_code=user_country_code)
    cache_key = _resolve_region_cache_key(
        user_id=current_user.id,
        protocol=normalized_protocol,
        device_type=device_type,
        preferred_region=preferred_region,
        user_geo_group=user_geo_group,
        user_country_code=user_country_code,
    )

    now = datetime.now(timezone.utc)
    ttl = _resolve_cache_ttl_seconds()
    cached = _REGION_RESOLUTION_CACHE.get(cache_key)
    if cached and isinstance(cached.get("cached_at"), datetime):
        age = (now - cached["cached_at"]).total_seconds()
        if 0 <= age <= ttl:
            payload = dict(cached.get("payload") or {})
            payload["cache_hit"] = True
            return payload, True

    protocol_servers = VPNServerService.get_active_servers(db, user_tier, protocol=normalized_protocol)
    if device_type and normalized_protocol not in _platform_supported_protocols(device_type):
        raise ApiException(
            status_code=400,
            code="protocol_not_supported_on_platform",
            message="Requested protocol is not supported on this platform.",
            details={"protocol": normalized_protocol, "device_type": device_type},
        )
    health_map = _region_health_map(protocol_servers)
    selected, reason = _select_best_region(
        servers=protocol_servers,
        health_map=health_map,
        preferred_region=preferred_region,
        user_geo_group=user_geo_group,
        user_country_code=user_country_code,
    )
    selected_group = _infer_geo_group_from_server(selected)
    payload = {
        "selected_region_id": selected.server_id,
        "reason": reason,
        "protocol": normalized_protocol,
        "device_type": device_type,
        "preferred_region": preferred_region,
        "user_geo_group": user_geo_group,
        "user_country_code": user_country_code,
        "selected_region_group": selected_group,
        "cache_hit": False,
    }
    _log_vpn_event(
        "region_resolved",
        failover_reason=reason,
        region_selected=selected.server_id,
        previous_region=preferred_region,
        selected_region_group=selected_group,
        user_geo_group=user_geo_group,
        user_country_code=user_country_code,
    )
    get_runtime_metrics().record_region_resolution(reason=reason)
    _REGION_RESOLUTION_CACHE[cache_key] = {"cached_at": now, "payload": payload}
    return payload, False


def run_region_health_watchdog_cycle(db: Session) -> dict[str, int]:
    """
    Periodic control-plane watchdog:
    - force-refreshes regional health probes
    - marks repeated failures as unreachable
    - applies cooldown-based circuit guardrails
    """
    servers = db.query(VPNServer).filter(VPNServer.status == "active").all()
    if not servers:
        return {"checked": 0, "up": 0, "down": 0, "unknown": 0, "marked_down": 0}

    now = datetime.now(timezone.utc)
    threshold = _region_probe_failure_threshold()
    counts = {"checked": 0, "up": 0, "down": 0, "unknown": 0, "marked_down": 0}

    for server in servers:
        counts["checked"] += 1
        probe = _region_health_for_server(server, force_refresh=True)
        status = str(probe.get("status") or "unknown").strip().lower()
        reason_code = str(probe.get("reason_code") or "").strip().lower()

        if status == "up":
            counts["up"] += 1
            server.consecutive_health_failures = 0
            if (server.health_status or "").strip().lower() in {"unreachable", "offline"}:
                server.health_status = "healthy"
        elif status == "down":
            counts["down"] += 1
            server.consecutive_health_failures = int(server.consecutive_health_failures or 0) + 1
            if server.consecutive_health_failures >= threshold:
                server.health_status = "unreachable"
                counts["marked_down"] += 1
            elif reason_code in {"listener_down", "timeout", "host_unreachable", "circuit_open"}:
                server.health_status = "unstable"
        else:
            counts["unknown"] += 1

        server.last_health_check = now.replace(tzinfo=None)
        db.add(server)

    db.commit()
    _log_vpn_event("region_health_watchdog_cycle", **counts)
    return counts


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

    tls_crypt_key = (getattr(server, "openvpn_tls_crypt_key", None) or "").strip()
    if not tls_crypt_key:
        tls_crypt_key = _read_optional_pem_from_env(
            pem_env="SECUREWAVE_OPENVPN_TLS_CRYPT_KEY",
            path_env="SECUREWAVE_OPENVPN_TLS_CRYPT_KEY_PATH",
        ) or ""

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
        "data-ciphers AES-256-GCM:AES-128-GCM",
        "cipher AES-256-GCM",
        "auth SHA256",
        "auth-user-pass",
        "auth-nocache",
        "verb 3",
        *[f"dhcp-option DNS {dns}" for dns in (dns_servers or []) if dns.strip()],
        *extra,
        "<ca>",
        ca_cert.strip(),
        "</ca>",
        *(["<tls-crypt>", tls_crypt_key, "</tls-crypt>"] if tls_crypt_key else []),
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
    # OpenVPN requires CA cert material to be provisioned on the server.
    if getattr(server, "supports_openvpn", False) and (
        getattr(server, "openvpn_ca_cert_pem", None) or ""
    ).strip() and _protocol_material_ready("openvpn"):
        out.append("openvpn")
    # IKEv2 requires CA cert + remote_id to be provisioned.
    if getattr(server, "supports_ikev2", False) and (
        getattr(server, "ikev2_ca_cert_pem", None) or ""
    ).strip() and (getattr(server, "ikev2_remote_id", None) or "").strip() and _protocol_material_ready("ikev2"):
        out.append("ikev2")
    return out


def _server_supports_protocol(server: VPNServer, protocol: str) -> bool:
    normalized = normalize_vpn_protocol(protocol)
    if normalized == "auto":
        return True
    supported = _server_supported_protocols(server)
    return normalized in supported


def _server_flag_supports_protocol(server: VPNServer, protocol: str) -> bool:
    normalized = normalize_vpn_protocol(protocol)
    if normalized == "wireguard":
        return bool(getattr(server, "supports_wireguard", True))
    if normalized == "openvpn":
        return bool(getattr(server, "supports_openvpn", False))
    if normalized == "ikev2":
        return bool(getattr(server, "supports_ikev2", False))
    return False


def _classify_protocol_provision_error(protocol: str, reason: str) -> str:
    normalized = normalize_vpn_protocol(protocol)
    text = (reason or "").strip().lower()
    if not text:
        return "credential_provision_failed"

    misconfigured_hints = (
        "missing",
        "not configured",
        "invalid",
        "certificate",
        "cert",
        "ca cert",
        "ca certificate",
        "ca_cert",
        "pki",
        "remote_id",
        "remote id",
        "endpoint",
        "ovpn_config_b64",
        "client_pkcs12",
    )
    if any(hint in text for hint in misconfigured_hints):
        return f"{normalized}_server_misconfigured"

    health_hints = (
        "timeout",
        "timed out",
        "connection refused",
        "connection reset",
        "no route to host",
        "network is unreachable",
        "name or service not known",
        "temporary failure in name resolution",
        "host unreachable",
        "healthcheck",
        "ssh",
        "permission denied",
    )
    if any(hint in text for hint in health_hints):
        return f"{normalized}_healthcheck_fail"

    if "temporarily unavailable" in text or "no active server" in text:
        return f"{normalized}_unavailable_region"

    return "credential_provision_failed"


def _provisioning_failure_should_block(message: str) -> bool:
    text = (message or "").strip().lower()
    if not text:
        return True
    # Non-blocking in dev/test flows where credentials are managed out-of-band.
    if text in {"auto provisioning disabled", "not_applicable"}:
        return False
    return True


def _protocol_runtime_checks_enabled() -> bool:
    # Keep deterministic test behavior unless explicitly enabled.
    if os.getenv("TESTING", "").strip().lower() == "true":
        return os.getenv("SECUREWAVE_TEST_ENFORCE_RUNTIME_CHECKS", "false").strip().lower() in {
            "1",
            "true",
            "yes",
            "on",
        }
    return os.getenv("SECUREWAVE_ENFORCE_RUNTIME_CHECKS", "true").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def _protocol_required_scripts(protocol: str) -> list[str]:
    normalized = normalize_vpn_protocol(protocol)
    if normalized == "openvpn":
        return [
            "/usr/local/bin/securewave-openvpn-issue-client",
            "/usr/local/bin/securewave-openvpn-upsert-user",
            "/usr/local/bin/securewave-openvpn-revoke-client",
        ]
    if normalized == "ikev2":
        return [
            "/usr/local/bin/securewave-ikev2-issue-client",
            "/usr/local/bin/securewave-ikev2-upsert-user",
            "/usr/local/bin/securewave-ikev2-revoke-client",
        ]
    return []


def _protocol_service_units(protocol: str) -> list[str]:
    normalized = normalize_vpn_protocol(protocol)
    if normalized == "openvpn":
        raw = os.getenv(
            "SECUREWAVE_OPENVPN_SERVICE_UNITS",
            "openvpn-server@server,openvpn-server@securewave,openvpn@server",
        ).strip()
        return [item.strip() for item in raw.split(",") if item.strip()]
    if normalized == "ikev2":
        raw = os.getenv(
            "SECUREWAVE_IKEV2_SERVICE_UNITS",
            "strongswan,strongswan-starter,charon-systemd",
        ).strip()
        return [item.strip() for item in raw.split(",") if item.strip()]
    return []


def _service_is_active(unit: str) -> bool:
    if not unit:
        return False
    try:
        result = subprocess.run(
            ["systemctl", "is-active", unit],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except Exception:
        return False
    return result.returncode == 0 and (result.stdout or "").strip() == "active"


def _protocol_material_ready(protocol: str) -> bool:
    normalized = normalize_vpn_protocol(protocol)
    if normalized not in {"openvpn", "ikev2"}:
        return True
    if not _protocol_runtime_checks_enabled():
        return True
    required_scripts = _protocol_required_scripts(normalized)
    return all(os.path.exists(path) and os.access(path, os.X_OK) for path in required_scripts)


def _protocol_health_ready(protocol: str) -> bool:
    normalized = normalize_vpn_protocol(protocol)
    if normalized not in {"openvpn", "ikev2"}:
        return True
    if not _protocol_runtime_checks_enabled():
        return True
    units = _protocol_service_units(normalized)
    if not units:
        return False
    return any(_service_is_active(unit) for unit in units)


def _protocol_temporarily_unavailable_code(protocol: str) -> str:
    normalized = normalize_vpn_protocol(protocol)
    if normalized in {"openvpn", "ikev2"}:
        return f"{normalized}_temporarily_unavailable"
    return "protocol_temporarily_unavailable"


def _normalized_protocol_runtime_health(
    server: VPNServer,
    *,
    health_map: Optional[dict[str, dict[str, Any]]] = None,
) -> str:
    return "healthy" if _region_health_status(server, health_map=health_map) == "up" else "unavailable"


def _protocol_health_summary(
    protocol: str,
    servers: list[VPNServer],
    *,
    health_map: Optional[dict[str, dict[str, Any]]] = None,
) -> dict[str, Any]:
    normalized = normalize_vpn_protocol(protocol)
    health_lookup = health_map or _region_health_map(servers)
    protocol_flags = [server for server in servers if _server_flag_supports_protocol(server, normalized)]
    eligible_servers = [server for server in protocol_flags if _server_supports_protocol(server, normalized)]
    healthy_servers = [
        server for server in eligible_servers if _region_health_status(server, health_map=health_lookup) == "up"
    ]

    reason = _effective_protocol_reason(
        normalized,
        servers=servers,
        health_map=health_lookup,
    )
    status = "healthy" if healthy_servers else "unavailable"

    region_groups: dict[str, list[VPNServer]] = {}
    for server in servers:
        region = (
            (getattr(server, "region", None) or "")
            or (getattr(server, "country_code", None) or "")
            or (getattr(server, "country", None) or "")
            or "global"
        )
        key = str(region).strip() or "global"
        region_groups.setdefault(key, []).append(server)

    region_rows: list[VpnProtocolRegionHealth] = []
    for region_name in sorted(region_groups.keys()):
        region_servers = region_groups[region_name]
        region_flags = [
            server for server in region_servers if _server_flag_supports_protocol(server, normalized)
        ]
        if not region_flags:
            continue
        region_eligible = [
            server for server in region_flags if _server_supports_protocol(server, normalized)
        ]
        region_up_count = sum(
            1
            for server in region_eligible
            if _region_health_status(server, health_map=health_lookup) == "up"
        )
        region_down_count = sum(
            1
            for server in region_flags
            if _region_health_status(server, health_map=health_lookup) == "down"
        )
        region_up_any = any(
            _region_health_status(server, health_map=health_lookup) == "up"
            for server in region_flags
        )
        region_reason: Optional[str] = None
        if region_up_count == 0:
            if not region_up_any and region_down_count > 0:
                region_reason = "region_down"
            elif len(region_eligible) == 0:
                region_reason = "unavailable_region"
            else:
                region_reason = "no_servers_available"

        region_rows.append(
            VpnProtocolRegionHealth(
                region=region_name,
                status="healthy" if region_up_count > 0 else "unavailable",
                total_servers=len(region_flags),
                available_servers=region_up_count,
                healthy_servers=region_up_count,
                degraded_servers=0,
                reason=region_reason,
            )
        )

    return {
        "protocol": normalized,
        "status": status,
        "reason": reason,
        "total_servers": len(protocol_flags),
        "available_servers": len(healthy_servers),
        "healthy_servers": len(healthy_servers),
        "degraded_servers": 0,
        "regions": region_rows,
    }


def _protocol_health_matrix(
    servers: list[VPNServer],
    *,
    health_map: Optional[dict[str, dict[str, Any]]] = None,
) -> dict[str, dict[str, Any]]:
    lookup = health_map or _region_health_map(servers)
    return {
        protocol: _protocol_health_summary(protocol, servers, health_map=lookup)
        for protocol in SUPPORTED_PROTOCOLS
    }


def _server_is_usable_for_protocol(
    server: VPNServer,
    protocol: str,
    *,
    health_map: Optional[dict[str, dict[str, Any]]] = None,
) -> bool:
    normalized = normalize_vpn_protocol(protocol)
    if not _server_supports_protocol(server, normalized):
        return False
    if normalized in {"openvpn", "ikev2"} and not _protocol_health_ready(normalized):
        return False
    return _region_health_status(server, health_map=health_map) == "up"


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
            and _server_supports_protocol(server, preferred)
        ):
            return preferred

    for candidate in _auto_protocol_order():
        if (
            candidate in supported_by_platform
            and candidate in allowed_protocols
            and _server_supports_protocol(server, candidate)
        ):
            return candidate

    # Defensive fallback to preserve backward compatibility.
    supported = _server_supported_protocols(server)
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
    raw = os.getenv("SECUREWAVE_OPENVPN_AUTH_MODE", "mtls").strip().lower()
    if raw in {"mtls", "tls", "cert"}:
        return "mtls"
    return "userpass"


def _openvpn_allow_userpass_fallback() -> bool:
    return os.getenv("SECUREWAVE_OPENVPN_MTLS_FALLBACK_USERPASS", "true").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def _ikev2_auth_mode() -> str:
    raw = os.getenv("SECUREWAVE_IKEV2_AUTH_MODE", "eap-tls").strip().lower()
    if raw in {"eap-mschapv2", "mschapv2", "userpass"}:
        return "eap-mschapv2"
    return "eap-tls"


def _ikev2_allow_userpass_fallback() -> bool:
    return os.getenv("SECUREWAVE_IKEV2_EAPTLS_FALLBACK_USERPASS", "true").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def _effective_ikev2_auth_mode(device_type: Optional[str]) -> str:
    """Resolve runtime IKEv2 auth mode for a given platform."""
    mode = _ikev2_auth_mode()
    dt = (device_type or "").strip().lower()
    if dt == "linux" and mode == "eap-tls" and _ikev2_allow_userpass_fallback():
        return "eap-mschapv2"
    return mode


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
    if protocol in {"openvpn", "ikev2"}:
        if not _protocol_material_ready(protocol):
            raise ApiException(
                status_code=409,
                code=f"{protocol}_server_misconfigured",
                message="Requested protocol server provisioning is incomplete.",
                details={"protocol": protocol},
            )
        if not _protocol_health_ready(protocol):
            raise ApiException(
                status_code=409,
                code=f"{protocol}_healthcheck_fail",
                message="Requested protocol service is not healthy on the server.",
                details={"protocol": protocol},
            )

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
        selected_health = _region_health_for_server(server)
        if selected_health.get("status") != "up":
            raise ApiException(
                status_code=409,
                code="region_down",
                message="Selected region is offline.",
                details={
                    "protocol": protocol,
                    "server_id": server.server_id,
                    "region_health_status": selected_health.get("status"),
                    "reason_code": selected_health.get("reason_code"),
                },
            )
        return server

    all_servers = VPNServerService.get_active_servers(db, user_tier, protocol=protocol)
    health_map = _region_health_map(all_servers)
    candidates = [
        server
        for server in all_servers
        if _server_is_usable_for_protocol(server, protocol, health_map=health_map)
    ]
    if not candidates:
        reason = _effective_protocol_reason(protocol, servers=all_servers, health_map=health_map)
        status_code = _protocol_unavailable_status_code(protocol, reason)
        error_code = _protocol_unavailable_error_code(protocol, reason)
        raise ApiException(
            status_code=status_code,
            code=error_code,
            message="Requested protocol is currently unavailable on active servers.",
            details={"protocol": protocol, "reason": reason},
        )

    latency_optimizer = get_latency_optimizer()
    scored = latency_optimizer.rank_servers(
        candidates,
        user_region_hint=region_hint,
    )
    score_map = {item.server_id: item.score for item in scored}
    candidates.sort(
        key=lambda s: (
            1 if _region_health_status(s, health_map=health_map) == "up" else 0,
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
    health_map = _region_health_map(servers)
    protocol_health = _protocol_health_matrix(servers, health_map=health_map)
    any_up_servers = any(
        _region_health_status(server, health_map=health_map) == "up"
        for server in servers
    )

    protocol_payload: list[VpnProtocolAvailability] = []
    for protocol in SUPPORTED_PROTOCOLS:
        health = protocol_health.get(protocol) or {
            "status": "unavailable",
            "reason": "no_active_server_support",
            "available_servers": 0,
            "healthy_servers": 0,
            "degraded_servers": 0,
            "total_servers": 0,
        }
        health_status = str(health.get("status") or "unavailable")
        health_reason = health.get("reason")
        server_enabled = int(health.get("available_servers") or 0) > 0

        reason = None
        if protocol not in enabled_protocols:
            reason = "disabled_server_side"
        elif protocol not in plan_allowed:
            reason = "restricted_by_plan"
        elif protocol not in platform_supported:
            reason = "not_supported_on_platform"
        elif not server_enabled:
            reason = str(
                health_reason
                or ("no_servers_available" if not any_up_servers else "unavailable_region")
            )
        elif protocol == "ikev2" and normalized_device_type == "linux":
            # Linux runner only implements eap-mschapv2; warn if backend is eap-tls.
            if _effective_ikev2_auth_mode(normalized_device_type) == "eap-tls":
                reason = "ikev2_auth_mode_mismatch_linux"
        enabled = reason is None

        transports = ["udp", "tcp"] if protocol == "openvpn" else None
        protocol_payload.append(
            VpnProtocolAvailability(
                protocol=protocol,
                enabled=enabled,
                server_enabled=server_enabled,
                plan_enabled=protocol in plan_allowed and protocol in enabled_protocols,
                platform_supported=protocol in platform_supported,
                health_status=health_status,
                health_reason=health_reason,
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
    response_model=VpnProtocolsResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def list_protocol_capabilities(
    request: Request,
    device_type: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Compatibility alias of /api/vpn/protocols."""
    return await list_protocols(
        request=request,
        device_type=device_type,
        current_user=current_user,
        db=db,
    )


@router.get(
    "/protocol-health",
    response_model=VpnProtocolHealthResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def protocol_health(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """DevOps-oriented protocol readiness matrix (global + per-region)."""
    user_tier = get_user_tier(current_user, db)
    servers = VPNServerService.get_active_servers(db, user_tier)
    health_map = _region_health_map(servers)
    matrix = _protocol_health_matrix(servers, health_map=health_map)
    payload = [
        VpnProtocolHealth(
            protocol=protocol,
            status=str((matrix.get(protocol) or {}).get("status") or "unavailable"),
            total_servers=int((matrix.get(protocol) or {}).get("total_servers") or 0),
            available_servers=int((matrix.get(protocol) or {}).get("available_servers") or 0),
            healthy_servers=int((matrix.get(protocol) or {}).get("healthy_servers") or 0),
            degraded_servers=int((matrix.get(protocol) or {}).get("degraded_servers") or 0),
            reason=(matrix.get(protocol) or {}).get("reason"),
            regions=list((matrix.get(protocol) or {}).get("regions") or []),
        )
        for protocol in SUPPORTED_PROTOCOLS
    ]
    return VpnProtocolHealthResponse(
        generated_at=_utc_iso(datetime.now(timezone.utc)),
        user_tier=user_tier,
        protocols=payload,
    )


@router.post(
    "/dev/region-health",
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("30/minute")
async def dev_region_health_override(
    request: Request,
    payload: DevRegionHealthOverrideRequest,
    current_user: User = Depends(get_current_user),
):
    """Test-only helper to simulate region health outcomes without real probes."""
    if not IS_TESTING and not _bool_env("SECUREWAVE_ENABLE_DEV_REGION_HEALTH_ENDPOINT", False):
        raise HTTPException(status_code=404, detail="Not found")

    if payload.clear:
        _TEST_REGION_HEALTH_OVERRIDES.clear()

    now_iso = _utc_iso(datetime.now(timezone.utc))
    for item in payload.overrides:
        _TEST_REGION_HEALTH_OVERRIDES[item.server_id] = {
            "status": item.status,
            "reason_code": item.reason_code,
            "last_checked_at": now_iso,
        }
    _REGION_HEALTH_CACHE.clear()
    _REGION_RESOLUTION_CACHE.clear()
    _REGION_PROBE_CIRCUITS.clear()

    return {
        "status": "ok",
        "overrides": _TEST_REGION_HEALTH_OVERRIDES,
        "updated_by_user_id": current_user.id,
    }


@router.post(
    "/simulate/traffic",
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def simulate_traffic(
    request: Request,
    payload: SimulatedTrafficRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Test-only helper to inject deterministic traffic in simulated tunnel mode.
    """
    if not IS_TESTING and not _bool_env("SECUREWAVE_ENABLE_SIM_TUNNEL_ENDPOINTS", False):
        raise HTTPException(status_code=404, detail="Not found")
    if not is_simulated_tunnel_mode():
        raise ApiException(
            status_code=409,
            code="simulation_mode_disabled",
            message="Tunnel simulation mode is not enabled.",
        )

    runtime = get_tunnel_runtime()
    if not isinstance(runtime, SimulatedTunnelRuntime):
        raise ApiException(
            status_code=409,
            code="simulation_runtime_unavailable",
            message="Simulated runtime is unavailable.",
        )

    session_id = payload.session_id or runtime.active_session_for_user(current_user.id)
    if not session_id:
        raise ApiException(
            status_code=409,
            code="no_active_session",
            message="No active simulated session for user.",
        )

    if payload.rx_rate_bytes_per_sec is not None or payload.tx_rate_bytes_per_sec is not None:
        ok = runtime.set_traffic_rate(
            session_id,
            rx_rate=payload.rx_rate_bytes_per_sec,
            tx_rate=payload.tx_rate_bytes_per_sec,
        )
        if not ok:
            raise ApiException(
                status_code=404,
                code="session_not_found",
                message="Simulated session not found.",
            )

    if payload.rx_bytes > 0 or payload.tx_bytes > 0:
        ok = runtime.inject_traffic(
            session_id,
            rx_bytes=payload.rx_bytes,
            tx_bytes=payload.tx_bytes,
        )
        if not ok:
            raise ApiException(
                status_code=404,
                code="session_not_found",
                message="Simulated session not found.",
            )

    _sync_simulated_usage_for_user(db, current_user.id)
    traffic = runtime.get_traffic(session_id)
    return {
        "mode": "simulated",
        "session_id": session_id,
        "rx_bytes": traffic.rx_bytes,
        "tx_bytes": traffic.tx_bytes,
        "connected": traffic.connected,
        "timestamp_ms": traffic.timestamp_ms,
    }


@router.post(
    "/simulate/failures",
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("30/minute")
async def simulate_failures(
    request: Request,
    payload: SimulatedFailureRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Test-only failure injection knobs for simulated runtime.
    """
    if not IS_TESTING and not _bool_env("SECUREWAVE_ENABLE_SIM_TUNNEL_ENDPOINTS", False):
        raise HTTPException(status_code=404, detail="Not found")
    if not is_simulated_tunnel_mode():
        raise ApiException(
            status_code=409,
            code="simulation_mode_disabled",
            message="Tunnel simulation mode is not enabled.",
        )
    runtime = get_tunnel_runtime()
    if not isinstance(runtime, SimulatedTunnelRuntime):
        raise ApiException(
            status_code=409,
            code="simulation_runtime_unavailable",
            message="Simulated runtime is unavailable.",
        )
    runtime.set_failure_modes(
        auth_failure=payload.auth_failure,
        blocked_regions=payload.blocked_regions,
        blocked_protocols=payload.blocked_protocols,
    )
    return {
        "mode": "simulated",
        "status": "ok",
        "runtime": runtime.health(),
    }


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
    health_map = _region_health_map(servers)

    # Filter by region if specified
    if region:
        servers = [s for s in servers if s.region and s.region.lower() == region.lower()]

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
        region_health = health_map.get(server.server_id) or _region_health_for_server(server)

        server_info = ServerInfo(
            server_id=server.server_id,
            location=server.location,
            country=server.country,
            country_code=server.country_code,
            city=server.city,
            region=server.region,
            region_group=getattr(server, "region_group", None),
            is_primary_region=bool(getattr(server, "is_primary_region", False)),
            priority_weight=int(getattr(server, "priority_weight", 100) or 100),
            latency_score=getattr(server, "latency_score", None),
            latency_ms=server.latency_ms,
            load_percent=round(load_percent, 1),
            status=server.status,
            health_status=server.health_status,
            region_health_status=str(region_health.get("status") or "unknown"),
            region_health_last_checked_at=region_health.get("last_checked_at"),
            region_health_reason_code=region_health.get("reason_code"),
            tier_restriction=server.tier_restriction,
            premium_only=bool((server.tier_restriction or "").strip().lower() == "premium"),
            supported_protocols=_server_supported_protocols(server),
        )
        server_list.append(server_info)

        # Track best server for recommendation using geo RTT weighting.
        score = latency_optimizer.score_server(
            server,
            baselines=baselines,
            user_region_hint=region_hint,
        )
        if str(region_health.get("status") or "unknown") == "up" and score > best_score:
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
        servers=server_list,
        total=len(server_list),
        recommended_server_id=recommended_id,
    )


@router.get(
    "/regions",
    response_model=RegionListResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def list_regions(
    request: Request,
    region: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Compatibility alias of /api/vpn/servers with `regions` key."""
    payload = await list_servers(
        request=request,
        region=region,
        current_user=current_user,
        db=db,
    )
    return RegionListResponse(
        regions=payload.servers,
        total=payload.total,
        recommended_server_id=payload.recommended_server_id,
    )


@router.get(
    "/resolve-region",
    response_model=RegionResolutionResponse,
    responses=VPN_ERROR_RESPONSES,
)
@rate_limit("60/minute")
async def resolve_region(
    request: Request,
    protocol: str = "wireguard",
    device_type: Optional[str] = None,
    preferred_region: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Resolve the best healthy region for a protocol/device context."""
    normalized_protocol = normalize_vpn_protocol(protocol)
    if normalized_protocol == "auto":
        normalized_protocol = "wireguard"
    normalized_device = (device_type or "").strip().lower() or None
    if normalized_device and normalized_device not in {"windows", "macos", "linux", "ios", "android"}:
        raise ApiException(
            status_code=400,
            code="invalid_device_type",
            message="Unsupported device_type. Supported: windows, macos, linux, ios, android.",
            details={"device_type": device_type},
        )
    preferred = (preferred_region or "").strip() or None
    user_tier = get_user_tier(current_user, db)
    payload, cache_hit = _resolve_region_with_cache(
        request=request,
        current_user=current_user,
        db=db,
        user_tier=user_tier,
        protocol=normalized_protocol,
        device_type=normalized_device,
        preferred_region=preferred,
    )
    return RegionResolutionResponse(
        selected_region_id=str(payload.get("selected_region_id") or ""),
        reason=str(payload.get("reason") or "priority_weight_fallback"),
        protocol=str(payload.get("protocol") or normalized_protocol),
        device_type=normalized_device,
        preferred_region=preferred,
        user_geo_group=payload.get("user_geo_group"),
        user_country_code=payload.get("user_country_code"),
        selected_region_group=payload.get("selected_region_group"),
        cache_hit=bool(payload.get("cache_hit") if payload.get("cache_hit") is not None else cache_hit),
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
    region_health = _region_health_for_server(server, force_refresh=True)

    return ServerInfo(
        server_id=server.server_id,
        location=server.location,
        country=server.country,
        country_code=server.country_code,
        city=server.city,
        region=server.region,
        region_group=getattr(server, "region_group", None),
        is_primary_region=bool(getattr(server, "is_primary_region", False)),
        priority_weight=int(getattr(server, "priority_weight", 100) or 100),
        latency_score=getattr(server, "latency_score", None),
        latency_ms=server.latency_ms,
        load_percent=round(load_percent, 1),
        status=server.status,
        health_status=server.health_status,
        region_health_status=str(region_health.get("status") or "unknown"),
        region_health_last_checked_at=region_health.get("last_checked_at"),
        region_health_reason_code=region_health.get("reason_code"),
        tier_restriction=server.tier_restriction,
        premium_only=bool((server.tier_restriction or "").strip().lower() == "premium"),
        supported_protocols=_server_supported_protocols(server),
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

    if requested_explicit and requested_protocol in {"openvpn", "ikev2"}:
        if not _protocol_material_ready(requested_protocol):
            raise ApiException(
                status_code=409,
                code=f"{requested_protocol}_server_misconfigured",
                message="Requested protocol server provisioning is incomplete.",
                details={"protocol": requested_protocol},
            )
        if not _protocol_health_ready(requested_protocol):
            raise ApiException(
                status_code=409,
                code=f"{requested_protocol}_healthcheck_fail",
                message="Requested protocol service is not healthy on the server.",
                details={"protocol": requested_protocol},
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
        selected_health = _region_health_for_server(server)
        if selected_health.get("status") != "up":
            raise ApiException(
                status_code=409,
                code="region_down",
                message="Selected region is offline.",
                details={
                    "server_id": server.server_id,
                    "region_health_status": selected_health.get("status"),
                    "reason_code": selected_health.get("reason_code"),
                },
            )

    if server is None and peer.server_id:
        server = db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
        if server and server.tier_restriction and user_tier == "free":
            server = None
        if server and requested_explicit and not _server_supports_protocol(server, requested_protocol):
            server = None
        if server and requested_explicit and not _server_is_usable_for_protocol(server, requested_protocol):
            server = None

    all_servers = VPNServerService.get_active_servers(
        db,
        user_tier,
        protocol=requested_protocol if requested_explicit else None,
    )
    health_map = _region_health_map(all_servers)
    candidates = list(all_servers)
    if requested_explicit:
        candidates = [
            item
            for item in candidates
            if _server_is_usable_for_protocol(item, requested_protocol, health_map=health_map)
        ]
    if requested_protocol == "auto":
        candidates = [
            item
            for item in candidates
            if _region_health_status(item, health_map=health_map) == "up"
            if any(
                proto in allowed_protocols
                for proto in _server_supported_protocols(item)
            )
        ]

    if payload.server_id and server is not None and all(server.id != item.id for item in candidates):
        raise ApiException(
            status_code=409,
            code="region_down",
            message="Selected region is offline.",
            details={"server_id": server.server_id},
        )

    if not candidates:
        up_servers = [
            item
            for item in all_servers
            if _region_health_status(item, health_map=health_map) == "up"
        ]
        if requested_explicit:
            reason = _effective_protocol_reason(
                requested_protocol,
                servers=all_servers,
                health_map=health_map,
            )
            status_code = _protocol_unavailable_status_code(
                requested_protocol,
                reason,
            )
            error_code = _protocol_unavailable_error_code(
                requested_protocol,
                reason,
            )
            raise ApiException(
                status_code=status_code,
                code=error_code,
                message="Requested protocol is currently unavailable on active servers.",
                details={"protocol": requested_protocol, "reason": reason},
            )
        if not up_servers:
            raise ApiException(
                status_code=503,
                code="no_servers_available",
                message="No VPN servers available. Please try again later.",
            )
        raise ApiException(
            status_code=409,
            code="no_protocol_available",
            message="No VPN protocol is available for this account/platform combination.",
            details={"tier": user_tier, "device_type": device_type},
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
                1 if _region_health_status(s, health_map=health_map) == "up" else 0,
                score_map.get(s.server_id, float("-inf")),
            ),
            reverse=True,
        )
        server = candidates[0]
    elif _region_health_status(server, health_map=health_map) != "up":
        raise ApiException(
            status_code=409,
            code="region_down",
            message="Selected region is offline.",
            details={"server_id": server.server_id},
        )

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
                    reason = str(exc)
                    if not _openvpn_allow_userpass_fallback():
                        code = _classify_protocol_provision_error("openvpn", reason)
                        raise ApiException(
                            status_code=502,
                            code=code,
                            message="Failed to provision OpenVPN certificate profile.",
                            details={"protocol": "openvpn", "reason": reason},
                        )
                    logger.warning(
                        "OpenVPN mTLS provisioning failed; falling back to userpass for server=%s: %s",
                        server.server_id,
                        reason,
                    )
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
                    if not provisioned and _provisioning_failure_should_block(message):
                        raise ApiException(
                            status_code=502,
                            code=_classify_protocol_provision_error("openvpn", message),
                            message="Failed to provision OpenVPN credential on selected server.",
                            details={"protocol": "openvpn", "reason": message, "server_id": server.server_id},
                        )
                    peer_registered = provisioned
                    registration_status = (
                        f"mtls_failed_fallback_userpass: {reason}"
                        if not provisioned
                        else f"mtls_failed_fallback_userpass: {message}"
                    )
                    issued = None
                if issued is None:
                    pass
                else:
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
                if not provisioned and _provisioning_failure_should_block(message):
                    raise ApiException(
                        status_code=502,
                        code=_classify_protocol_provision_error("openvpn", message),
                        message="Failed to provision OpenVPN credential on selected server.",
                        details={"protocol": "openvpn", "reason": message, "server_id": server.server_id},
                    )
                peer_registered = provisioned
                registration_status = message
        elif effective_protocol == "ikev2":
            ikev2_mode = _effective_ikev2_auth_mode(device_type)
            if ikev2_mode == "eap-tls":
                try:
                    issued = await creds_service.issue_ikev2_certificate_profile(
                        user_id=current_user.id,
                        device_id=peer.id,
                        server=server,
                    )
                except Exception as exc:
                    reason = str(exc)
                    if not _ikev2_allow_userpass_fallback():
                        code = _classify_protocol_provision_error("ikev2", reason)
                        raise ApiException(
                            status_code=502,
                            code=code,
                            message="Failed to provision IKEv2 certificate profile.",
                            details={"protocol": "ikev2", "reason": reason},
                        )
                    logger.warning(
                        "IKEv2 EAP-TLS provisioning failed; falling back to EAP-MSCHAPv2 for server=%s: %s",
                        server.server_id,
                        reason,
                    )
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
                    if not provisioned and _provisioning_failure_should_block(message):
                        raise ApiException(
                            status_code=502,
                            code=_classify_protocol_provision_error("ikev2", message),
                            message="Failed to provision IKEv2 credential on selected server.",
                            details={"protocol": "ikev2", "reason": message, "server_id": server.server_id},
                        )
                    peer_registered = provisioned
                    registration_status = (
                        f"eap_tls_failed_fallback_userpass: {reason}"
                        if not provisioned
                        else f"eap_tls_failed_fallback_userpass: {message}"
                    )
                else:
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
                if not provisioned and _provisioning_failure_should_block(message):
                    raise ApiException(
                        status_code=502,
                        code=_classify_protocol_provision_error("ikev2", message),
                        message="Failed to provision IKEv2 credential on selected server.",
                        details={"protocol": "ikev2", "reason": message, "server_id": server.server_id},
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
                reason = str(exc)
                if not _openvpn_allow_userpass_fallback():
                    raise ApiException(
                        status_code=502,
                        code=_classify_protocol_provision_error("openvpn", reason),
                        message="Failed to provision OpenVPN certificate profile.",
                        details={"protocol": "openvpn", "reason": reason},
                    )
                logger.warning(
                    "OpenVPN mTLS provisioning failed; falling back to userpass for server=%s: %s",
                    server.server_id,
                    reason,
                )
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
                provisioned, message = await provision_protocol_credentials_on_server(
                    server=server,
                    protocol="openvpn",
                    username=creds.username,
                    password=creds.password,
                )
                if not provisioned and _provisioning_failure_should_block(message):
                    raise ApiException(
                        status_code=502,
                        code=_classify_protocol_provision_error("openvpn", message),
                        message="Failed to provision OpenVPN credential on selected server.",
                        details={"protocol": "openvpn", "reason": message, "server_id": server.server_id},
                    )
                status_message = f"mtls_failed_fallback_userpass: {reason}"
            else:
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
            provisioned, message = await provision_protocol_credentials_on_server(
                server=server,
                protocol="openvpn",
                username=creds.username,
                password=creds.password,
            )
            if not provisioned and _provisioning_failure_should_block(message):
                raise ApiException(
                    status_code=502,
                    code=_classify_protocol_provision_error("openvpn", message),
                    message="Failed to provision OpenVPN credential on selected server.",
                    details={"protocol": "openvpn", "reason": message, "server_id": server.server_id},
                )
            status_message = "credential_provisioned"
    else:
        if _effective_ikev2_auth_mode(device_type) == "eap-tls":
            try:
                issued = await creds_service.issue_ikev2_certificate_profile(
                    user_id=current_user.id,
                    device_id=peer.id,
                    server=server,
                )
            except Exception as exc:
                reason = str(exc)
                if not _ikev2_allow_userpass_fallback():
                    raise ApiException(
                        status_code=502,
                        code=_classify_protocol_provision_error("ikev2", reason),
                        message="Failed to provision IKEv2 certificate profile.",
                        details={"protocol": "ikev2", "reason": reason},
                    )
                logger.warning(
                    "IKEv2 EAP-TLS provisioning failed; falling back to EAP-MSCHAPv2 for server=%s: %s",
                    server.server_id,
                    reason,
                )
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
                provisioned, message = await provision_protocol_credentials_on_server(
                    server=server,
                    protocol="ikev2",
                    username=creds.username,
                    password=creds.password,
                )
                if not provisioned and _provisioning_failure_should_block(message):
                    raise ApiException(
                        status_code=502,
                        code=_classify_protocol_provision_error("ikev2", message),
                        message="Failed to provision IKEv2 credential on selected server.",
                        details={"protocol": "ikev2", "reason": message, "server_id": server.server_id},
                    )
                status_message = f"eap_tls_failed_fallback_userpass: {reason}"
            else:
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
            provisioned, message = await provision_protocol_credentials_on_server(
                server=server,
                protocol="ikev2",
                username=creds.username,
                password=creds.password,
            )
            if not provisioned and _provisioning_failure_should_block(message):
                raise ApiException(
                    status_code=502,
                    code=_classify_protocol_provision_error("ikev2", message),
                    message="Failed to provision IKEv2 credential on selected server.",
                    details={"protocol": "ikev2", "reason": message, "server_id": server.server_id},
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
                reason = str(exc)
                raise ApiException(
                    status_code=502,
                    code=_classify_protocol_provision_error("openvpn", reason),
                    message="Failed to provision rotated OpenVPN certificate.",
                    details={"credential_id": credential_id, "reason": reason},
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
            provisioned, message = await provision_protocol_credentials_on_server(
                server=server,
                protocol="openvpn",
                username=creds.username,
                password=creds.password,
            )
            if not provisioned and _provisioning_failure_should_block(message):
                raise ApiException(
                    status_code=502,
                    code=_classify_protocol_provision_error("openvpn", message),
                    message="Failed to provision rotated OpenVPN credential on selected server.",
                    details={"credential_id": credential_id, "reason": message, "server_id": server.server_id},
                )
    else:
        peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == credential.device_id).first()
        rotate_device_type = (peer.device_type or "").strip().lower() if peer else None
        if _effective_ikev2_auth_mode(rotate_device_type) == "eap-tls":
            try:
                issued = await service.issue_ikev2_certificate_profile(
                    user_id=current_user.id,
                    device_id=credential.device_id,
                    server=server,
                )
            except Exception as exc:
                reason = str(exc)
                if not _ikev2_allow_userpass_fallback():
                    raise ApiException(
                        status_code=502,
                        code=_classify_protocol_provision_error("ikev2", reason),
                        message="Failed to provision rotated IKEv2 certificate.",
                        details={"credential_id": credential_id, "reason": reason},
                    )
                logger.warning(
                    "IKEv2 rotated EAP-TLS provisioning failed; falling back to EAP-MSCHAPv2 for server=%s: %s",
                    server.server_id,
                    reason,
                )
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
                provisioned, message = await provision_protocol_credentials_on_server(
                    server=server,
                    protocol="ikev2",
                    username=creds.username,
                    password=creds.password,
                )
                if not provisioned and _provisioning_failure_should_block(message):
                    raise ApiException(
                        status_code=502,
                        code=_classify_protocol_provision_error("ikev2", message),
                        message="Failed to provision rotated IKEv2 credential on selected server.",
                        details={"credential_id": credential_id, "reason": message, "server_id": server.server_id},
                    )
            else:
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
            provisioned, message = await provision_protocol_credentials_on_server(
                server=server,
                protocol="ikev2",
                username=creds.username,
                password=creds.password,
            )
            if not provisioned and _provisioning_failure_should_block(message):
                raise ApiException(
                    status_code=502,
                    code=_classify_protocol_provision_error("ikev2", message),
                    message="Failed to provision rotated IKEv2 credential on selected server.",
                    details={"credential_id": credential_id, "reason": message, "server_id": server.server_id},
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
    if is_simulated_tunnel_mode():
        runtime = get_tunnel_runtime()
        session_id = runtime.active_session_for_user(current_user.id)
        if not session_id:
            return ConnectionStatusResponse(status="DISCONNECTED", connected=False)
        _sync_simulated_usage_for_user(db, current_user.id)
        traffic = runtime.get_traffic(session_id)
        active_connection = (
            db.query(VPNConnection)
            .filter(
                VPNConnection.user_id == current_user.id,
                VPNConnection.disconnected_at.is_(None),
            )
            .order_by(VPNConnection.connected_at.desc())
            .first()
        )
        server = None
        if active_connection:
            server = db.query(VPNServer).filter(VPNServer.id == active_connection.server_id).first()
        return ConnectionStatusResponse(
            status="CONNECTED" if traffic.connected else "DISCONNECTED",
            connected=traffic.connected,
            server_id=server.server_id if server else None,
            server_location=f"{server.city}, {server.country}" if server else None,
            client_ip=active_connection.client_ip if active_connection else "10.250.0.2",
            connected_since=active_connection.connected_at.isoformat() if active_connection and active_connection.connected_at else None,
            bytes_sent=traffic.tx_bytes,
            bytes_received=traffic.rx_bytes,
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
    user_tier = get_user_tier(current_user, db)
    requested_protocol = normalize_vpn_protocol(payload.protocol)
    effective_protocol = requested_protocol if requested_protocol != "auto" else "wireguard"
    protocol_filter = requested_protocol if requested_protocol not in {"auto", "wireguard"} else None
    servers = VPNServerService.get_active_servers(db, user_tier, protocol=protocol_filter)
    health_map = _region_health_map(servers)
    up_servers = [
        item
        for item in servers
        if _region_health_status(item, health_map=health_map) == "up"
    ]
    if not up_servers and not payload.server_id:
        raise ApiException(
            status_code=503,
            code="no_servers_available",
            message="No servers available",
            details={"reason": "no_servers_available"},
        )

    server: Optional[VPNServer] = None
    if payload.server_id:
        server = VPNServerService.get_server_by_id(db, payload.server_id)
        if not server:
            raise ApiException(status_code=404, code="server_not_found", message="Server not found")
        if server.tier_restriction and user_tier == "free":
            raise ApiException(
                status_code=403,
                code="region_premium_required",
                message=f"Selected region requires a {server.tier_restriction} subscription.",
                details={
                    "server_id": server.server_id,
                    "tier_required": server.tier_restriction,
                },
            )
        selected_health = _region_health_for_server(server)
        if selected_health.get("status") != "up":
            raise ApiException(
                status_code=409,
                code="region_down",
                message="Selected region is offline.",
                details={
                    "server_id": server.server_id,
                    "reason_code": selected_health.get("reason_code"),
                },
            )
    elif payload.region:
        region_text = payload.region.strip().lower()
        for candidate in up_servers:
            if candidate.server_id.lower() == region_text:
                server = candidate
                break
        if server is None:
            for candidate in up_servers:
                values = [
                    str(candidate.region or "").lower(),
                    str(candidate.location or "").lower(),
                    str(candidate.city or "").lower(),
                ]
                if region_text and region_text in values:
                    server = candidate
                    break

    if server is None:
        preferred = VPNServerService.allocate_server_for_user(
            db,
            current_user,
            preferred_location=payload.region,
        )
        if preferred and _region_health_status(preferred, health_map=health_map) == "up":
            server = preferred
        else:
            up_servers.sort(key=lambda s: (s.performance_score or 0), reverse=True)
            server = up_servers[0]

    runtime = get_tunnel_runtime()
    if is_simulated_tunnel_mode():
        existing_session_id = runtime.active_session_for_user(current_user.id)
        if existing_session_id:
            _sync_simulated_usage_for_user(db, current_user.id)
            runtime.disconnect(existing_session_id)
        connect_result = runtime.connect(
            protocol=effective_protocol,
            region_id=server.server_id,
            user_id=current_user.id,
            device_id=None,
        )
        if not connect_result.ok:
            code = connect_result.error_code or "connect_failed"
            status_code = 409
            if code == "authentication_failed":
                status_code = 401
            elif code == "region_down":
                status_code = 409
            elif code == "protocol_unavailable":
                status_code = 409
            raise ApiException(
                status_code=status_code,
                code=code,
                message="Failed to establish simulated tunnel session.",
                details={
                    "protocol": effective_protocol,
                    "region_id": server.server_id,
                    "reason": connect_result.reason,
                },
            )

        active_connection = db.query(VPNConnection).filter(
            VPNConnection.user_id == current_user.id,
            VPNConnection.disconnected_at.is_(None)
        ).first()
        if not active_connection:
            active_connection = VPNConnection(
                user_id=current_user.id,
                server_id=server.id,
                client_ip="10.250.0.2",
                connected_at=datetime.utcnow(),
                total_bytes_sent=0,
                total_bytes_received=0,
            )
        else:
            active_connection.server_id = server.id
            active_connection.client_ip = active_connection.client_ip or "10.250.0.2"
            active_connection.connected_at = active_connection.connected_at or datetime.utcnow()
            active_connection.disconnected_at = None
        db.add(active_connection)
        db.commit()

        get_runtime_metrics().record_peer_connect()
        _log_vpn_event(
            "vpn_peer_connect",
            mode="simulated",
            user_id=current_user.id,
            server_id=server.server_id,
            session_id=connect_result.session_id,
            protocol=effective_protocol,
        )

        return {
            "mode": "simulated",
            "status": "CONNECTED",
            "region": server.region or server.location,
            "server_id": server.server_id,
            "client_ip": "10.250.0.2",
            "session_id": connect_result.session_id,
            "protocol": effective_protocol,
        }

    wg_service = WireGuardService()

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
    get_runtime_metrics().record_peer_connect()
    _log_vpn_event(
        "vpn_peer_connect",
        mode="live",
        user_id=current_user.id,
        server_id=server.server_id,
        client_ip=client_ip,
    )

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
    if is_simulated_tunnel_mode():
        runtime = get_tunnel_runtime()
        session_id = runtime.active_session_for_user(current_user.id)
        if session_id:
            _sync_simulated_usage_for_user(db, current_user.id)
            runtime.disconnect(session_id)
        active_connection = db.query(VPNConnection).filter(
            VPNConnection.user_id == current_user.id,
            VPNConnection.disconnected_at.is_(None)
        ).first()
        if active_connection:
            active_connection.disconnected_at = datetime.utcnow()
            db.add(active_connection)
            db.commit()
            get_runtime_metrics().record_peer_disconnect()
            _log_vpn_event(
                "vpn_peer_disconnect",
                mode="simulated",
                user_id=current_user.id,
                server_id=active_connection.server_id,
                session_id=session_id,
            )
        return {
            "mode": "simulated",
            "status": "DISCONNECTED",
            "disconnected_at": datetime.utcnow().isoformat(),
        }

    active_connection = db.query(VPNConnection).filter(
        VPNConnection.user_id == current_user.id,
        VPNConnection.disconnected_at.is_(None)
    ).first()

    if active_connection:
        active_connection.disconnected_at = datetime.utcnow()
        db.add(active_connection)
        db.commit()
        get_runtime_metrics().record_peer_disconnect()
        _log_vpn_event(
            "vpn_peer_disconnect",
            mode="live",
            user_id=current_user.id,
            server_id=active_connection.server_id,
        )

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
