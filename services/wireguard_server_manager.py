"""Authenticated SSH peer changes for the single Hetzner WireGuard target."""

from __future__ import annotations

import asyncio
import ipaddress
import os
import re
import shutil
from dataclasses import dataclass


@dataclass(frozen=True)
class ServerConnection:
    server_id: str
    public_ip: str
    ssh_user: str
    ssh_key_path: str
    ssh_port: int = 22
    known_hosts_path: str | None = None


class WireGuardServerManager:
    def __init__(self) -> None:
        self.ssh_path = shutil.which("ssh")
        self.timeout = int(os.getenv("WG_COMMAND_TIMEOUT", "30"))
        self.key_pattern = re.compile(r"^[A-Za-z0-9+/=]{43,44}$")

    @staticmethod
    def remote_operations_enabled() -> bool:
        return os.getenv("TESTING", "").lower() != "true"

    def _validate(self, public_key: str, allowed_ips: str) -> str | None:
        if not self.key_pattern.fullmatch(public_key):
            return "Invalid WireGuard public key format"
        try:
            ipaddress.ip_network(allowed_ips, strict=False)
        except ValueError:
            return "Invalid WireGuard address format"
        return None

    async def _run(self, connection: ServerConnection, command: str) -> bool:
        if not self.ssh_path:
            return False
        if not connection.ssh_key_path or not os.path.isfile(connection.ssh_key_path):
            return False
        if not connection.known_hosts_path or not os.path.isfile(connection.known_hosts_path):
            return False
        try:
            if os.stat(connection.known_hosts_path).st_mode & 0o022:
                return False
        except OSError:
            return False
        process = await asyncio.create_subprocess_exec(
            self.ssh_path,
            "-i",
            connection.ssh_key_path,
            "-o",
            f"ConnectTimeout={self.timeout}",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            f"UserKnownHostsFile={connection.known_hosts_path}",
            "-p",
            str(connection.ssh_port),
            f"{connection.ssh_user}@{connection.public_ip}",
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            await asyncio.wait_for(process.communicate(), timeout=self.timeout)
        except asyncio.TimeoutError:
            process.kill()
            await process.communicate()
            return False
        return process.returncode == 0

    async def add_peer(
        self,
        connection: ServerConnection,
        public_key: str,
        allowed_ips: str,
    ) -> tuple[bool, str]:
        issue = self._validate(public_key, allowed_ips)
        if issue:
            return False, issue
        if not self.remote_operations_enabled():
            return True, "WireGuard peer change skipped in the isolated test database"
        command = (
            "sudo wg set wg0 peer "
            f"{public_key} allowed-ips {allowed_ips} && sudo wg-quick save wg0"
        )
        return (
            (True, "WireGuard peer registered")
            if await self._run(connection, command)
            else (False, "WireGuard target rejected peer registration")
        )

    async def remove_peer(
        self,
        connection: ServerConnection,
        public_key: str,
    ) -> tuple[bool, str]:
        if not self.key_pattern.fullmatch(public_key):
            return False, "Invalid WireGuard public key format"
        if not self.remote_operations_enabled():
            return True, "WireGuard peer change skipped in the isolated test database"
        command = f"sudo wg set wg0 peer {public_key} remove && sudo wg-quick save wg0"
        return (
            (True, "WireGuard peer removed")
            if await self._run(connection, command)
            else (False, "WireGuard target rejected peer removal")
        )


_manager: WireGuardServerManager | None = None


def get_wireguard_server_manager() -> WireGuardServerManager:
    global _manager
    if _manager is None:
        _manager = WireGuardServerManager()
    return _manager


def server_connection_from_db(server) -> ServerConnection:
    key_path = os.getenv("WG_SSH_KEY_PATH", "")
    if not key_path and os.getenv("ENVIRONMENT", "development").lower() != "production":
        key_path = os.path.expanduser("~/.ssh/id_rsa")
    return ServerConnection(
        server_id=server.server_id,
        public_ip=server.public_ip,
        ssh_user=os.getenv("WG_SSH_USER", "securewave"),
        ssh_key_path=key_path,
        ssh_port=int(os.getenv("WG_SSH_PORT", "22")),
        known_hosts_path=os.getenv("WG_KNOWN_HOSTS_PATH", ""),
    )
