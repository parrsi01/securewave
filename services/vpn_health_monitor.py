import asyncio
import logging
import random
import subprocess
from datetime import datetime
from typing import Dict

from sqlalchemy.orm import Session

from database.session import SessionLocal
from models.vpn_server import VPNServer
from services.vpn_server_service import VPNServerService

logger = logging.getLogger(__name__)


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
                .filter(VPNServer.status.in_(["active", "demo"]))
                .all()
            )

            logger.debug(f"Checking health of {len(servers)} servers")

            for server in servers:
                try:
                    metrics = await self.probe_server(server)
                    self.server_service.update_server_metrics(
                        self.db, server.server_id, metrics
                    )

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
        # If demo server, use simulated metrics
        if server.status == "demo":
            return self._generate_demo_metrics(server)

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
            result = await asyncio.create_subprocess_exec(
                "ping",
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

        except (asyncio.TimeoutError, subprocess.SubprocessError, ValueError) as e:
            logger.warning(f"Failed to ping {ip}: {e}")
            return 999.0  # Unreachable

    async def _get_cpu_load(self, server: VPNServer) -> float:
        """
        Get CPU load from server

        In production, this would query a monitoring agent on the server.
        For now, returns a simulated value based on connection count.

        Args:
            server: VPN server object

        Returns:
            CPU load (0.0 to 1.0)
        """
        # Simulate load based on connection count
        base_load = 0.15  # Idle load
        connection_load = (server.current_connections / server.max_connections) * 0.6
        return min(0.95, base_load + connection_load)

    def _generate_demo_metrics(self, server: VPNServer) -> Dict:
        """
        Generate realistic but simulated metrics for demo servers

        Args:
            server: VPN server object

        Returns:
            Dictionary of simulated metrics
        """
        # Base metrics with some randomness for realism
        base_latency = {
            "us-west-1": 30,
            "eu-west-1": 40,
            "eu-central-1": 45,
            "ap-southeast-1": 80,
            "ap-northeast-1": 85,
        }.get(server.server_id, 50)

        # Add jitter to latency
        latency = base_latency + random.uniform(-5, 10)

        metrics = {
            "latency_ms": round(latency, 1),
            "bandwidth_mbps": random.uniform(800, 1000),
            "cpu_load": random.uniform(0.2, 0.6),
            "active_connections": server.current_connections,
            "packet_loss": random.uniform(0.0, 0.02),  # 0-2%
            "jitter_ms": random.uniform(1, 5),
            "bandwidth_in_mbps": random.uniform(800, 1000),
            "bandwidth_out_mbps": random.uniform(800, 1000),
        }

        return metrics


# Singleton instance
_health_monitor = None


def get_health_monitor() -> VPNHealthMonitor:
    """Get singleton health monitor instance"""
    global _health_monitor
    if _health_monitor is None:
        _health_monitor = VPNHealthMonitor()
    return _health_monitor
