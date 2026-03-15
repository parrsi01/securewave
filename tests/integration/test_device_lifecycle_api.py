from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer


class _StubWireGuardManager:
    def __init__(self) -> None:
        self.add_calls: list[dict[str, str]] = []
        self.remove_calls: list[dict[str, str]] = []

    async def add_peer(self, conn, public_key: str, allowed_ips: str):
        self.add_calls.append(
            {
                "server_id": str(conn.server_id),
                "public_key": public_key,
                "allowed_ips": allowed_ips,
            }
        )
        return True, "peer added"

    async def remove_peer(self, conn, public_key: str):
        self.remove_calls.append(
            {
                "server_id": str(conn.server_id),
                "public_key": public_key,
            }
        )
        return True, "peer removed"


def _seed_server(db, *, server_id: str = "device-us-1", ip: str = "198.51.100.41") -> VPNServer:
    server = VPNServer(
        server_id=server_id,
        location="Ashburn",
        country="United States",
        country_code="US",
        city="Ashburn",
        region="Americas",
        hcloud_location="ash",
        public_ip=ip,
        endpoint=f"{ip}:51820",
        wg_public_key="ZGV2aWNlLWFwaS1zZXJ2ZXItd2lyZWd1YXJkLWtleS0wMTIzNDU2Nw==",
        wg_private_key_encrypted="encrypted-private-key",
        allowed_ips="0.0.0.0/0, ::/0",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
        performance_score=97.0,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_create_device_registers_peer_on_selected_server(client, auth_headers, db, monkeypatch):
    server = _seed_server(db)
    manager = _StubWireGuardManager()
    monkeypatch.setattr("routes.devices.get_wireguard_server_manager", lambda: manager)

    response = client.post(
        "/api/vpn/devices",
        headers=auth_headers,
        json={
            "name": "QA Laptop",
            "device_type": "linux",
            "server_id": server.server_id,
        },
    )
    assert response.status_code == 201, response.text
    payload = response.json()

    peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == payload["id"]).first()
    assert peer is not None
    assert payload["server_id"] == server.server_id
    assert payload["device_state"] == "active"
    assert peer.server_id == server.id
    assert manager.add_calls == [
        {
            "server_id": server.server_id,
            "public_key": peer.public_key,
            "allowed_ips": peer.ipv4_address,
        }
    ]


def test_delete_device_revokes_peer_and_cleans_up_remote_server(client, auth_headers, db, monkeypatch):
    server = _seed_server(db, server_id="device-us-2", ip="198.51.100.42")
    manager = _StubWireGuardManager()
    monkeypatch.setattr("routes.devices.get_wireguard_server_manager", lambda: manager)
    monkeypatch.setattr("services.device_service.get_wireguard_server_manager", lambda: manager)

    created = client.post(
        "/api/vpn/devices",
        headers=auth_headers,
        json={
            "name": "Primary Laptop",
            "device_type": "linux",
            "server_id": server.server_id,
        },
    )
    assert created.status_code == 201, created.text
    device_id = created.json()["id"]

    peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == device_id).first()
    assert peer is not None
    public_key = peer.public_key

    revoked = client.delete(f"/api/vpn/devices/{device_id}", headers=auth_headers)
    assert revoked.status_code == 204, revoked.text

    db.refresh(peer)
    assert peer.is_revoked is True
    assert peer.device_state == "revoked"
    assert peer.is_active is False
    assert manager.remove_calls[-1] == {
        "server_id": server.server_id,
        "public_key": public_key,
    }


def test_create_device_rejects_unknown_server_id(client, auth_headers):
    response = client.post(
        "/api/vpn/devices",
        headers=auth_headers,
        json={
            "name": "Ghost Device",
            "device_type": "linux",
            "server_id": "missing-server",
        },
    )
    assert response.status_code == 404
    payload = response.json()
    assert payload["error"]["code"] == "not_found"
    assert payload["error"]["message"] in {"Not found", "Server not found"}
