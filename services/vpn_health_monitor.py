import asyncio
import logging
import os
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
                await asyncio.sleep(30)  # Check every 30 seconds
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

            self.db.close()

        except Exception as e:
            logger.error(f"Failed to check servers: {e}", exc_info=True)
            if self.db:
                self.db.close()

    async def probe_server(self, server: VPNServer) -> Dict:
        """
        Probe individual server for metrics

        Args:
            server: VPN server object

        Returns:
            Dictionary of metrics
        """
        # For real server, probe actual metrics
        latency = await self.ping_server(server.public_ip)

        # In production, these would come from server monitoring agent
        metrics = {
            "latency_ms": latency,
            "active_connections": server.current_connections,
            "cpu_load": await self._get_cpu_load(server),
            "memory_usage": 0.6,  # Would come from monitoring agent
            "packet_loss": 0.0 if latency < 999 else 1.0,
            "jitter_ms": max(0.5, latency * 0.05),  # Estimate jitter as 5% of latency
            "bandwidth_in_mbps": 1000.0,  # Would come from monitoring agent
            "bandwidth_out_mbps": 1000.0,  # Would come from monitoring agent
        }

        return metrics

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
                peer.total_data_received = int(remote.get("transfer_rx", peer.total_data_received or 0))
                peer.total_data_sent = int(remote.get("transfer_tx", peer.total_data_sent or 0))
            else:
                age_seconds = None
                if peer.last_handshake_at:
                    age_seconds = max(0.0, (now - peer.last_handshake_at).total_seconds())

            peer.health_status = self.classify_handshake_freshness(age_seconds)
            statuses.append(peer.health_status)
            self.db.add(peer)

        server.health_status = self.classify_server_health(statuses)
        server.last_health_check = now
        self.db.add(server)
        self.db.commit()

    async def ping_server(self, ip: str) -> float:
        """
        Measure latency to server via ping

        Args:
            ip: Server IP address

        Returns:
            Latency in milliseconds (999.0 if unreachable)
        """
        try:
            # Run ping command (platform-specific)
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

            # Parse average latency from output
            output = stdout.decode()
            if "avg" in output or "average" in output:
                # Extract average from: "rtt min/avg/max/mdev = 10.1/15.3/20.5/3.2 ms"
                for line in output.split("\n"):
                    if "avg" in line or "average" in line:
                        parts = line.split("=")
                        if len(parts) > 1:
                            values = parts[1].split("/")
                            if len(values) >= 2:
                                return float(values[1].strip().replace("ms", "").strip())

            # If we got here, parsing failed but ping succeeded
            return 50.0  # Default reasonable latency

        except FileNotFoundError:
            logger.warning("Ping binary not available; marking latency as unreachable")
            return 999.0
        except (asyncio.TimeoutError, subprocess.SubprocessError, ValueError) as e:
            logger.warning(f"Failed to ping {ip}: {e}")
            return 999.0  # Unreachable

    async def _get_cpu_load(self, server: VPNServer) -> float:
        """
        Get CPU load from server

        In production, this should query a monitoring agent on the server.
        Current implementation returns a deterministic estimate based on
        connection count.

        Args:
            server: VPN server object

        Returns:
            CPU load (0.0 to 1.0)
        """
        # Estimate load from current connection pressure.
        base_load = 0.15  # Idle load
        connection_load = (server.current_connections / server.max_connections) * 0.6
        return min(0.95, base_load + connection_load)

# Singleton instance
_health_monitor = None


def get_health_monitor() -> VPNHealthMonitor:
    """Get singleton health monitor instance"""
    global _health_monitor
    if _health_monitor is None:
        _health_monitor = VPNHealthMonitor()
    return _health_monitor
