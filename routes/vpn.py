"""Minimal WireGuard API used by the Linux SecureWave app.

This module intentionally exposes one product path:

- create or reuse an account-owned WireGuard device
- register that peer on a real server before returning private-key config
- record client-reported session usage while the app is open
- mark active sessions disconnected on logout/disconnect
"""

import asyncio
import base64
import binascii
import ipaddress
import os
import re
import signal
from datetime import datetime, timedelta
from typing import Optional, Literal
from urllib.parse import urlsplit

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, or_
from sqlalchemy.exc import IntegrityError
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
from services.vpn_peer_manager import IP_POOL_END, IP_POOL_START, get_peer_manager
from services.vpn_server_service import VPNServerService
from services import wireguard_helper_client
from services.routing_shadow import observe_selection
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
_WG_INTERFACE = "wg0"
_LOCAL_COMMAND_TIMEOUT_SECONDS = 10


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


class ClientWireGuardConfigRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    public_key: str = Field(..., min_length=44, max_length=44)


class ClientWireGuardConfigResponse(BaseModel):
    wireguard_config: str
    server_location: str
    device_id: int
    server_id: str


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
    metering_version: Literal[1, 2] = 1
    reporting_token: Optional[str] = Field(None, pattern=r"^[0-9a-f]{64}$")


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


def _observe_routing(candidates, baseline, *, explicit=False):
    # An advisory experiment must never become a provisioning dependency.
    try:
        observe_selection(candidates, baseline, explicit=explicit)
    except Exception:
        pass


def _select_server(db: Session, user: User, server_id: Optional[str]) -> VPNServer:
    candidates = _active_wireguard_servers(db, user)
    if server_id:
        server = VPNServerService.get_server_by_id(db, server_id)
        if server is None or server not in candidates:
            raise HTTPException(status_code=404, detail="WireGuard server not found")
        _observe_routing(candidates, server, explicit=True)
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
    baseline = candidates[0]
    _observe_routing(candidates, baseline)
    return baseline


def _is_wireguard_public_key(value: str) -> bool:
    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError):
        return False
    return (
        len(decoded) == 32
        and any(decoded)
        and base64.b64encode(decoded).decode("ascii") == value
    )


def _client_wireguard_config(server: VPNServer, address: str) -> tuple[str, str]:
    if not _is_wireguard_public_key(server.wg_public_key or ""):
        raise HTTPException(status_code=503, detail="WireGuard server public key is unavailable.")
    endpoint = (server.endpoint or "").strip()
    if not re.fullmatch(
        r"(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\]):[1-9][0-9]{0,4}",
        endpoint,
    ):
        raise HTTPException(status_code=503, detail="WireGuard server endpoint is unavailable.")
    try:
        parsed = urlsplit(f"udp://{endpoint}")
        port = parsed.port
    except ValueError:
        parsed = None
        port = None
    hostname = parsed.hostname if parsed else None
    if (
        not hostname
        or port is None
        or not 1 <= port <= 65535
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path
        or parsed.query
        or parsed.fragment
    ):
        raise HTTPException(status_code=503, detail="WireGuard server endpoint is unavailable.")
    try:
        ipaddress.ip_address(hostname)
    except ValueError:
        labels = hostname.rstrip(".").split(".")
        if not labels or any(
            not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
            for label in labels
        ):
            raise HTTPException(status_code=503, detail="WireGuard server endpoint is unavailable.")
    try:
        client_interface = ipaddress.ip_interface(address)
        if client_interface.version != 4 or client_interface.network.prefixlen != 32:
            raise ValueError
        allowed_ips = [
            str(ipaddress.ip_network(item.strip(), strict=False))
            for item in (server.allowed_ips or "").split(",")
            if item.strip()
        ]
        if not allowed_ips:
            raise ValueError
        dns_servers = [
            str(ipaddress.ip_address(item.strip()))
            for item in (server.dns_servers or "").split(",")
            if item.strip()
        ]
    except ValueError as exc:
        raise HTTPException(
            status_code=503, detail="WireGuard network settings are invalid."
        ) from exc
    lines = ["[Interface]", f"Address = {client_interface}"]
    if dns_servers:
        lines.append(f"DNS = {','.join(dns_servers)}")
    lines.extend(
        [
            "",
            "[Peer]",
            f"PublicKey = {server.wg_public_key}",
            f"Endpoint = {endpoint}",
            f"AllowedIPs = {', '.join(allowed_ips)}",
        ]
    )
    try:
        keepalive = int(os.getenv("SECUREWAVE_WG_KEEPALIVE", "25"))
    except ValueError as exc:
        raise HTTPException(
            status_code=503, detail="WireGuard keepalive settings are invalid."
        ) from exc
    if not 0 <= keepalive <= 3600:
        raise HTTPException(
            status_code=503, detail="WireGuard keepalive settings are invalid."
        )
    if keepalive > 0:
        lines.append(f"PersistentKeepalive = {keepalive}")
    location = ", ".join(
        part.strip() for part in (server.city, server.country) if part and part.strip()
    ) or (server.location or "").strip()
    if not location or "\n" in location or "\r" in location:
        raise HTTPException(status_code=503, detail="WireGuard server location is unavailable.")
    return "\n".join(lines) + "\n", location


