"""
Tunnel self-healing watchdog for WireGuard servers.

This is a backend-side reliability layer that monitors:
- handshake staleness (DB + remote)
- interface disappearance (remote wg health check)
- tunnel "stuck" states (no transfer progress over multiple cycles)

When a stuck/unhealthy condition is detected, it attempts a best-effort restart
of the WireGuard interface on the VPN node, using bounded retries with
exponential backoff + jitter to avoid storms.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import random
import time
from collections import deque
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Deque, Dict, Optional

from sqlalchemy.orm import Session

from database.session import SessionLocal
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.wireguard_server_manager import get_wireguard_server_manager, server_connection_from_db

logger = logging.getLogger(__name__)


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name, str(default)).strip()
    try:
        return int(raw)
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name, str(default)).strip()
    try:
        return float(raw)
    except ValueError:
        return default


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _utc_now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"


class WatchdogEventWriter:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = asyncio.Lock()
        self.path.parent.mkdir(parents=True, exist_ok=True)

    async def write(self, payload: dict) -> None:
        line = json.dumps(payload, sort_keys=True)
        async with self._lock:
            # Append JSONL line.
            with self.path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")


@dataclass
class _ServerState:
    attempts: Deque[float]
    consecutive_failures: int = 0
    next_allowed_at: float = 0.0
    last_total_transfer: int = 0
    stuck_cycles: int = 0


class TunnelWatchdog:
    def __init__(self) -> None:
        self.enabled = _env_bool("SECUREWAVE_WATCHDOG_ENABLED", True)
        self.interval_seconds = max(5, _env_int("SECUREWAVE_WATCHDOG_INTERVAL_SECONDS", 20))
        self.interface = os.getenv("SECUREWAVE_WATCHDOG_INTERFACE", "wg0").strip() or "wg0"

        # Staleness thresholds (reuse the same env vars as the health monitor).
        self.degraded_handshake_seconds = _env_int("WG_HANDSHAKE_DEGRADED_SECONDS", 120)
        self.unstable_handshake_seconds = _env_int("WG_HANDSHAKE_UNSTABLE_SECONDS", 300)

        # Retry storm protection.
        self.window_seconds = max(60, _env_int("SECUREWAVE_WATCHDOG_ACTION_WINDOW_SECONDS", 10 * 60))
        self.max_actions_per_window = max(1, _env_int("SECUREWAVE_WATCHDOG_MAX_ACTIONS_PER_WINDOW", 3))
        self.backoff_base_seconds = max(1.0, _env_float("SECUREWAVE_WATCHDOG_BACKOFF_BASE_SECONDS", 10.0))
        self.backoff_max_seconds = max(self.backoff_base_seconds, _env_float("SECUREWAVE_WATCHDOG_BACKOFF_MAX_SECONDS", 300.0))
        self.jitter_fraction = min(0.9, max(0.0, _env_float("SECUREWAVE_WATCHDOG_JITTER_FRACTION", 0.25)))

        self.stuck_required_cycles = max(2, _env_int("SECUREWAVE_WATCHDOG_STUCK_CYCLES", 3))

        self.is_running = False
        self._states: Dict[str, _ServerState] = {}
        self._rng = random.Random()

        out_path = Path(os.getenv("SECUREWAVE_WATCHDOG_EVENTS_PATH", "artifacts/watchdog/watchdog_events.jsonl"))
        self._events = WatchdogEventWriter(out_path)

    async def start(self) -> None:
        if not self.enabled:
            logger.info("TunnelWatchdog disabled (SECUREWAVE_WATCHDOG_ENABLED=false)")
            return

        self.is_running = True
        await self._events.write(
            {
                "timestamp": _utc_now_iso(),
                "event": "watchdog_start",
                "interval_seconds": self.interval_seconds,
                "window_seconds": self.window_seconds,
                "max_actions_per_window": self.max_actions_per_window,
                "interface": self.interface,
            }
        )
        logger.info("TunnelWatchdog started (interval=%ss)", self.interval_seconds)

        while self.is_running:
            db: Optional[Session] = None
            try:
                db = SessionLocal()
                await self._check_servers(db)
            except Exception as exc:
                logger.warning("TunnelWatchdog loop error: %s", exc)
            finally:
                if db:
                    db.close()
            await asyncio.sleep(self.interval_seconds)

        await self._events.write({"timestamp": _utc_now_iso(), "event": "watchdog_stop"})
        logger.info("TunnelWatchdog stopped")

    async def stop(self) -> None:
        self.is_running = False

    def _state_for(self, server_id: str) -> _ServerState:
        state = self._states.get(server_id)
        if state is None:
            state = _ServerState(attempts=deque())
            self._states[server_id] = state
        return state

    async def _check_servers(self, db: Session) -> None:
        servers = (
            db.query(VPNServer)
            .filter(VPNServer.status.in_(["active"]))
            .all()
        )
        if not servers:
            return

        manager = get_wireguard_server_manager()

        # Avoid thundering herd across multiple servers within a single loop.
        for server in servers:
            await self._check_one(db, manager, server)
            await asyncio.sleep(self._rng.uniform(0.0, 0.4))

    async def _check_one(self, db: Session, manager, server: VPNServer) -> None:
        server_id = server.server_id
        health_status = (server.health_status or "unknown").strip().lower()
        state = self._state_for(server_id)

        # DB-side handshake staleness signal.
        now = datetime.utcnow()
        peers = (
            db.query(WireGuardPeer)
            .filter(
                WireGuardPeer.server_id == server.id,
                WireGuardPeer.is_revoked == False,
                WireGuardPeer.is_active == True,
            )
            .all()
        )

        stale_peers = 0
        max_age_s: Optional[float] = None
        for peer in peers:
            if not peer.last_handshake_at:
                stale_peers += 1
                max_age_s = max(max_age_s or 0.0, float(self.unstable_handshake_seconds) + 1.0)
                continue
            age = max(0.0, (now - peer.last_handshake_at).total_seconds())
            if age > self.unstable_handshake_seconds:
                stale_peers += 1
            max_age_s = age if max_age_s is None else max(max_age_s, age)

        handshake_state = "healthy"
        if peers and (max_age_s or 0.0) > self.unstable_handshake_seconds:
            handshake_state = "unstable"
        elif peers and (max_age_s or 0.0) > self.degraded_handshake_seconds:
            handshake_state = "degraded"

        # Remote-side interface health.
        interface_ok = None
        interface_msg = ""
        try:
            conn = server_connection_from_db(server)
            ok, msg = await manager.health_check(conn)
            interface_ok = bool(ok)
            interface_msg = msg
        except Exception as exc:
            interface_ok = False
            interface_msg = str(exc)

        needs_restart = False
        reason = None

        if interface_ok is False:
            needs_restart = True
            reason = "interface_missing_or_unhealthy"

        # Only do heavier "stuck" checks when something already looks wrong.
        if not needs_restart and (health_status in {"degraded", "unstable", "unhealthy", "unreachable"} or handshake_state in {"degraded", "unstable"}):
            total_transfer = 0
            try:
                conn = server_connection_from_db(server)
                ok, remote_peers = await manager.list_peers(conn)
                if ok:
                    for item in remote_peers:
                        # Never log peer keys; aggregate only.
                        total_transfer += int(item.get("transfer_rx", 0) or 0)
                        total_transfer += int(item.get("transfer_tx", 0) or 0)
            except Exception:
                total_transfer = state.last_total_transfer

            if total_transfer <= state.last_total_transfer and peers and handshake_state == "unstable":
                state.stuck_cycles += 1
            else:
                state.stuck_cycles = 0

            state.last_total_transfer = max(state.last_total_transfer, total_transfer)

            if state.stuck_cycles >= self.stuck_required_cycles:
                needs_restart = True
                reason = "tunnel_stuck_no_transfer_progress"

        if needs_restart:
            await self._maybe_restart(
                db,
                manager,
                server,
                state=state,
                reason=reason or "unknown",
                health_status=health_status,
                handshake_state=handshake_state,
                stale_peers=stale_peers,
                max_handshake_age_s=max_age_s,
                interface_ok=interface_ok,
                interface_msg=interface_msg,
            )

    def _prune_attempts(self, state: _ServerState, now: float) -> None:
        cutoff = now - float(self.window_seconds)
        while state.attempts and state.attempts[0] < cutoff:
            state.attempts.popleft()

    def _compute_backoff(self, *, failures: int) -> float:
        backoff = self.backoff_base_seconds * (2 ** max(0, failures))
        return min(self.backoff_max_seconds, backoff)

    async def _maybe_restart(
        self,
        db: Session,
        manager,
        server: VPNServer,
        *,
        state: _ServerState,
        reason: str,
        health_status: str,
        handshake_state: str,
        stale_peers: int,
        max_handshake_age_s: Optional[float],
        interface_ok: Optional[bool],
        interface_msg: str,
    ) -> None:
        now_mono = time.monotonic()
        self._prune_attempts(state, now_mono)

        if len(state.attempts) >= self.max_actions_per_window:
            await self._events.write(
                {
                    "timestamp": _utc_now_iso(),
                    "event": "watchdog_action_suppressed",
                    "server_id": server.server_id,
                    "reason": reason,
                    "suppressed_by": "max_actions_per_window",
                    "attempts_in_window": len(state.attempts),
                    "window_seconds": self.window_seconds,
                }
            )
            return

        if now_mono < state.next_allowed_at:
            await self._events.write(
                {
                    "timestamp": _utc_now_iso(),
                    "event": "watchdog_action_suppressed",
                    "server_id": server.server_id,
                    "reason": reason,
                    "suppressed_by": "backoff",
                    "next_allowed_in_seconds": round(state.next_allowed_at - now_mono, 3),
                }
            )
            return

        state.attempts.append(now_mono)

        await self._events.write(
            {
                "timestamp": _utc_now_iso(),
                "event": "watchdog_action_attempt",
                "server_id": server.server_id,
                "action": "restart_wireguard_interface",
                "reason": reason,
                "health_status": health_status,
                "handshake_state": handshake_state,
                "stale_peers": stale_peers,
                "max_handshake_age_s": None if max_handshake_age_s is None else round(float(max_handshake_age_s), 3),
                "interface_ok": interface_ok,
                "interface_message": interface_msg,
                "attempts_in_window": len(state.attempts),
                "window_seconds": self.window_seconds,
            }
        )

        success = False
        message = ""
        try:
            conn = server_connection_from_db(server)
            success, message = await manager.restart_interface(conn, interface=self.interface)
        except Exception as exc:
            success = False
            message = str(exc)

        if success:
            state.consecutive_failures = 0
            state.stuck_cycles = 0
            server.last_reboot_at = datetime.utcnow()
            db.add(server)
            db.commit()
        else:
            state.consecutive_failures += 1

        backoff = self._compute_backoff(failures=state.consecutive_failures)
        jitter = backoff * self._rng.uniform(0.0, self.jitter_fraction)
        delay = backoff + jitter
        state.next_allowed_at = now_mono + delay

        await self._events.write(
            {
                "timestamp": _utc_now_iso(),
                "event": "watchdog_action_result",
                "server_id": server.server_id,
                "action": "restart_wireguard_interface",
                "success": bool(success),
                "message": message,
                "consecutive_failures": state.consecutive_failures,
                "next_allowed_in_seconds": round(delay, 3),
            }
        )


_watchdog: TunnelWatchdog | None = None


def get_tunnel_watchdog() -> TunnelWatchdog:
    global _watchdog
    if _watchdog is None:
        _watchdog = TunnelWatchdog()
    return _watchdog

