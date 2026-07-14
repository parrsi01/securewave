"""
WireGuard Server Manager - Manages peer operations on remote WireGuard servers.

Supports multiple communication methods:
1. HTTP API - Direct API calls to management API on WG server
2. SSH - Execute commands via SSH

This service is the bridge between the FastAPI backend and the actual WireGuard servers.
"""

import os
import json
import logging
import subprocess  # nosec B404 - controlled subprocess usage
import asyncio
import shutil
import re
import ipaddress
from typing import Dict, List, Optional, Tuple, Literal
from dataclasses import dataclass
from datetime import datetime
import httpx
from cryptography.fernet import Fernet

from utils.env_validation import validate_fernet_key, is_production

logger = logging.getLogger(__name__)

# Communication method type
CommunicationMethod = Literal["http_api", "ssh"]


@dataclass
class ServerConnection:
    """Configuration for connecting to a WireGuard server"""
    server_id: str
    public_ip: str
    wg_port: int = 51820
    # HTTP API settings
    api_port: int = 8080
    api_key: Optional[str] = None
    # SSH settings
    ssh_user: str = "securewave"
    ssh_key_path: Optional[str] = None
    ssh_port: int = 22
    # Preferred communication method
    method: CommunicationMethod = "ssh"


class WireGuardServerManager:
    """
    Manages WireGuard peer operations on remote servers.

    This class handles adding/removing peers, checking server health,
    and retrieving peer information from WireGuard servers.
    """

    def __init__(self):
        self.fernet = self._load_fernet()
        self._http_client: Optional[httpx.AsyncClient] = None
        self.default_ssh_key = os.getenv("WG_SSH_KEY_PATH", os.path.expanduser("~/.ssh/id_rsa"))
        self.default_api_key = os.getenv("WG_API_KEY", "")
        self.timeout = int(os.getenv("WG_COMMAND_TIMEOUT", "30"))
        self.ssh_path = shutil.which("ssh")
        self._wg_key_pattern = re.compile(r"^[A-Za-z0-9+/=]{43,44}$")

    @staticmethod
    def remote_operations_enabled() -> bool:
        """Return whether this process may contact a WireGuard server.

        Test and mock runs must remain local.  In particular, fixture server
        addresses are documentation-only values and must never trigger SSH or
        HTTP traffic during backend lifecycle tests.
        """
        return not (
            os.getenv("TESTING", "").lower() == "true"
            or os.getenv("WG_MOCK_MODE", "").lower() == "true"
        )

    def _load_fernet(self) -> Optional[Fernet]:
        """Load Fernet encryption key for API keys"""
        key = os.getenv("WG_ENCRYPTION_KEY")
        issue = validate_fernet_key(key)
        if issue:
            if is_production():
                raise RuntimeError(f"WG_ENCRYPTION_KEY {issue} in production")
            logger.warning("WG_ENCRYPTION_KEY %s; API key encryption disabled", issue)
            return None
        return Fernet(key.encode())

    def _validate_peer_inputs(self, public_key: str, allowed_ips: str) -> Optional[str]:
        if not self._wg_key_pattern.match(public_key):
            return "Invalid WireGuard public key format"
        try:
            ipaddress.ip_network(allowed_ips, strict=False)
        except ValueError:
            return "Invalid allowed IPs format"
        return None

    @property
    def http_client(self) -> httpx.AsyncClient:
        """Lazy-initialized HTTP client"""
        if self._http_client is None:
            self._http_client = httpx.AsyncClient(timeout=self.timeout)
        return self._http_client

    async def close(self):
        """Close HTTP client"""
        if self._http_client:
            await self._http_client.aclose()
            self._http_client = None

    # =========================================================================
    # Peer Management Operations
    # =========================================================================

    async def add_peer(
        self,
        conn: ServerConnection,
        public_key: str,
        allowed_ips: str,
    ) -> Tuple[bool, str]:
        """
        Add a peer to a WireGuard server.

        Args:
            conn: Server connection configuration
            public_key: Client's WireGuard public key
            allowed_ips: Allowed IP addresses (e.g., "10.8.0.10/32")

        Returns:
            Tuple of (success, message)
        """
        logger.info("Adding peer to server_id=%s", conn.server_id)

        if not self.remote_operations_enabled():
            return True, "Peer addition simulated (local test/mock mode)"

        if conn.method == "http_api":
            return await self._add_peer_via_api(conn, public_key, allowed_ips)
        elif conn.method == "ssh":
            return await self._add_peer_via_ssh(conn, public_key, allowed_ips)
        else:
            return False, f"Unknown communication method: {conn.method}"

    async def remove_peer(
        self,
        conn: ServerConnection,
        public_key: str,
    ) -> Tuple[bool, str]:
        """
        Remove a peer from a WireGuard server.

        Args:
            conn: Server connection configuration
            public_key: Client's WireGuard public key to remove

        Returns:
            Tuple of (success, message)
        """
        logger.info("Removing peer from server_id=%s", conn.server_id)

        if not self.remote_operations_enabled():
            return True, "Peer removal simulated (local test/mock mode)"

        if conn.method == "http_api":
            return await self._remove_peer_via_api(conn, public_key)
        elif conn.method == "ssh":
            return await self._remove_peer_via_ssh(conn, public_key)
        else:
            return False, f"Unknown communication method: {conn.method}"

    async def list_peers(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, List[Dict]]:
        """
        List all peers on a WireGuard server.

        Args:
            conn: Server connection configuration

        Returns:
            Tuple of (success, list of peer dicts)
        """
        if not self.remote_operations_enabled():
            return True, []

        if conn.method == "http_api":
            return await self._list_peers_via_api(conn)
        elif conn.method == "ssh":
            return await self._list_peers_via_ssh(conn)
        else:
            return False, []

    async def get_server_status(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, Dict]:
        """
        Get WireGuard server status and metrics.

        Args:
            conn: Server connection configuration

        Returns:
            Tuple of (success, status dict)
        """
        if not self.remote_operations_enabled():
            return True, {"status": "mock"}

        if conn.method == "http_api":
            return await self._get_status_via_api(conn)
        elif conn.method == "ssh":
            return await self._get_status_via_ssh(conn)
        else:
            return False, {}

    async def health_check(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, str]:
        """
        Quick health check for a WireGuard server.

        Args:
            conn: Server connection configuration

        Returns:
            Tuple of (healthy, message)
        """
        if not self.remote_operations_enabled():
            return True, "WireGuard server probe simulated (local test/mock mode)"

        if conn.method == "http_api":
            return await self._health_check_via_api(conn)
        elif conn.method == "ssh":
            return await self._health_check_via_ssh(conn)
        else:
            return False, f"Unknown communication method: {conn.method}"

    # =========================================================================
    # HTTP API Implementation
    # =========================================================================

    async def _add_peer_via_api(
        self,
        conn: ServerConnection,
        public_key: str,
        allowed_ips: str,
    ) -> Tuple[bool, str]:
        """Add peer via HTTP management API"""
        try:
            url = f"http://{conn.public_ip}:{conn.api_port}/peers/add"
            headers = {"X-API-Key": conn.api_key or self.default_api_key}
            data = {"public_key": public_key, "allowed_ips": allowed_ips}

            response = await self.http_client.post(url, json=data, headers=headers)
            result = response.json()

            if response.status_code == 200 and result.get("success"):
                return True, "Peer added successfully"
            return False, "Management API rejected peer addition"
        except Exception as e:
            logger.error("Management API add-peer failed exception_type=%s", type(e).__name__)
            return False, "Management API unavailable"

    async def _remove_peer_via_api(
        self,
        conn: ServerConnection,
        public_key: str,
    ) -> Tuple[bool, str]:
        """Remove peer via HTTP management API"""
        try:
            url = f"http://{conn.public_ip}:{conn.api_port}/peers/remove"
            headers = {"X-API-Key": conn.api_key or self.default_api_key}
            data = {"public_key": public_key}

            response = await self.http_client.post(url, json=data, headers=headers)
            result = response.json()

            if response.status_code == 200 and result.get("success"):
                return True, "Peer removed successfully"
            return False, "Management API rejected peer removal"
        except Exception as e:
            logger.error("Management API remove-peer failed exception_type=%s", type(e).__name__)
            return False, "Management API unavailable"

    async def _list_peers_via_api(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, List[Dict]]:
        """List peers via HTTP management API"""
        try:
            url = f"http://{conn.public_ip}:{conn.api_port}/peers"
            headers = {"X-API-Key": conn.api_key or self.default_api_key}

            response = await self.http_client.get(url, headers=headers)
            if response.status_code == 200:
                return True, response.json()
            else:
                return False, []
        except Exception as e:
            logger.error("Management API peer-list failed exception_type=%s", type(e).__name__)
            return False, []

    async def _get_status_via_api(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, Dict]:
        """Get server status via HTTP management API"""
        try:
            url = f"http://{conn.public_ip}:{conn.api_port}/status"
            headers = {"X-API-Key": conn.api_key or self.default_api_key}

            response = await self.http_client.get(url, headers=headers)
            if response.status_code == 200:
                return True, response.json()
            else:
                return False, {}
        except Exception as e:
            logger.error("Management API status failed exception_type=%s", type(e).__name__)
            return False, {}

    async def _health_check_via_api(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, str]:
        """Health check via HTTP management API"""
        try:
            url = f"http://{conn.public_ip}:{conn.api_port}/health"
            headers = {"X-API-Key": conn.api_key or self.default_api_key}

            response = await self.http_client.get(url, headers=headers, timeout=10)
            result = response.json()

            if response.status_code == 200 and result.get("healthy"):
                return True, "Server healthy"
            else:
                return False, "Server unhealthy"
        except Exception as e:
            logger.warning("Management API health check failed exception_type=%s", type(e).__name__)
            return False, "Management API unavailable"

    # =========================================================================
    # SSH Implementation
    # =========================================================================

    async def _run_ssh_command(
        self,
        conn: ServerConnection,
        command: str,
    ) -> Tuple[bool, str, str]:
        """
        Execute a command via SSH.

        Returns:
            Tuple of (success, stdout, stderr)
        """
        ssh_key = conn.ssh_key_path or self.default_ssh_key
        ssh_target = f"{conn.ssh_user}@{conn.public_ip}"

        if not self.ssh_path:
            return False, "", "SSH client not installed"

        ssh_cmd = [
            self.ssh_path,
            "-i", ssh_key,
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", f"ConnectTimeout={self.timeout}",
            "-p", str(conn.ssh_port),
            ssh_target,
            command
        ]

        try:
            process = await asyncio.create_subprocess_exec(
                *ssh_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await asyncio.wait_for(
                process.communicate(),
                timeout=self.timeout
            )

            success = process.returncode == 0
            return success, stdout.decode().strip(), stderr.decode().strip()
        except asyncio.TimeoutError:
            return False, "", "SSH command timed out"
        except Exception as e:
            logger.warning("SSH command failed exception_type=%s", type(e).__name__)
            return False, "", "SSH command failed"

    async def _add_peer_via_ssh(
        self,
        conn: ServerConnection,
        public_key: str,
        allowed_ips: str,
    ) -> Tuple[bool, str]:
        """Add peer via SSH"""
        # Use wg set directly for atomic operation
        error = self._validate_peer_inputs(public_key, allowed_ips)
        if error:
            return False, error

        cmd = f"sudo wg set wg0 peer '{public_key}' allowed-ips '{allowed_ips}' && sudo wg-quick save wg0"
        success, stdout, stderr = await self._run_ssh_command(conn, cmd)

        if success:
            return True, "Peer added successfully"
        else:
            return False, "Failed to add peer"

    async def _remove_peer_via_ssh(
        self,
        conn: ServerConnection,
        public_key: str,
    ) -> Tuple[bool, str]:
        """Remove peer via SSH"""
        cmd = f"sudo wg set wg0 peer '{public_key}' remove && sudo wg-quick save wg0"
        success, stdout, stderr = await self._run_ssh_command(conn, cmd)

        if success:
            return True, "Peer removed successfully"
        else:
            return False, "Failed to remove peer"

    async def _list_peers_via_ssh(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, List[Dict]]:
        """List peers via SSH"""
        cmd = "sudo wg show wg0 dump"
        success, stdout, stderr = await self._run_ssh_command(conn, cmd)

        if not success:
            return False, []

        peers = []
        lines = stdout.strip().split('\n')

        # Skip first line (server info)
        for line in lines[1:]:
            if not line.strip():
                continue
            parts = line.split('\t')
            if len(parts) >= 5:
                peer = {
                    "public_key": parts[0],
                    "allowed_ips": parts[3],
                    "latest_handshake": int(parts[4]) if parts[4] != "0" else None,
                    "transfer_rx": int(parts[5]) if len(parts) > 5 else 0,
                    "transfer_tx": int(parts[6]) if len(parts) > 6 else 0,
                }
                peers.append(peer)

        return True, peers

    async def _get_status_via_ssh(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, Dict]:
        """Get server status via SSH"""
        # Get WireGuard status
        wg_cmd = "sudo wg show wg0"
        wg_success, wg_stdout, _ = await self._run_ssh_command(conn, wg_cmd)

        # Get system metrics
        metrics_cmd = """
        echo "{"
        echo '"cpu_load":' $(awk '{print $1}' /proc/loadavg),
        echo '"memory_percent":' $(free | awk '/Mem/{printf "%.1f", $3/$2*100}'),
        echo '"disk_percent":' $(df / | tail -1 | awk '{print int($5)}'),
        echo '"peer_count":' $(sudo wg show wg0 peers 2>/dev/null | wc -l),
        echo '"uptime_seconds":' $(awk '{print int($1)}' /proc/uptime)
        echo "}"
        """
        metrics_success, metrics_stdout, _ = await self._run_ssh_command(conn, metrics_cmd)

        if not wg_success:
            return False, {}

        status = {
            "status": "active" if wg_success else "inactive",
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }

        if metrics_success:
            try:
                metrics = json.loads(metrics_stdout)
                status.update(metrics)
            except json.JSONDecodeError:
                pass

        return True, status

    async def _health_check_via_ssh(
        self,
        conn: ServerConnection,
    ) -> Tuple[bool, str]:
        """Health check via SSH"""
        cmd = "sudo wg show wg0 > /dev/null 2>&1 && echo 'OK' || echo 'FAIL'"
        success, stdout, stderr = await self._run_ssh_command(conn, cmd)

        if success and stdout.strip() == "OK":
            return True, "Server healthy"
        else:
            return False, "Server unhealthy"

# Singleton instance
_manager_instance: Optional[WireGuardServerManager] = None


def get_wireguard_server_manager() -> WireGuardServerManager:
    """Get the singleton WireGuardServerManager instance"""
    global _manager_instance
    if _manager_instance is None:
        _manager_instance = WireGuardServerManager()
    return _manager_instance


def server_connection_from_db(server) -> ServerConnection:
    """
    Create a ServerConnection from a VPNServer database model.

    Args:
        server: VPNServer model instance

    Returns:
        ServerConnection configured for this server
    """
    # Determine the best communication method based on available config
    method: CommunicationMethod = "ssh"  # Default

    # Prefer HTTP API if configured
    api_key = os.getenv("WG_API_KEY")
    if api_key:
        method = "http_api"
    elif os.getenv("WG_SSH_KEY_PATH"):
        method = "ssh"

    return ServerConnection(
        server_id=server.server_id,
        public_ip=server.public_ip,
        wg_port=server.wg_listen_port or 51820,
        api_port=int(os.getenv("WG_API_PORT", "8080")),
        api_key=api_key,
        ssh_user=os.getenv("WG_SSH_USER", "securewave"),
        ssh_key_path=os.getenv("WG_SSH_KEY_PATH"),
        method=method,
    )
