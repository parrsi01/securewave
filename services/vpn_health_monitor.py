import asyncio
import logging
import os
import socket
import subprocess  # nosec B404 - controlled subprocess usage
import shutil
import time
from datetime import datetime
from typing import Dict, List

from sqlalchemy.orm import Session

from database.session import SessionLocal
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.vpn_server_service import VPNServerService
from services.runtime_metrics import get_runtime_metrics
from services.wireguard_server_manager import get_wireguard_server_manager, server_connection_from_db

logger = logging.getLogger(__name__)


DEGRADED_HANDSHAKE_SECONDS = int(os.getenv("WG_HANDSHAKE_DEGRADED_SECONDS", "120"))
UNSTABLE_HANDSHAKE_SECONDS = int(os.getenv("WG_HANDSHAKE_UNSTABLE_SECONDS", "300"))

# After this many consecutive probe failures a node transitions to "offline".
OFFLINE_FAILURE_THRESHOLD = int(os.getenv("VPN_OFFLINE_FAILURE_THRESHOLD", "5"))

# Health check interval in seconds.
HEALTH_CHECK_INTERVAL = int(os.getenv("VPN_HEALTH_CHECK_INTERVAL", "30"))

# WireGuard port probe timeout in seconds.
WG_PORT_PROBE_TIMEOUT = float(os.getenv("VPN_WG_PORT_PROBE_TIMEOUT", "3"))


