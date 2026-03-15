import routes.diagnostics as diagnostics_routes

from models.wireguard_peer import WireGuardPeer


class _StubWireGuardManager:
    def __init__(self):
        self.add_calls: list[dict[str, str]] = []
        self.remove_calls: list[dict[str, str]] = []
        self.status_calls: list[str] = []

    async def add_peer(self, conn, public_key: str, allowed_ips: str):
        self.add_calls.append(
            {
                "server_id": conn.server_id,
                "public_key": public_key,
                "allowed_ips": allowed_ips,
            }
        )
        return True, "peer added"

    async def remove_peer(self, conn, public_key: str):
        self.remove_calls.append(
            {
                "server_id": conn.server_id,
                "public_key": public_key,
            }
        )
        return True, "peer removed"

    async def get_server_status(self, conn):
        self.status_calls.append(conn.server_id)
        return True, {
            "cpu_load": 0.52,
            "memory_percent": 37,
            "peer_count": 4,
            "latest_handshake": 1700000000,
        }


def test_telemetry_round_trip_and_summary(client, auth_headers, test_vpn_server):
    diagnostics_routes._telemetry_store.clear()
    try:
        single = client.post(
            "/api/diagnostics/telemetry",
            headers=auth_headers,
            json={
                "latency_ms": 42.5,
                "packet_loss": 0.01,
                "jitter_ms": 3.2,
                "uptime_seconds": 600,
                "bytes_sent": 1024,
                "bytes_received": 2048,
                "server_id": test_vpn_server.server_id,
                "connection_quality": "good",
            },
        )
        assert single.status_code == 200, single.text
        assert single.json()["status"] == "accepted"

        batch = client.post(
            "/api/diagnostics/telemetry/batch",
            headers=auth_headers,
            json={
                "records": [
                    {
                        "latency_ms": 40.0,
                        "packet_loss": 0.0,
                        "jitter_ms": 2.0,
                        "uptime_seconds": 1200,
                        "server_id": test_vpn_server.server_id,
                    },
                    {
                        "latency_ms": 44.0,
                        "packet_loss": 0.02,
                        "jitter_ms": 4.0,
                        "uptime_seconds": 1800,
                        "server_id": test_vpn_server.server_id,
                    },
                ]
            },
        )
        assert batch.status_code == 200, batch.text
        assert batch.json()["records_accepted"] == 2

        session = client.get("/api/diagnostics/debug/session", headers=auth_headers)
        assert session.status_code == 200, session.text
        payload = session.json()
        assert payload["telemetry_store_size"] == 3
        assert len(payload["recent_telemetry"]) == 3
        assert {item["server_id"] for item in payload["recent_telemetry"]} == {test_vpn_server.server_id}

        summary = client.get("/api/diagnostics/summary", headers=auth_headers)
        assert summary.status_code == 200, summary.text
        assert summary.json()["telemetry_enabled"] is True
    finally:
        diagnostics_routes._telemetry_store.clear()


def test_device_create_and_revoke_sync_remote_peer(
    client,
    auth_headers,
    test_subscription,
    test_vpn_server,
    db,
    monkeypatch,
):
    manager = _StubWireGuardManager()
    monkeypatch.setattr("routes.devices.get_wireguard_server_manager", lambda: manager)
    monkeypatch.setattr("services.device_service.get_wireguard_server_manager", lambda: manager)

    create = client.post(
        "/api/vpn/devices",
        headers=auth_headers,
        json={
            "name": "QA Laptop",
            "device_type": "linux",
            "server_id": test_vpn_server.server_id,
        },
    )
    assert create.status_code == 201, create.text
    created = create.json()

    peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == created["id"]).first()
    assert peer is not None
    assert peer.server_id == test_vpn_server.id
    assert len(manager.add_calls) == 1
    assert manager.add_calls[0]["server_id"] == test_vpn_server.server_id
    assert manager.add_calls[0]["public_key"] == peer.public_key
    assert manager.add_calls[0]["allowed_ips"] == peer.ipv4_address

    revoke = client.delete(f"/api/vpn/devices/{peer.id}", headers=auth_headers)
    assert revoke.status_code == 204, revoke.text

    db.refresh(peer)
    assert peer.is_revoked is True
    assert len(manager.remove_calls) == 1
    assert manager.remove_calls[0]["server_id"] == test_vpn_server.server_id
    assert manager.remove_calls[0]["public_key"] == peer.public_key


def test_profile_generation_rejects_unknown_server_id(client, auth_headers):
    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={
            "device_name": "Missing Server Laptop",
            "device_type": "linux",
            "server_id": "does-not-exist",
            "protocol": "wireguard",
        },
    )
    assert response.status_code == 404
    payload = response.json()
    assert payload["error"]["code"] in {"not_found", "server_not_found"}


def test_admin_server_metrics_requires_admin_and_updates_server_state(
    client,
    auth_headers,
    admin_auth_headers,
    test_vpn_server,
    db,
    monkeypatch,
):
    manager = _StubWireGuardManager()
    monkeypatch.setattr("routes.servers.get_wireguard_server_manager", lambda: manager)

    forbidden = client.get(
        f"/api/admin/servers/{test_vpn_server.server_id}/metrics",
        headers=auth_headers,
    )
    assert forbidden.status_code == 403

    response = client.get(
        f"/api/admin/servers/{test_vpn_server.server_id}/metrics",
        headers=admin_auth_headers,
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["server_id"] == test_vpn_server.server_id
    assert payload["metrics"]["peer_count"] == 4
    assert manager.status_calls == [test_vpn_server.server_id]

    db.refresh(test_vpn_server)
    assert test_vpn_server.current_connections == 4
    assert test_vpn_server.cpu_load == 0.52
    assert test_vpn_server.memory_usage == 0.37
