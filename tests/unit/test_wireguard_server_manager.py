import pytest

from services.wireguard_server_manager import ServerConnection, WireGuardServerManager


@pytest.mark.asyncio
async def test_restart_interface_uses_pkexec_helper_without_sudo(monkeypatch):
    manager = WireGuardServerManager()
    manager._test_mode = False
    seen = {}

    async def fake_run(conn, command, *, stdin_data=None):
        seen["command"] = command
        return True, "restarted", ""

    monkeypatch.setattr(manager, "_run_ssh_command", fake_run)

    ok, message = await manager.restart_interface(
        ServerConnection(server_id="prod-1", public_ip="203.0.113.10", method="ssh")
    )

    assert ok is True
    assert message == "Interface restarted"
    assert "sudo " not in seen["command"]
    assert "pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick up" in seen["command"]
    assert "pkexec --disable-internal-agent wg show" in seen["command"]


@pytest.mark.asyncio
async def test_restart_interface_classifies_privilege_failures(monkeypatch):
    manager = WireGuardServerManager()
    manager._test_mode = False

    async def fake_run(conn, command, *, stdin_data=None):
        return False, "", "pkexec: Error executing command as another user: Not authorized"

    monkeypatch.setattr(manager, "_run_ssh_command", fake_run)

    ok, message = await manager.restart_interface(
        ServerConnection(server_id="prod-1", public_ip="203.0.113.10", method="ssh")
    )

    assert ok is False
    assert message.startswith("privilege_failure:")
