from fastapi import status

from models.user import User
from models.wireguard_peer import WireGuardPeer
from services.jwt_service import create_access_token


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
