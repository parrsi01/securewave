"""Contract tests for the fixed, authenticated IKEv2 gateway channel."""

from __future__ import annotations

import pytest

from services.ikev2_server_manager import Ikev2ServerManager
from services.wireguard_server_manager import ServerConnection


@pytest.mark.asyncio
async def test_ikev2_refuses_unpinned_gateway_before_health_or_credential_write(monkeypatch):
    manager = Ikev2ServerManager()
    conn = ServerConnection(server_id="ikev2-test", public_ip="192.0.2.10")
    monkeypatch.setattr(manager, "remote_operations_enabled", lambda: True)
    monkeypatch.delenv("SECUREWAVE_IKEV2_SSH_KNOWN_HOSTS_PATH", raising=False)

    healthy, authenticated, _ = await manager.authenticated_health_check(conn)
    updated, _ = await manager.upsert_credential(
        conn,
        username="swikev2-" + "a" * 32,
        password="A" * 32,
    )

    assert (healthy, authenticated) == (False, False)
    assert updated is False


@pytest.mark.asyncio
async def test_ikev2_uses_strict_pinned_ssh_and_sends_secret_only_on_stdin(
    monkeypatch, tmp_path
):
    manager = Ikev2ServerManager()
    conn = ServerConnection(server_id="ikev2-test", public_ip="192.0.2.10")
    known_hosts = tmp_path / "known_hosts"
    known_hosts.write_text("[192.0.2.10]:22 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest\\n")
    known_hosts.chmod(0o600)
    username = "swikev2-" + "b" * 32
    password = "B" * 32
    calls: list[tuple[str, dict[str, object]]] = []

    async def fake_ssh(_conn, command, **kwargs):
        calls.append((command, kwargs))
        return True, "OK", ""

    monkeypatch.setattr(manager, "remote_operations_enabled", lambda: True)
    monkeypatch.setenv("SECUREWAVE_IKEV2_SSH_KNOWN_HOSTS_PATH", str(known_hosts))
    monkeypatch.setattr(manager._ssh, "_run_ssh_command", fake_ssh)

    healthy, authenticated, _ = await manager.authenticated_health_check(conn)
    updated, _ = await manager.upsert_credential(conn, username=username, password=password)
    revoked, _ = await manager.revoke_credential(conn, username=username)

    assert (healthy, authenticated, updated, revoked) == (True, True, True, True)
    assert calls[0][0] == "sudo -n /usr/local/libexec/securewave-ikev2-health"
    assert calls[1][0].endswith(" upsert " + username)
    assert password not in calls[1][0]
    assert calls[1][1]["stdin"] == password + "\n"
    assert calls[2][0].endswith(" revoke " + username)
    for _, kwargs in calls:
        assert kwargs["strict_host_key_checking"] is True
        assert kwargs["known_hosts_path"] == str(known_hosts)

