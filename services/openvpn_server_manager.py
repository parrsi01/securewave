"""Authenticated, SSH-only OpenVPN server operations.

The backend never exposes an OpenVPN management interface.  Provisioned
servers offer two root-owned, fixed-command utilities instead: a health probe
and a credential verifier updater.  Inputs are validated before they reach
SSH and neither credentials nor command output are logged.
"""

from __future__ import annotations

import re
from typing import Tuple

from services.wireguard_server_manager import ServerConnection, WireGuardServerManager


class OpenVpnServerManager:
    _username = re.compile(r"^swovpn-[a-f0-9]{32}$")
    _hex = re.compile(r"^[a-f0-9]{64}$")

    @staticmethod
    def remote_operations_enabled() -> bool:
        return WireGuardServerManager.remote_operations_enabled()

    def __init__(self) -> None:
        self._ssh = WireGuardServerManager()

    @staticmethod
    def _ssh_only(conn: ServerConnection) -> ServerConnection:
        # OpenVPN never adopts the WireGuard HTTP management transport.
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
            return True, True, "OpenVPN health simulated in local test/mock mode"
        success, stdout, _ = await self._ssh._run_ssh_command(
            self._ssh_only(conn),
            "sudo -n /usr/local/libexec/securewave-openvpn-health",
        )
        healthy = success and stdout.strip() == "OK"
        return healthy, bool(success), "OpenVPN healthy" if healthy else "OpenVPN unavailable"

    async def upsert_credential(
        self,
        conn: ServerConnection,
        *,
        username: str,
        password_salt: str,
        password_hash: str,
        expires_at_epoch: int,
    ) -> tuple[bool, str]:
        if not (
            self._username.fullmatch(username)
            and self._hex.fullmatch(password_salt)
            and self._hex.fullmatch(password_hash)
            and 0 < expires_at_epoch < 4102444800
        ):
            return False, "OpenVPN credential values are invalid"
        if not self.remote_operations_enabled():
            return True, "OpenVPN credential simulated in local test/mock mode"
        command = (
            "sudo -n /usr/local/libexec/securewave-openvpn-credential upsert "
            f"{username} {password_salt} {password_hash} {expires_at_epoch}"
        )
        success, stdout, _ = await self._ssh._run_ssh_command(
            self._ssh_only(conn), command
        )
        return success and stdout.strip() == "OK", "OpenVPN credential updated" if success and stdout.strip() == "OK" else "OpenVPN credential update failed"

    async def revoke_credential(
        self, conn: ServerConnection, *, username: str
    ) -> tuple[bool, str]:
        if not self._username.fullmatch(username):
            return False, "OpenVPN credential identifier is invalid"
        if not self.remote_operations_enabled():
            return True, "OpenVPN credential revocation simulated in local test/mock mode"
        success, stdout, _ = await self._ssh._run_ssh_command(
            self._ssh_only(conn),
            "sudo -n /usr/local/libexec/securewave-openvpn-credential revoke " + username,
        )
        return success and stdout.strip() == "OK", "OpenVPN credential revoked" if success and stdout.strip() == "OK" else "OpenVPN credential revocation failed"


_manager: OpenVpnServerManager | None = None


def get_openvpn_server_manager() -> OpenVpnServerManager:
    global _manager
    if _manager is None:
        _manager = OpenVpnServerManager()
    return _manager
