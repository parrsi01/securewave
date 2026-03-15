from __future__ import annotations

from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer


class _FakeWireGuardManager:
    def __init__(self) -> None:
        self.add_calls: list[tuple[str, str]] = []
        self.remove_calls: list[str] = []

    async def add_peer(self, conn, public_key: str, allowed_ips: str):
        self.add_calls.append((public_key, allowed_ips))
        return True, "ok"

    async def remove_peer(self, conn, public_key: str):
        self.remove_calls.append(public_key)
        return True, "ok"


def _seed_server(db, *, server_id: str = "devices-ash-1") -> VPNServer:
    server = VPNServer(
        server_id=server_id,
        location="Ashburn",
        country="United States",
        country_code="US",
        city="Ashburn",
        region="Americas",
        hcloud_location="ash",
        public_ip="198.51.100.60",
        endpoint="198.51.100.60:51820",
        wg_public_key="dGVzdC1kZXZpY2Utc2VydmVyLXB1YmxpYy1rZXktMDEyMzQ1",
        wg_private_key_encrypted="encrypted-private-key",
        allowed_ips="0.0.0.0/0, ::/0",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
        max_connections=1000,
        current_connections=0,
        performance_score=99.0,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_device_create_registers_peer_on_server(client, premium_auth_headers, db, monkeypatch):
    server = _seed_server(db)
    fake_manager = _FakeWireGuardManager()
    monkeypatch.setattr("routes.devices.get_wireguard_server_manager", lambda: fake_manager)

    response = client.post(
        "/api/vpn/devices",
        headers=premium_auth_headers,
        json={
            "name": "QA Laptop",
            "device_type": "linux",
            "server_id": server.server_id,
        },
    )
    assert response.status_code == 201, response.text
    payload = response.json()
    assert payload["server_id"] == server.server_id
    assert len(fake_manager.add_calls) == 1

    peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == payload["id"]).first()
    assert peer is not None
    assert fake_manager.add_calls[0][0] == peer.public_key
    assert fake_manager.add_calls[0][1] == peer.ipv4_address


def test_device_delete_revokes_peer_and_cleans_remote_registration(
    client,
    premium_auth_headers,
    db,
    monkeypatch,
):
    server = _seed_server(db, server_id="devices-ash-2")
    fake_manager = _FakeWireGuardManager()
    monkeypatch.setattr("routes.devices.get_wireguard_server_manager", lambda: fake_manager)
    monkeypatch.setattr("services.device_service.get_wireguard_server_manager", lambda: fake_manager)

    created = client.post(
        "/api/vpn/devices",
        headers=premium_auth_headers,
        json={
            "name": "Delete Me",
            "device_type": "linux",
            "server_id": server.server_id,
        },
    )
    assert created.status_code == 201, created.text
    device_id = int(created.json()["id"])

    delete = client.delete(f"/api/vpn/devices/{device_id}", headers=premium_auth_headers)
    assert delete.status_code == 204, delete.text

    peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == device_id).first()
    assert peer is not None
    assert peer.is_revoked is True
    assert len(fake_manager.remove_calls) == 1
    assert fake_manager.remove_calls[0] == peer.public_key


def test_add_device_with_invalid_server_id_returns_404(client, premium_auth_headers):
    response = client.post(
        "/api/vpn/devices",
        headers=premium_auth_headers,
        json={
            "name": "Broken Device",
            "device_type": "linux",
            "server_id": "missing-server-id",
        },
    )
    assert response.status_code == 404
    body = response.json()
    assert body["error"]["code"] == "not_found"
    assert body["error"]["message"] == "Not found"
