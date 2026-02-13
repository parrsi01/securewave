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
        logger.info(f"Adding peer to server {conn.server_id}: {public_key[:20]}... -> {allowed_ips}")

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
        logger.info(f"Removing peer from server {conn.server_id}: {public_key[:20]}...")

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
        if conn.method == "http_api":
            return await self._health_check_via_api(conn)
        elif conn.method == "ssh":
            return await self._health_check_via_ssh(conn)
        else:
            return False, f"Unknown communication method: {conn.method}"

    async def rotate_server_key(
        self,
        conn: ServerConnection,
        private_key: str,
        *,
        interface: str = "wg0",
    ) -> Tuple[bool, str, Optional[str]]:
        """
        Rotate a server WireGuard private key over SSH with rollback safeguards.

        Returns:
            (success, message, new_public_key)
        """
        if not self._wg_key_pattern.match(private_key):
            return False, "Invalid WireGuard private key format", None
        if conn.method != "ssh":
            return False, "Server key rotation currently supports SSH mode only", None

        safe_iface = re.sub(r"[^A-Za-z0-9_-]", "", interface) or "wg0"
        command = (
            "set -euo pipefail; "
            f"IFACE='{safe_iface}'; "
            f"NEW_KEY='{private_key}'; "
            "KEY_PATH='/etc/wireguard/keys/server_private.key'; "
            "CONF=\"/etc/wireguard/${IFACE}.conf\"; "
            "BACKUP=\"/tmp/${IFACE}.conf.bak.$$\"; "
            "sudo install -d -m 700 /etc/wireguard/keys; "
            "if [ -f \"$CONF\" ]; then sudo cp \"$CONF\" \"$BACKUP\"; fi; "
            "printf '%s' \"$NEW_KEY\" | sudo tee \"$KEY_PATH\" >/dev/null; "
            "sudo chmod 600 \"$KEY_PATH\"; "
            "if [ -f \"$CONF\" ]; then "
            "sudo sed -i \"s#^PrivateKey\\s*=.*#PrivateKey = ${NEW_KEY}#g\" \"$CONF\"; "
            "fi; "
            "if ! sudo systemctl restart \"wg-quick@${IFACE}\"; then "
            "if [ -f \"$BACKUP\" ]; then "
            "sudo cp \"$BACKUP\" \"$CONF\"; "
            "sudo systemctl restart \"wg-quick@${IFACE}\" || true; "
            "fi; "
            "echo rotation_failed; "
            "exit 11; "
            "fi; "
            "if [ -f \"$BACKUP\" ]; then sudo rm -f \"$BACKUP\"; fi; "
            "printf '%s' \"$NEW_KEY\" | wg pubkey"
        )

        ok, stdout, stderr = await self._run_ssh_command(conn, command)
        if not ok:
            return False, (stderr or stdout or "rotation failed").strip(), None

        candidate = (stdout or "").strip().splitlines()[-1] if stdout else ""
        if not self._wg_key_pattern.match(candidate):
            return False, "Rotation applied but could not validate resulting public key", None
        return True, "Server key rotated", candidate

    async def restart_interface(
        self,
        conn: ServerConnection,
        *,
        interface: str = "wg0",
    ) -> Tuple[bool, str]:
        """
        Best-effort restart of the WireGuard interface on the VPN node.

        This is used by the self-healing watchdog to recover from missing/stuck tunnels.
        """
        if conn.method != "ssh":
            return False, "Interface restart requires SSH mode"

        safe_iface = re.sub(r"[^A-Za-z0-9_-]", "", interface) or "wg0"
        command = (
            "set -euo pipefail; "
            f"IFACE='{safe_iface}'; "
            "if command -v systemctl >/dev/null 2>&1; then "
            "sudo systemctl restart \"wg-quick@${IFACE}\"; "
            "else "
            "sudo wg-quick down \"${IFACE}\" || true; "
            "sudo wg-quick up \"${IFACE}\"; "
            "fi; "
            "sudo wg show \"${IFACE}\" >/dev/null 2>&1; "
            "echo restarted"
        )
        ok, stdout, stderr = await self._run_ssh_command(conn, command)
        if not ok:
            return False, (stderr or stdout or "restart failed").strip()
        return True, "Interface restarted"

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
                return True, result.get("message", "Peer added")
            else:
                return False, result.get("error", "Unknown error")
        except Exception as e:
            logger.error(f"HTTP API add_peer failed: {e}")
            return False, str(e)

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
                return True, result.get("message", "Peer removed")
            else:
                return False, result.get("error", "Unknown error")
        except Exception as e:
            logger.error(f"HTTP API remove_peer failed: {e}")
            return False, str(e)

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
            logger.error(f"HTTP API list_peers failed: {e}")
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
            logger.error(f"HTTP API get_status failed: {e}")
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
            return False, f"Health check failed: {e}"

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
            return False, "", str(e)

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
            return False, stderr or "Failed to add peer"

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
            return False, stderr or "Failed to remove peer"

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
                    "preshared_key": parts[1] if parts[1] != "(none)" else None,
                    "endpoint": parts[2] if parts[2] != "(none)" else None,
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
            return False, stderr or "Server unhealthy"

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
