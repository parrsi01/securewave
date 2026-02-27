"""
Tunnel runtime abstraction for real and simulated VPN sessions.

The simulated runtime is deterministic, in-memory, and never touches OS
network interfaces or subprocesses. It is intended for dev/test harnesses.
"""

from __future__ import annotations

import os
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Dict, Optional, Literal, Any

from utils.env_validation import is_production, is_testing


TunnelMode = Literal["real", "simulated"]


@dataclass(frozen=True)
class TunnelConnectResult:
    ok: bool
    session_id: Optional[str] = None
    error_code: Optional[str] = None
    reason: Optional[str] = None


@dataclass(frozen=True)
class TunnelTrafficStats:
    session_id: str
    rx_bytes: int
    tx_bytes: int
    connected: bool
    protocol: Optional[str] = None
    region_id: Optional[str] = None
    timestamp_ms: int = 0


@dataclass(frozen=True)
class TunnelTrafficDelta:
    session_id: str
    rx_delta_bytes: int
    tx_delta_bytes: int


class TunnelRuntime:
    """Interface for runtime connect/disconnect and traffic accounting."""

    mode: TunnelMode = "real"

    def connect(
        self,
        *,
        protocol: str,
        region_id: str,
        user_id: int,
        device_id: Optional[int],
    ) -> TunnelConnectResult:
        raise NotImplementedError

    def disconnect(self, session_id: str) -> bool:
        raise NotImplementedError

    def get_traffic(self, session_id: str) -> TunnelTrafficStats:
        raise NotImplementedError

    def pop_traffic_delta(self, session_id: str) -> TunnelTrafficDelta:
        raise NotImplementedError

    def health(self) -> Dict[str, Any]:
        raise NotImplementedError

    def active_session_for_user(self, user_id: int) -> Optional[str]:
        raise NotImplementedError


class RealTunnelRuntime(TunnelRuntime):
    """
    Default runtime mode.

    Real tunnel operations are still handled by existing runtime paths. This
    class only offers a lightweight session registry for a consistent API.
    """

    mode: TunnelMode = "real"

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._user_sessions: Dict[int, str] = {}
        self._sessions: Dict[str, Dict[str, Any]] = {}

    def connect(
        self,
        *,
        protocol: str,
        region_id: str,
        user_id: int,
        device_id: Optional[int],
    ) -> TunnelConnectResult:
        session_id = uuid.uuid4().hex
        now_ms = int(time.time() * 1000)
        with self._lock:
            old = self._user_sessions.get(user_id)
            if old:
                self._sessions.pop(old, None)
            self._user_sessions[user_id] = session_id
            self._sessions[session_id] = {
                "user_id": user_id,
                "device_id": device_id,
                "protocol": protocol,
                "region_id": region_id,
                "rx_bytes": 0,
                "tx_bytes": 0,
                "last_reported_rx": 0,
                "last_reported_tx": 0,
                "connected": True,
                "timestamp_ms": now_ms,
            }
        return TunnelConnectResult(ok=True, session_id=session_id, reason="connected")

    def disconnect(self, session_id: str) -> bool:
        with self._lock:
            session = self._sessions.pop(session_id, None)
            if not session:
                return False
            user_id = int(session["user_id"])
            if self._user_sessions.get(user_id) == session_id:
                self._user_sessions.pop(user_id, None)
        return True

    def get_traffic(self, session_id: str) -> TunnelTrafficStats:
        with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return TunnelTrafficStats(
                    session_id=session_id,
                    rx_bytes=0,
                    tx_bytes=0,
                    connected=False,
                    timestamp_ms=int(time.time() * 1000),
                )
            return TunnelTrafficStats(
                session_id=session_id,
                rx_bytes=int(session["rx_bytes"]),
                tx_bytes=int(session["tx_bytes"]),
                connected=bool(session["connected"]),
                protocol=str(session.get("protocol") or ""),
                region_id=str(session.get("region_id") or ""),
                timestamp_ms=int(time.time() * 1000),
            )

    def pop_traffic_delta(self, session_id: str) -> TunnelTrafficDelta:
        with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return TunnelTrafficDelta(
                    session_id=session_id,
                    rx_delta_bytes=0,
                    tx_delta_bytes=0,
                )
            rx = int(session["rx_bytes"])
            tx = int(session["tx_bytes"])
            prev_rx = int(session["last_reported_rx"])
            prev_tx = int(session["last_reported_tx"])
            session["last_reported_rx"] = rx
            session["last_reported_tx"] = tx
        return TunnelTrafficDelta(
            session_id=session_id,
            rx_delta_bytes=max(0, rx - prev_rx),
            tx_delta_bytes=max(0, tx - prev_tx),
        )

    def health(self) -> Dict[str, Any]:
        with self._lock:
            active = len(self._sessions)
        return {"mode": self.mode, "status": "ok", "active_sessions": active}

    def active_session_for_user(self, user_id: int) -> Optional[str]:
        with self._lock:
            return self._user_sessions.get(user_id)