async def _reserve_client_peer(
    db: Session,
    user: User,
    public_key: str,
) -> tuple[WireGuardPeer, VPNServer, str, str]:
    peer = db.query(WireGuardPeer).filter(WireGuardPeer.public_key == public_key).first()
    if peer is not None:
        if peer.user_id != user.id:
            raise HTTPException(status_code=409, detail="WireGuard public key is already assigned.")
        if peer.is_revoked:
            raise HTTPException(status_code=409, detail="This WireGuard public key has been revoked.")
        if peer.private_key_encrypted:
            raise HTTPException(
                status_code=409,
                detail="Use a fresh client-generated WireGuard key for provisioning.",
            )
        server = (
            db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
            if peer.server_id
            else _select_server(db, user, None)
        )
        if not server or not _wireguard_ready(server):
            raise HTTPException(status_code=503, detail="The WireGuard server is unavailable.")
        config, location = _client_wireguard_config(server, peer.ipv4_address)
        return peer, server, config, location

    for attempt in range(3):
        db.query(User).filter(User.id == user.id).with_for_update().first()
        server = _select_server(db, user, None)
        locked_server = (
            db.query(VPNServer)
            .filter(VPNServer.id == server.id)
            .with_for_update()
            .first()
        )
        if not locked_server or not _wireguard_ready(locked_server):
            db.rollback()
            raise HTTPException(status_code=503, detail="The WireGuard server is unavailable.")
        server = locked_server

        # A concurrent request for the same key may have completed while this
        # request waited for the per-server allocation lock.
        peer = db.query(WireGuardPeer).filter(WireGuardPeer.public_key == public_key).first()
        if peer is not None:
            db.rollback()
            if peer.user_id != user.id or peer.private_key_encrypted or peer.is_revoked:
                raise HTTPException(status_code=409, detail="WireGuard public key is already assigned.")
            server = (
                db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
                if peer.server_id
                else server
            )
            if not server or not _wireguard_ready(server):
                raise HTTPException(status_code=503, detail="The WireGuard server is unavailable.")
            config, location = _client_wireguard_config(server, peer.ipv4_address)
            return peer, server, config, location

        try:
            live_state = await wireguard_helper_client.inspect_state()
        except wireguard_helper_client.WireGuardHelperError as exc:
            db.rollback()
            raise HTTPException(
                status_code=503, detail="Live WireGuard peer state is unavailable."
            ) from exc
        if (
            live_state.get("server_public_key") != server.wg_public_key
            or live_state.get("listen_port") != server.wg_listen_port
        ):
            db.rollback()
            raise HTTPException(status_code=503, detail="The WireGuard server is unavailable.")
        live_peers = _parse_wireguard_peer_state(live_state.get("peers"))
        if live_peers is None:
            db.rollback()
            raise HTTPException(status_code=503, detail="Live WireGuard peer state is invalid.")
        if public_key in live_peers:
            db.rollback()
            raise HTTPException(
                status_code=409,
                detail="WireGuard public key is already assigned outside this account.",
            )
        live_networks = {
            network
            for networks in live_peers.values()
            for network in networks
            if network.version == 4
        }

        allocated = (raw for (raw,) in db.query(WireGuardPeer.ipv4_address).all() if raw)
        try:
            used_networks = {
                ipaddress.ip_interface(raw).network for raw in allocated
            }
        except ValueError as exc:
            raise HTTPException(
                status_code=503, detail="WireGuard address allocation data is invalid."
            ) from exc

        device_count = (
            db.query(WireGuardPeer)
            .filter(
                WireGuardPeer.user_id == user.id,
                WireGuardPeer.is_revoked.is_(False),
                or_(WireGuardPeer.is_active.is_(True), WireGuardPeer.private_key_encrypted == ""),
            )
            .count()
        )
        if device_count >= get_effective_device_limit(db, user):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Device limit reached. Reuse or revoke an existing device.",
            )
        address = next(
            (
                f"{IP_POOL_START}.{host}/32"
                for host in range(10, IP_POOL_END + 1)
                if not any(
                    ipaddress.ip_address(f"{IP_POOL_START}.{host}") in network
                    for network in used_networks | live_networks
                )
            ),
            None,
        )
        if address is None:
            raise HTTPException(
                status_code=503, detail="No WireGuard client addresses are available."
            )
        peer = WireGuardPeer(
            user_id=user.id,
            server_id=server.id,
            public_key=public_key,
            private_key_encrypted="",
            ipv4_address=address,
            device_type="linux-client-owned", is_active=False, is_revoked=False,
        )
        config, location = _client_wireguard_config(server, address)
        db.add(peer)
        try:
            db.commit()
            db.refresh(peer)
            return peer, server, config, location
        except IntegrityError:
            db.rollback()
            peer = db.query(WireGuardPeer).filter(WireGuardPeer.public_key == public_key).first()
            if peer is not None:
                if peer.user_id != user.id or peer.private_key_encrypted or peer.is_revoked:
                    raise HTTPException(status_code=409, detail="WireGuard public key is already assigned.")
                server = (
                    db.query(VPNServer).filter(VPNServer.id == peer.server_id).first()
                    if peer.server_id
                    else server
                )
                if not server or not _wireguard_ready(server):
                    raise HTTPException(status_code=503, detail="The WireGuard server is unavailable.")
                config, location = _client_wireguard_config(server, peer.ipv4_address)
                return peer, server, config, location
            if attempt == 2:
                raise HTTPException(
                    status_code=503,
                    detail="A unique WireGuard client address could not be reserved.",
                )
    raise HTTPException(
        status_code=503,
        detail="A unique WireGuard client address could not be reserved.",
    )


