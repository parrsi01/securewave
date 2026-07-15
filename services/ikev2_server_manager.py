"""Authenticated, SSH-only IKEv2 server operations.

The IKEv2 gateway is a dedicated SecureWave strongSwan/swanctl deployment.
The backend may invoke only its fixed health and credential lifecycle helpers;
it never exposes VICI, a management socket, or arbitrary remote commands.
"""

from __future__ import annotations

import re
import os
from typing import Tuple

from services.wireguard_server_manager import ServerConnection, WireGuardServerManager


class Ikev2ServerManager:
    _username = re.compile(r"^swikev2-[a-f0-9]{32}$")
    _password = re.compile(r"^[A-Za-z0-9_-]{32,128}$")

    @staticmethod
    def remote_operations_enabled() -> bool:
        return WireGuardServerManager.remote_operations_enabled()

    def __init__(self) -> None:
        self._ssh = WireGuardServerManager()

    @staticmethod
    def _known_hosts_path() -> str | None:
        """Return the pinned gateway host-key file, or fail closed.

        IKEv2 credential provisioning is an authenticated control-plane
        operation.  Reusing the legacy SSH TOFU path would allow a network
        attacker to impersonate a gateway and receive a client EAP secret.
        """
        value = os.getenv("SECUREWAVE_IKEV2_SSH_KNOWN_HOSTS_PATH", "").strip()
        return value or None

    async def _run_fixed_command(
        self,
        conn: ServerConnection,
        command: str,
        *,
        stdin: str | None = None,
    ) -> tuple[bool, str, str]:
        known_hosts_path = self._known_hosts_path()
        if not known_hosts_path:
            return False, "", "IKEv2 SSH host verification is not configured"
        return await self._ssh._run_ssh_command(
            self._ssh_only(conn),
            command,
            stdin=stdin,
            strict_host_key_checking=True,
            known_hosts_path=known_hosts_path,
        )

    @staticmethod
    def _ssh_only(conn: ServerConnection) -> ServerConnection:
        return ServerConnection(
            server_id=conn.server_id,
            public_ip=conn.public_ip,
            wg_port=conn.wg_port,
            ssh_user=conn.ssh_user,
            ssh_key_path=conn.ssh_key_path,
            ssh_port=conn.ssh_port,
            method="ssh",
        )

    async def authenticated_health_check(
        self, conn: ServerConnection
    ) -> Tuple[bool, bool, str]:
        if not self.remote_operations_enabled():
            # Local test/mock mode must not turn simulated reachability into
            # authenticated evidence that could enable IKEv2 for users.
            return False, False, "IKEv2 health is simulated in local test/mock mode"
        success, stdout, _ = await self._run_fixed_command(
            conn,
            "sudo -n /usr/local/libexec/securewave-ikev2-health",
        )
        healthy = success and stdout.strip() == "OK"
        return healthy, bool(success), "IKEv2 healthy" if healthy else "IKEv2 unavailable"

    async def upsert_credential(
        self,
        conn: ServerConnection,
        *,
        username: str,
        password: str,
    ) -> tuple[bool, str]:
        if not self._username.fullmatch(username) or not self._password.fullmatch(password):
            return False, "IKEv2 credential values are invalid"
        if not self.remote_operations_enabled():
            return True, "IKEv2 credential simulated in local test/mock mode"
        # The password is sent only on SSH stdin, never in a command argument,
        # log message, process list, or remote shell expansion.
        success, stdout, _ = await self._run_fixed_command(
            conn,
            "sudo -n /usr/local/libexec/securewave-ikev2-credential upsert " + username,
            stdin=password + "\n",
        )
        ok = success and stdout.strip() == "OK"
        return ok, "IKEv2 credential updated" if ok else "IKEv2 credential update failed"

    async def revoke_credential(
        self, conn: ServerConnection, *, username: str
    ) -> tuple[bool, str]:
        if not self._username.fullmatch(username):
            return False, "IKEv2 credential identifier is invalid"
        if not self.remote_operations_enabled():
            return True, "IKEv2 credential revocation simulated in local test/mock mode"
        success, stdout, _ = await self._run_fixed_command(
            conn,
            "sudo -n /usr/local/libexec/securewave-ikev2-credential revoke " + username,
        )
        ok = success and stdout.strip() == "OK"
        return ok, "IKEv2 credential revoked" if ok else "IKEv2 credential revocation failed"


_manager: Ikev2ServerManager | None = None


def get_ikev2_server_manager() -> Ikev2ServerManager:
    global _manager
    if _manager is None:
        _manager = Ikev2ServerManager()
    return _manager