class SimulatedTunnelRuntime(TunnelRuntime):
    """
    Deterministic in-memory runtime for dev/test.
    """

    mode: TunnelMode = "simulated"

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._sessions: Dict[str, Dict[str, Any]] = {}
        self._user_sessions: Dict[int, str] = {}
        self._blocked_regions: set[str] = set()
        self._blocked_protocols: set[str] = set()
        self._auth_failure = False
        self._default_rx_rate = int(os.getenv("SECUREWAVE_SIM_RX_RATE_BYTES_PER_SEC", "65536"))
        self._default_tx_rate = int(os.getenv("SECUREWAVE_SIM_TX_RATE_BYTES_PER_SEC", "32768"))

    def _tick_locked(self, session: Dict[str, Any]) -> None:
        now = time.monotonic()
        elapsed = max(0.0, now - float(session["last_tick"]))
        if elapsed <= 0:
            return
        rx_inc = int(float(session["rx_rate"]) * elapsed)
        tx_inc = int(float(session["tx_rate"]) * elapsed)
        session["rx_bytes"] = int(session["rx_bytes"]) + max(0, rx_inc)
        session["tx_bytes"] = int(session["tx_bytes"]) + max(0, tx_inc)
        session["last_tick"] = now

    def connect(
        self,
        *,
        protocol: str,
        region_id: str,
        user_id: int,
        device_id: Optional[int],
    ) -> TunnelConnectResult:
        normalized_protocol = (protocol or "").strip().lower() or "wireguard"
        normalized_region = (region_id or "").strip().lower()

        with self._lock:
            if self._auth_failure:
                return TunnelConnectResult(
                    ok=False,
                    error_code="authentication_failed",
                    reason="simulated_auth_failure",
                )
            if normalized_protocol in self._blocked_protocols:
                return TunnelConnectResult(
                    ok=False,
                    error_code="protocol_unavailable",
                    reason="simulated_protocol_unavailable",
                )
            if normalized_region and normalized_region in self._blocked_regions:
                return TunnelConnectResult(
                    ok=False,
                    error_code="region_down",
                    reason="simulated_region_down",
                )

            old = self._user_sessions.get(user_id)
            if old:
                self._sessions.pop(old, None)

            session_id = uuid.uuid4().hex
            now_mono = time.monotonic()
            self._user_sessions[user_id] = session_id
            self._sessions[session_id] = {
                "user_id": user_id,
                "device_id": device_id,
                "protocol": normalized_protocol,
                "region_id": region_id,
                "rx_bytes": 0,
                "tx_bytes": 0,
                "rx_rate": self._default_rx_rate,
                "tx_rate": self._default_tx_rate,
                "last_tick": now_mono,
                "last_reported_rx": 0,
                "last_reported_tx": 0,
                "connected": True,
            }
        return TunnelConnectResult(ok=True, session_id=session_id, reason="simulated_connected")

    def disconnect(self, session_id: str) -> bool:
        with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return False
            self._tick_locked(session)
            self._sessions.pop(session_id, None)
            user_id = int(session["user_id"])
            if self._user_sessions.get(user_id) == session_id:
                self._user_sessions.pop(user_id, None)
        return True

    def get_traffic(self, session_id: str) -> TunnelTrafficStats:
        with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return TunnelTrafficStats(
                    session_id=session_id,
                    rx_bytes=0,
                    tx_bytes=0,
                    connected=False,
                    timestamp_ms=int(time.time() * 1000),
                )
            self._tick_locked(session)
            return TunnelTrafficStats(
                session_id=session_id,
                rx_bytes=int(session["rx_bytes"]),
                tx_bytes=int(session["tx_bytes"]),
                connected=bool(session["connected"]),
                protocol=str(session.get("protocol") or ""),
                region_id=str(session.get("region_id") or ""),
                timestamp_ms=int(time.time() * 1000),
            )

    def pop_traffic_delta(self, session_id: str) -> TunnelTrafficDelta:
        with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return TunnelTrafficDelta(
                    session_id=session_id,
                    rx_delta_bytes=0,
                    tx_delta_bytes=0,
                )
            self._tick_locked(session)
            rx = int(session["rx_bytes"])
            tx = int(session["tx_bytes"])
            prev_rx = int(session["last_reported_rx"])
            prev_tx = int(session["last_reported_tx"])
            session["last_reported_rx"] = rx
            session["last_reported_tx"] = tx
        return TunnelTrafficDelta(
            session_id=session_id,
            rx_delta_bytes=max(0, rx - prev_rx),
            tx_delta_bytes=max(0, tx - prev_tx),
        )

    def health(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "mode": self.mode,
                "status": "ok",
                "active_sessions": len(self._sessions),
                "blocked_protocols": sorted(self._blocked_protocols),
                "blocked_regions": sorted(self._blocked_regions),
                "auth_failure": self._auth_failure,
            }

    def active_session_for_user(self, user_id: int) -> Optional[str]:
        with self._lock:
            return self._user_sessions.get(user_id)

    def set_traffic_rate(self, session_id: str, *, rx_rate: Optional[int], tx_rate: Optional[int]) -> bool:
        with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return False
            self._tick_locked(session)
            if rx_rate is not None:
                session["rx_rate"] = max(0, int(rx_rate))
            if tx_rate is not None:
                session["tx_rate"] = max(0, int(tx_rate))
        return True

    def inject_traffic(self, session_id: str, *, rx_bytes: int, tx_bytes: int) -> bool:
        with self._lock:
            session = self._sessions.get(session_id)
            if not session:
                return False
            self._tick_locked(session)
            session["rx_bytes"] = int(session["rx_bytes"]) + max(0, int(rx_bytes))
            session["tx_bytes"] = int(session["tx_bytes"]) + max(0, int(tx_bytes))
        return True

    def set_failure_modes(
        self,
        *,
        auth_failure: Optional[bool] = None,
        blocked_regions: Optional[list[str]] = None,
        blocked_protocols: Optional[list[str]] = None,
    ) -> None:
        with self._lock:
            if auth_failure is not None:
                self._auth_failure = bool(auth_failure)
            if blocked_regions is not None:
                self._blocked_regions = {
                    item.strip().lower() for item in blocked_regions if item and item.strip()
                }
            if blocked_protocols is not None:
                self._blocked_protocols = {
                    item.strip().lower() for item in blocked_protocols if item and item.strip()
                }


