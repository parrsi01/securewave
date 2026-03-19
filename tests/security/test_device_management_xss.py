import base64
import secrets

from models.wireguard_peer import WireGuardPeer
from models.user import User


def _login_cookie_session(client, email: str, password: str):
    resp = client.post(
        "/api/auth/login",
        json={"email": email, "password": password},
    )
    assert resp.status_code == 200, resp.text
    csrf = resp.json().get("csrf_token") or resp.cookies.get("csrf_token")
    assert csrf
    return csrf


def test_device_rename_rejects_html_payload(client, db, test_user):
    csrf = _login_cookie_session(client, test_user.email, "TestPass123")

    peer = WireGuardPeer(
        user_id=test_user.id,
        public_key=base64.b64encode(secrets.token_bytes(32)).decode(),
        private_key_encrypted="enc",
        ipv4_address="10.8.0.10",
        device_name="SafeDevice",
        is_active=True,
        is_revoked=False,
        device_state="active",
    )
    db.add(peer)
    db.commit()
    db.refresh(peer)

    payload = {"name": "<img src=x onerror=alert(1)>"}
    resp = client.patch(
        f"/api/vpn/devices/{peer.id}",
        json=payload,
        headers={"X-CSRF-Token": csrf},
    )
    assert resp.status_code == 422, resp.text

    db.refresh(peer)
    assert peer.device_name == "SafeDevice"