async def _run_local_command(
    command: tuple[str, ...],
) -> tuple[bool, str]:
    try:
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            start_new_session=True,
        )
    except (OSError, asyncio.SubprocessError):
        return False, ""

    try:
        stdout, _ = await asyncio.wait_for(
            process.communicate(), timeout=_LOCAL_COMMAND_TIMEOUT_SECONDS
        )
    except asyncio.TimeoutError:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        await process.communicate()
        return False, ""
    except asyncio.CancelledError:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        await asyncio.shield(process.wait())
        raise
    if process.returncode != 0:
        return False, ""
    return True, stdout.decode("utf-8", errors="replace").strip()


def _parse_wireguard_peer_state(raw_peers: object) -> Optional[dict[str, set]]:
    if not isinstance(raw_peers, dict):
        return None
    peers: dict[str, set] = {}
    for public_key, raw_allowed_ips in raw_peers.items():
        if (
            not _is_wireguard_public_key(public_key)
            or public_key in peers
            or not isinstance(raw_allowed_ips, list)
            or any(not isinstance(item, str) for item in raw_allowed_ips)
        ):
            return None
        networks = set()
        if raw_allowed_ips:
            try:
                parsed_networks = [
                    ipaddress.ip_network(item, strict=False)
                    for item in raw_allowed_ips
                ]
                if len(parsed_networks) != len(set(parsed_networks)):
                    return None
                networks = set(parsed_networks)
            except ValueError:
                return None
        peers[public_key] = networks
    return peers


