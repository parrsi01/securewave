from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer


def _server(db, server_id: str, ip: str, score: float):
    server = VPNServer(
        server_id=server_id,
        location="Frankfurt",
        country="Germany",
        country_code="DE",
        city="Frankfurt",
        region="Europe",
        hcloud_location="fsn1",
        public_ip=ip,
        endpoint=f"{ip}:51820",
        wg_public_key="dGVzdC1wZWVyLWxpZmVjeWNsZS13aXJlZ3VhcmQta2V5LTAxMjM0NQ==",
        wg_private_key_encrypted="encrypted-private-key",
        allowed_ips="0.0.0.0/0, ::/0",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
        performance_score=score,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_peer_lifecycle_create_reassign_rotate(client, auth_headers, db):
    s1 = _server(db, "de-fsn1-01", "198.51.100.21", 98.0)
    s2 = _server(db, "de-fsn1-02", "198.51.100.22", 97.0)

    first = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={"device_name": "Primary Laptop", "device_type": "windows", "server_id": s1.server_id},
    )
    assert first.status_code == 200, first.text
    first_json = first.json()
    device_id = first_json["device_id"]
    first_key_version = first_json["key_version"]

    reassigned = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={"device_name": "Primary Laptop", "device_type": "windows", "server_id": s2.server_id},
    )
    assert reassigned.status_code == 200, reassigned.text
    reassigned_json = reassigned.json()
    assert reassigned_json["device_id"] == device_id
    assert reassigned_json["server_id"] == s2.server_id

    rotated = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={
            "device_id": device_id,
            "device_type": "windows",
            "server_id": s2.server_id,
            "force_rotate_keys": True,
        },
    )
    assert rotated.status_code == 200, rotated.text
    rotated_json = rotated.json()
    assert rotated_json["key_version"] == first_key_version + 1
    assert rotated_json["server_id"] == s2.server_id

    peers = db.query(WireGuardPeer).all()
    assert len(peers) == 1
    assert peers[0].server_id == s2.id
    assert peers[0].is_revoked is False