_RUNTIME_LOCK = threading.Lock()
_RUNTIME_INSTANCE: Optional[TunnelRuntime] = None
_RUNTIME_MODE: Optional[TunnelMode] = None


def _bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def ensure_tunnel_mode_allowed(*, mode: Optional[str] = None) -> TunnelMode:
    raw_mode = (mode or os.getenv("SECUREWAVE_TUNNEL_MODE", "real")).strip().lower()
    resolved: TunnelMode = "simulated" if raw_mode == "simulated" else "real"
    if resolved != "simulated":
        return resolved
    if is_testing():
        return resolved
    if is_production():
        raise RuntimeError(
            "SECUREWAVE_TUNNEL_MODE=simulated is forbidden in production."
        )
    if not _bool_env("SECUREWAVE_ALLOW_DEV_SIMULATED_TUNNEL_MODE", False):
        raise RuntimeError(
            "SECUREWAVE_TUNNEL_MODE=simulated requires "
            "SECUREWAVE_ALLOW_DEV_SIMULATED_TUNNEL_MODE=1 outside tests."
        )
    return resolved


def tunnel_mode() -> TunnelMode:
    return ensure_tunnel_mode_allowed()


def is_simulated_tunnel_mode() -> bool:
    return tunnel_mode() == "simulated"


def get_tunnel_runtime() -> TunnelRuntime:
    global _RUNTIME_INSTANCE, _RUNTIME_MODE
    mode = tunnel_mode()
    with _RUNTIME_LOCK:
        if _RUNTIME_INSTANCE is not None and _RUNTIME_MODE == mode:
            return _RUNTIME_INSTANCE
        if mode == "simulated":
            _RUNTIME_INSTANCE = SimulatedTunnelRuntime()
            _RUNTIME_MODE = "simulated"
        else:
            _RUNTIME_INSTANCE = RealTunnelRuntime()
            _RUNTIME_MODE = "real"
        return _RUNTIME_INSTANCE


def reset_tunnel_runtime_for_tests() -> None:
    global _RUNTIME_INSTANCE, _RUNTIME_MODE
    with _RUNTIME_LOCK:
        _RUNTIME_INSTANCE = None
        _RUNTIME_MODE = None