def _wireguard_peer_has_conflicting_address(
    peers: dict[str, set],
    public_key: str,
    client_network: ipaddress.IPv4Network,
) -> bool:
    for existing_key, networks in peers.items():
        if existing_key == public_key:
            if networks != {client_network}:
                return True
            continue
        if any(
            network.version == 4 and network.overlaps(client_network)
            for network in networks
        ):
            return True
    return False


async def _register_client_owned_peer(server: VPNServer, peer: WireGuardPeer) -> bool:
    if not AUTO_REGISTER_PEERS or not _is_wireguard_public_key(peer.public_key or ""):
        return False
    if not _is_wireguard_public_key(server.wg_public_key or ""):
        return False

    try:
        server_address = ipaddress.ip_address(server.public_ip)
        client_interface = ipaddress.ip_interface(peer.ipv4_address)
        client_ip = client_interface.ip
        listen_port = int(server.wg_listen_port or 0)
        pool = ipaddress.ip_network(f"{IP_POOL_START}.0/24")
    except (TypeError, ValueError):
        return False
    if (
        server_address.version != 4
        or client_interface.version != 4
        or client_interface.network.prefixlen != 32
        or client_ip not in pool
        or not 10 <= int(str(client_ip).rsplit(".", 1)[1]) <= IP_POOL_END
        or not 1 <= listen_port <= 65535
    ):
        return False
    client_network = client_interface.network

    success, route = await _run_local_command(
        ("/usr/sbin/ip", "-4", "route", "get", "1.1.1.1")
    )
    if not success:
        return False
    route_columns = route.split()
    try:
        source = ipaddress.ip_address(route_columns[route_columns.index("src") + 1])
    except (ValueError, IndexError):
        return False
    if source != server_address:
        return False

    success, interface_addresses = await _run_local_command(
        ("/usr/sbin/ip", "-4", "address", "show", "dev", _WG_INTERFACE)
    )
    if not success:
        return False
    raw_interface_addresses = re.findall(r"(?m)^\s*inet\s+(\S+)", interface_addresses)
    if len(raw_interface_addresses) != 1:
        return False
    try:
        interface_address = ipaddress.ip_interface(raw_interface_addresses[0])
    except ValueError:
        return False
    if (
        interface_address.version != 4
        or client_ip not in interface_address.network
        or client_ip == interface_address.ip
    ):
        return False

    try:
        current_state = await wireguard_helper_client.inspect_state()
    except wireguard_helper_client.WireGuardHelperError:
        return False
    if (
        current_state.get("server_public_key") != server.wg_public_key
        or current_state.get("listen_port") != listen_port
    ):
        return False
    peers = _parse_wireguard_peer_state(current_state.get("peers"))
    if peers is None or _wireguard_peer_has_conflicting_address(
        peers, peer.public_key, client_network
    ):
        return False

    added = False
    if peer.public_key not in peers:
        added = True
    try:
        await wireguard_helper_client.ensure_peer(peer.public_key, str(client_network))
        verified_state = await wireguard_helper_client.inspect_state()
    except wireguard_helper_client.WireGuardHelperError:
        return False
    if (
        verified_state.get("server_public_key") != server.wg_public_key
        or verified_state.get("listen_port") != listen_port
    ):
        if added:
            try:
                await wireguard_helper_client.remove_peer(
                    peer.public_key, str(client_network)
                )
            except wireguard_helper_client.WireGuardHelperError:
                pass
        return False
    peers = _parse_wireguard_peer_state(verified_state.get("peers"))
    if (
        peers is None
        or peer.public_key not in peers
        or peers[peer.public_key] != {client_network}
        or _wireguard_peer_has_conflicting_address(peers, peer.public_key, client_network)
    ):
        if added:
            try:
                await wireguard_helper_client.remove_peer(
                    peer.public_key, str(client_network)
                )
            except wireguard_helper_client.WireGuardHelperError:
                pass
        return False

    return True