class VPNHealthMonitor:
    """Background service to monitor VPN server health"""

    def __init__(self):
        self.db: Session = None
        self.server_service = None
        self.is_running = False

    async def start(self):
        """Start the health monitoring loop"""
        self.is_running = True
        logger.info("VPN Health Monitor started")

        while self.is_running:
            try:
                await self.check_all_servers()
                await asyncio.sleep(HEALTH_CHECK_INTERVAL)
            except Exception as e:
                logger.error(f"Health monitor error: {e}", exc_info=True)
                await asyncio.sleep(60)  # Wait longer on error

    async def stop(self):
        """Stop the health monitoring loop"""
        self.is_running = False
        logger.info("VPN Health Monitor stopped")

    async def check_all_servers(self):
        """Check health of all active servers"""
        try:
            # Create new DB session for this check cycle
            self.db = SessionLocal()
            self.server_service = VPNServerService()

            servers = (
                self.db.query(VPNServer)
                .filter(VPNServer.status.in_(["active"]))
                .all()
            )

            logger.debug(f"Checking health of {len(servers)} servers")

            for server in servers:
                try:
                    metrics = await self.probe_server(server)
                    self.server_service.update_server_metrics(
                        self.db, server.server_id, metrics
                    )

                    # Determine effective health from combined probes
                    ping_ok = metrics["latency_ms"] < 999
                    port_ok = metrics.get("wg_port_open", False)
                    self._apply_health_transition(server, ping_ok, port_ok)

                    await self.refresh_peer_handshake_health(server)

                    # Update optimizer with fresh metrics
                    try:
                        from services.vpn_optimizer import get_vpn_optimizer

                        optimizer = get_vpn_optimizer()
                        optimizer.update_server_metrics(server.server_id, metrics)
                    except Exception as e:
                        logger.warning(f"Failed to update optimizer for {server.server_id}: {e}")

                except Exception as e:
                    logger.error(f"Failed to probe {server.server_id}: {e}")
                    # Count the failure even when the entire probe threw.
                    self._apply_health_transition(server, ping_ok=False, port_ok=False)

            self.db.commit()
            self.db.close()

        except Exception as e:
            logger.error(f"Failed to check servers: {e}", exc_info=True)
            if self.db:
                self.db.close()

    # ------------------------------------------------------------------
    # Health state transitions
    # ------------------------------------------------------------------

    def _apply_health_transition(
        self,
        server: VPNServer,
        ping_ok: bool,
        port_ok: bool,
    ) -> None:
        """
        Transition server health based on probe results.

        Statuses:
          healthy  — ping OK **and** WireGuard port reachable
          degraded — ping OK but WireGuard port unreachable, or vice-versa
          offline  — consecutive failures >= OFFLINE_FAILURE_THRESHOLD

        When a previously-offline server passes both probes, it recovers to
        healthy and the failure counter resets.
        """
        now = datetime.utcnow()
        server.last_health_check = now

        if ping_ok and port_ok:
            # Full pass — reset failure counter and mark healthy.
            server.consecutive_health_failures = 0
            if server.health_status in ("offline", "unreachable"):
                logger.info(
                    "Server %s recovered from %s → healthy",
                    server.server_id,
                    server.health_status,
                )
            server.health_status = "healthy"
            return

        # At least one probe failed — increment failure counter.
        server.consecutive_health_failures = (server.consecutive_health_failures or 0) + 1

        if server.consecutive_health_failures >= OFFLINE_FAILURE_THRESHOLD:
            if server.health_status != "offline":
                logger.warning(
                    "Server %s marked offline after %d consecutive failures",
                    server.server_id,
                    server.consecutive_health_failures,
                )
            server.health_status = "offline"
        elif ping_ok or port_ok:
            # Partial reachability
            server.health_status = "degraded"
        else:
            # Both probes failed but below offline threshold
            server.health_status = "unhealthy"

    # ------------------------------------------------------------------
    # Server probing
    # ------------------------------------------------------------------

    async def probe_server(self, server: VPNServer) -> Dict:
        """
        Probe individual server for metrics.

        Returns a dict with latency, cpu, memory, packet_loss, and a
        ``wg_port_open`` boolean indicating WireGuard UDP reachability.
        """
        latency = await self.ping_server(server.public_ip)
        wg_port_open = await self.check_wg_port(
            server.public_ip,
            server.wg_listen_port or 51820,
        )

        metrics = {
            "latency_ms": latency,
            "active_connections": server.current_connections,
            "cpu_load": await self._get_cpu_load(server),
            "memory_usage": 0.6,  # Would come from monitoring agent
            "packet_loss": 0.0 if latency < 999 else 1.0,
            "jitter_ms": max(0.5, latency * 0.05),
            "bandwidth_in_mbps": 1000.0,
            "bandwidth_out_mbps": 1000.0,
            "wg_port_open": wg_port_open,
        }

        return metrics

    # ------------------------------------------------------------------
    # WireGuard UDP port check
    # ------------------------------------------------------------------

    @staticmethod
    async def check_wg_port(
        ip: str,
        port: int,
        timeout: float = WG_PORT_PROBE_TIMEOUT,
    ) -> bool:
        """
        Check whether the WireGuard UDP port is reachable.

        Sends a single empty UDP datagram and waits for an ICMP
        "port unreachable" error. If the socket stays open (no error)
        within the timeout, we assume the port is accepting packets.

        Returns True if the port appears open, False otherwise.
        """
        loop = asyncio.get_event_loop()
        try:
            return await asyncio.wait_for(
                loop.run_in_executor(None, _udp_port_probe, ip, port, timeout),
                timeout=timeout + 1,
            )
        except (asyncio.TimeoutError, OSError) as exc:
            logger.debug("WG port check %s:%d failed: %s", ip, port, exc)
            return False

    # ------------------------------------------------------------------
    # Handshake freshness / server health classification
    # ------------------------------------------------------------------

    @staticmethod
    def classify_handshake_freshness(age_seconds: float | None) -> str:
        """
        Classify handshake freshness for a peer.

        Returns "pending" for peers that have never completed a handshake
        (age_seconds is None).  These peers are provisioned but not yet
        connected and must NOT drag server health toward unstable.
        """
        if age_seconds is None:
            return "pending"
        if age_seconds > UNSTABLE_HANDSHAKE_SECONDS:
            return "unstable"
        if age_seconds > DEGRADED_HANDSHAKE_SECONDS:
            return "degraded"
        return "healthy"

    @staticmethod
    def classify_server_health(peer_statuses: List[str]) -> str:
        """
        Derive server health from peer statuses.

        Peers with status "pending" (never connected) are excluded from
        the calculation.  Only peers that have completed at least one
        handshake participate in the health ratio.
        """
        # Filter out peers that have never connected.
        active_statuses = [s for s in peer_statuses if s != "pending"]

        if not active_statuses:
            # No peers with handshake data -- server is idle, not unhealthy.
            return "healthy"

        total = len(active_statuses)
        unstable = len([s for s in active_statuses if s == "unstable"])
        degraded = len([s for s in active_statuses if s == "degraded"])

        unstable_ratio = unstable / total
        degraded_ratio = (unstable + degraded) / total

        if unstable_ratio >= 0.30:
            return "unstable"
        if degraded_ratio >= 0.25:
            return "degraded"
        return "healthy"

    async def refresh_peer_handshake_health(self, server: VPNServer) -> None:
        """
        Pull latest handshake data from the WireGuard node and update peer health.
        """
        peers = (
            self.db.query(WireGuardPeer)
            .filter(
                WireGuardPeer.server_id == server.id,
                WireGuardPeer.is_revoked == False,
                WireGuardPeer.is_active == True,
            )
            .all()
        )
        if not peers:
            return

        now = datetime.utcnow()
        manager = get_wireguard_server_manager()
        conn = server_connection_from_db(server)
        start = time.monotonic()
        success, remote_peers = await manager.list_peers(conn)
        request_latency_ms = (time.monotonic() - start) * 1000.0
        get_runtime_metrics().record_handshake_latency(request_latency_ms)

        remote_by_key = {}
        if success:
            remote_by_key = {item.get("public_key"): item for item in remote_peers if item.get("public_key")}

        statuses: List[str] = []
        for peer in peers:
            remote = remote_by_key.get(peer.public_key)
            if remote and remote.get("latest_handshake"):
                handshake_at = datetime.utcfromtimestamp(remote["latest_handshake"])
                age_seconds = max(0.0, (now - handshake_at).total_seconds())
                peer.last_handshake_at = handshake_at
                peer.last_handshake_latency_ms = round(request_latency_ms, 2)
                new_rx = int(remote.get("transfer_rx", peer.total_data_received or 0))
                new_tx = int(remote.get("transfer_tx", peer.total_data_sent or 0))
                if new_rx != (peer.total_data_received or 0) or new_tx != (peer.total_data_sent or 0):
                    logger.debug(
                        '[METRICS] peer=%s rx=%d→%d tx=%d→%d',
                        peer.public_key[:8], peer.total_data_received or 0, new_rx,
                        peer.total_data_sent or 0, new_tx,
                    )
                peer.total_data_received = new_rx
                peer.total_data_sent = new_tx
            else:
                age_seconds = None
                if peer.last_handshake_at:
                    age_seconds = max(0.0, (now - peer.last_handshake_at).total_seconds())

            peer.health_status = self.classify_handshake_freshness(age_seconds)
            statuses.append(peer.health_status)
            self.db.add(peer)

        # Only override server health from peer stats when server is not already
        # marked offline by the probe layer.
        if server.health_status != "offline":
            server.health_status = self.classify_server_health(statuses)
        server.last_health_check = now
        self.db.add(server)
        self.db.commit()

    async def ping_server(self, ip: str) -> float:
        """
        Measure latency to server via ping.

        Returns latency in milliseconds (999.0 if unreachable).
        """
        try:
            ping_path = shutil.which("ping")
            if not ping_path:
                raise FileNotFoundError("ping not available")

            result = await asyncio.create_subprocess_exec(
                ping_path,
                "-c",
                "3",  # 3 packets
                "-W",
                "2",  # 2 second timeout
                ip,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

            stdout, stderr = await asyncio.wait_for(result.communicate(), timeout=5)

            output = stdout.decode()
            if "avg" in output or "average" in output:
                for line in output.split("\n"):
                    if "avg" in line or "average" in line:
                        parts = line.split("=")
                        if len(parts) > 1:
                            values = parts[1].split("/")
                            if len(values) >= 2:
                                return float(values[1].strip().replace("ms", "").strip())

            return 50.0  # Default reasonable latency

        except FileNotFoundError:
            logger.warning("Ping binary not available; marking latency as unreachable")
            return 999.0
        except (asyncio.TimeoutError, subprocess.SubprocessError, ValueError) as e:
            logger.warning(f"Failed to ping {ip}: {e}")
            return 999.0  # Unreachable

    async def _get_cpu_load(self, server: VPNServer) -> float:
        """
        Get CPU load from server.

        In production, this should query a monitoring agent on the server.
        Current implementation returns a deterministic estimate based on
        connection count.
        """
        base_load = 0.15
        connection_load = (server.current_connections / server.max_connections) * 0.6
        return min(0.95, base_load + connection_load)


# ---------------------------------------------------------------------------
# Helpers (module-level, not methods, so they work inside run_in_executor)
# ---------------------------------------------------------------------------

def _udp_port_probe(ip: str, port: int, timeout: float) -> bool:
    """
    Send a single empty UDP datagram and check for ICMP port-unreachable.

    If the OS returns ECONNREFUSED (Linux) the port is explicitly closed.
    If the socket stays writable with no error, we assume the port is open
    (WireGuard silently drops unknown packets).
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(b"", (ip, port))
        # Wait for potential ICMP error to arrive.
        try:
            sock.recvfrom(1024)
        except socket.timeout:
            # No ICMP error within timeout — port is open (WireGuard drops silently).
            return True
        except OSError as e:
            if e.errno in (111, 113):  # ECONNREFUSED / EHOSTUNREACH
                return False
            # Other OS error — treat as closed.
            return False
        # Got a response — port is definitely open.
        return True
    except OSError:
        return False
    finally:
        sock.close()


# Singleton instance
_health_monitor = None


def get_health_monitor() -> VPNHealthMonitor:
    """Get singleton health monitor instance"""
    global _health_monitor
    if _health_monitor is None:
        _health_monitor = VPNHealthMonitor()
    return _health_monitor
