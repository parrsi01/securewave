from fastapi import status

from models.user import User
from models.wireguard_peer import WireGuardPeer
from services.jwt_service import create_access_token
from services.hashing_service import hash_password


def test_device_config_acl_isolated(client, db):
    user_a = User(email="usera@example.com", hashed_password="hash", email_verified=True, is_active=True)
    user_b = User(email="userb@example.com", hashed_password="hash", email_verified=True, is_active=True)
    db.add_all([user_a, user_b])
    db.commit()
    db.refresh(user_a)
    db.refresh(user_b)

    peer = WireGuardPeer(
        user_id=user_a.id,
        public_key="public-key-a",
        private_key_encrypted="encrypted-key-a",
        ipv4_address="10.8.0.10/32",
        device_name="UserA Device",
    )
    db.add(peer)
    db.commit()
    db.refresh(peer)

    token_b = create_access_token(user_b)
    headers_b = {"Authorization": f"Bearer {token_b}"}
    response = client.get(f"/api/vpn/devices/{peer.id}/config", headers=headers_b)
    assert response.status_code == status.HTTP_404_NOT_FOUND


def test_device_limits_route_is_not_shadowed_by_dynamic_device_route(client, auth_headers):
    response = client.get("/api/vpn/devices/limits/info", headers=auth_headers)
    assert response.status_code == status.HTTP_200_OK
    assert {"limit", "used", "remaining"} <= response.json().keys()


def test_profile_cannot_use_another_accounts_device(client, db, test_user, auth_headers, test_vpn_server):
    other = User(
        email="foreign-device-owner@example.com",
        hashed_password=hash_password("ForeignPass123"),
        email_verified=True,
        is_active=True,
    )
    db.add(other)
    db.commit()
    foreign_peer = WireGuardPeer(
        user_id=other.id,
        public_key="foreign-device-public-key",
        private_key_encrypted="encrypted-foreign-key",
        ipv4_address="10.8.0.201/32",
        device_name="Foreign device",
        is_active=True,
        is_revoked=False,
    )
    db.add(foreign_peer)
    db.commit()

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={"device_id": foreign_peer.id, "server_id": test_vpn_server.server_id},
    )
    assert response.status_code == status.HTTP_404_NOT_FOUND
    assert "wireguard_config" not in response.text


def test_device_registration_failure_does_not_leave_an_active_assignment(
    client, db, auth_headers, test_vpn_server, monkeypatch
):
    import routes.devices as device_routes

    async def fail_registration(server, peer):
        raise device_routes.HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="VPN peer registration could not be confirmed.",
        )

    monkeypatch.setattr(device_routes, "_register_peer_or_raise", fail_registration)
    response = client.post(
        "/api/vpn/devices",
        headers=auth_headers,
        json={"name": "Unconfirmed registration", "server_id": test_vpn_server.server_id},
    )
    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    peer = db.query(WireGuardPeer).filter(
        WireGuardPeer.device_name == "Unconfirmed registration"
    ).one()
    assert peer.is_active is False
    assert peer.server_id is None


def test_device_profile_rotation_and_revocation_lifecycle(
    client, auth_headers, test_vpn_server
):
    created = client.post(
        "/api/vpn/devices",
        headers=auth_headers,
        json={
            "name": "Certification Linux device",
            "device_type": "linux",
            "server_id": test_vpn_server.server_id,
        },
    )
    assert created.status_code == status.HTTP_201_CREATED, created.text
    device = created.json()
    device_id = device["id"]
    assert device["key_version"] == 1

    first_profile = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={"device_id": device_id, "server_id": test_vpn_server.server_id},
    )
    assert first_profile.status_code == status.HTTP_200_OK, first_profile.text
    first_config = first_profile.json()["wireguard_config"]

    rotated = client.post(
        f"/api/vpn/devices/{device_id}/rotate-keys",
        headers=auth_headers,
    )
    assert rotated.status_code == status.HTTP_200_OK, rotated.text
    assert rotated.json()["key_version"] == 2

    reconnected = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={"device_id": device_id, "server_id": test_vpn_server.server_id},
    )
    assert reconnected.status_code == status.HTTP_200_OK, reconnected.text
    assert reconnected.json()["wireguard_config"] != first_config

    revoked = client.delete(
        f"/api/vpn/devices/{device_id}",
        headers=auth_headers,
    )
    assert revoked.status_code == status.HTTP_204_NO_CONTENT

    blocked = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={"device_id": device_id, "server_id": test_vpn_server.server_id},
    )
    assert blocked.status_code == status.HTTP_404_NOT_FOUND