async def _remove_client_owned_peer(public_key: str, address: str) -> bool:
    if not _is_wireguard_public_key(public_key):
        return False
    try:
        await wireguard_helper_client.remove_peer(public_key, address)
    except wireguard_helper_client.WireGuardHelperError:
        return False
    return True


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
        if not peer.private_key_encrypted:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This device uses a client-owned WireGuard key; request its configuration through POST /api/vpn/config.",
            )
        return peer

    device_name = (payload.device_name or "Linux VM").strip()[:64]
    peer = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user.id,
            func.lower(WireGuardPeer.device_name) == device_name.lower(),
            WireGuardPeer.is_revoked.is_(False),
            WireGuardPeer.private_key_encrypted != "",
        )
        .first()
    )
    if peer is not None:
        return peer

    query = db.query(WireGuardPeer).filter(
        WireGuardPeer.user_id == user.id,
        WireGuardPeer.is_active.is_(True),
        WireGuardPeer.is_revoked.is_(False),
        WireGuardPeer.private_key_encrypted != "",
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


@router.post("/config", response_model=ClientWireGuardConfigResponse)
@rate_limit("30/minute")
async def provision_client_wireguard_config(
    request: Request,
    payload: ClientWireGuardConfigRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not _is_wireguard_public_key(payload.public_key):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="A valid WireGuard public key is required.",
        )

    await require_active_subscription(db, current_user)
    peer, server, config, location = await _reserve_client_peer(
        db, current_user, payload.public_key
    )

    try:
        registered = await _register_client_owned_peer(server, peer)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="WireGuard peer registration could not be confirmed.",
        ) from exc
    if not registered:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="WireGuard peer registration could not be confirmed.",
        )

    if not peer.is_active:
        peer.is_active = True
        db.add(peer)
        try:
            db.commit()
            db.refresh(peer)
        except Exception as exc:
            db.rollback()
            try:
                await _remove_client_owned_peer(peer.public_key, peer.ipv4_address)
            except Exception:
                pass
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="WireGuard peer activation could not be saved.",
            ) from exc

    return ClientWireGuardConfigResponse(
        wireguard_config=config,
        server_location=location,
        device_id=peer.id,
        server_id=server.server_id,
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
    if peer.private_key_encrypted == "":
        # Client-owned keys are provisioned by the local privileged helper.
        # The legacy peer manager creates a server-key directory during its
        # construction and cannot run inside the API's read-only sandbox.
        device_id = peer.id
        try:
            initial_state = await wireguard_helper_client.inspect_state()
            if (
                peer.server is None
                or initial_state.get("server_public_key") != peer.server.wg_public_key
                or initial_state.get("listen_port") != peer.server.wg_listen_port
                or _parse_wireguard_peer_state(initial_state.get("peers")) is None
            ):
                raise WireGuardPeerSyncError("Client-owned server identity was not verified.")
            if not await _remove_client_owned_peer(peer.public_key, peer.ipv4_address):
                raise WireGuardPeerSyncError("Client-owned peer removal failed.")
            state = await wireguard_helper_client.inspect_state()
            remaining = _parse_wireguard_peer_state(state.get("peers"))
            if (
                peer.server is None
                or state.get("server_public_key") != peer.server.wg_public_key
                or state.get("listen_port") != peer.server.wg_listen_port
                or remaining is None
                or peer.public_key in remaining
            ):
                raise WireGuardPeerSyncError("Client-owned peer removal was not verified.")
            peer.is_revoked = True
            peer.is_active = False
            peer.revoked_at = datetime.utcnow()
            db.commit()
        except Exception as exc:
            try:
                db.rollback()
            except Exception:
                pass
            raise HTTPException(
                status_code=503,
                detail="WireGuard peer removal could not be confirmed.",
            ) from exc
        return {"device_id": device_id, "status": "revoked"}
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
        "metering_version": connection.metering_version,
        "recording_quality": connection.recording_quality,
        "finalization_reason": connection.finalization_reason,
        "client_verified_at": connection.client_verified_at.isoformat() if connection.client_verified_at else None,
        "final_sequence": connection.final_meter_sequence,
    }


@router.post("/usage/sessions/start")
async def start_usage_session(
    payload: UsageSessionStartRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _normalize_wireguard(payload.protocol)
    if (payload.metering_version == 2) != (payload.reporting_token is not None):
        raise HTTPException(status_code=422, detail="Version 2 requires a session reporting token.")
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
            metering_version=payload.metering_version,
            reporting_token=payload.reporting_token,
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


# Keep the existing app router registration and its production URL unchanged.
from routes.usage_recording import router as usage_recording_router
router.include_router(usage_recording_router)
