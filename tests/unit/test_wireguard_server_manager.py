import pytest

from services.wireguard_server_manager import ServerConnection, WireGuardServerManager


@pytest.mark.asyncio
async def test_ssh_peer_inventory_omits_preshared_keys_and_endpoints(monkeypatch):
    manager = WireGuardServerManager()
    dump = (
        "server-private\tserver-public\t51820\toff\n"
        "peer-public\tpreshared-secret\t198.51.100.8:51820\t10.8.0.5/32\t123\t45\t67\toff\n"
    )

    async def fake_ssh_command(_connection, _command):
        return True, dump, ""

    monkeypatch.setattr(manager, "_run_ssh_command", fake_ssh_command)
    success, peers = await manager._list_peers_via_ssh(
        ServerConnection(server_id="test", public_ip="192.0.2.10")
    )

    assert success is True
    assert peers == [
        {
            "public_key": "peer-public",
            "allowed_ips": "10.8.0.5/32",
            "latest_handshake": 123,
            "transfer_rx": 45,
            "transfer_tx": 67,
        }
    ]
    assert "preshared-secret" not in str(peers)
    assert "198.51.100.8" not in str(peers)


@pytest.mark.asyncio
async def test_manager_exceptions_return_normalized_failures(monkeypatch):
    manager = WireGuardServerManager()

    class FailingClient:
        async def post(self, *_args, **_kwargs):
            raise RuntimeError("token=must-not-escape")

    manager._http_client = FailingClient()
    success, message = await manager._add_peer_via_api(
        ServerConnection(server_id="test", public_ip="192.0.2.10", method="http_api"),
        "A" * 43 + "=",
        "10.8.0.5/32",
    )

    assert success is False
    assert message == "Management API unavailable"
    assert "token" not in message


@pytest.mark.asyncio
async def test_strict_ssh_rejects_missing_or_writable_known_hosts(tmp_path):
    manager = WireGuardServerManager()
    connection = ServerConnection(server_id="test", public_ip="192.0.2.10")

    missing = await manager._run_ssh_command(
        connection,
        "true",
        strict_host_key_checking=True,
        known_hosts_path=str(tmp_path / "missing"),
    )
    assert missing == (False, "", "SSH host verification is not configured")

    writable = tmp_path / "known_hosts"
    writable.write_text("example ssh-ed25519 AAAA\n")
    writable.chmod(0o666)
    unsafe = await manager._run_ssh_command(
        connection,
        "true",
        strict_host_key_checking=True,
        known_hosts_path=str(writable),
    )
    assert unsafe == (
        False,
        "",
        "SSH known-hosts file must not be group or world writable",
    )
