"""Authentication, device lifecycle, entitlement, and usage contract tests."""

from datetime import datetime, timedelta

from models.subscription import Subscription
from models.wireguard_peer import WireGuardPeer


def _create_subscription(db, user, plan_id="basic", *, expires_at=None):
    subscription = Subscription(
        user_id=user.id,
        plan_id=plan_id,
        plan_name=plan_id.capitalize(),
        provider="stripe",
        status="active",
        amount=9.0,
        currency="USD",
        billing_cycle="monthly",
        current_period_start=datetime.utcnow() - timedelta(days=1),
        current_period_end=expires_at or datetime.utcnow() + timedelta(days=30),
    )
    db.add(subscription)
    db.commit()
    db.refresh(subscription)
    return subscription


def test_login_logout_login_and_refresh_contract(client, test_user):
    login = client.post(
        "/api/auth/login",
        json={"email": test_user.email, "password": "TestPass123"},
    )
    assert login.status_code == 200, login.text
    first_tokens = login.json()
    assert first_tokens["access_token"]
    assert first_tokens["refresh_token"]

    assert client.get("/api/auth/me").status_code == 200

    csrf_token = client.cookies.get("csrf_token")
    assert csrf_token
    logout = client.post("/api/auth/logout", headers={"X-CSRF-Token": csrf_token})
    assert logout.status_code == 200, logout.text

    second_login = client.post(
        "/api/auth/login",
        json={"email": test_user.email, "password": "TestPass123"},
    )
    assert second_login.status_code == 200, second_login.text
    second_tokens = second_login.json()
    assert second_tokens["access_token"]

    refreshed = client.post(
        "/api/auth/refresh",
        json={"refresh_token": second_tokens["refresh_token"]},
    )
    assert refreshed.status_code == 200, refreshed.text
    assert refreshed.json()["access_token"]


def test_logout_invalidates_bearer_access_and_refresh_tokens(client, test_user):
    from services.jwt_service import create_access_token, create_refresh_token

    access_token = create_access_token(test_user)
    refresh_token = create_refresh_token(test_user)
    headers = {"Authorization": f"Bearer {access_token}"}

    logout = client.post("/api/auth/logout", headers=headers)
    assert logout.status_code == 200, logout.text

    assert client.get("/api/auth/me", headers=headers).status_code == 401
    refreshed = client.post(
        "/api/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert refreshed.status_code == 401, refreshed.text


def test_profile_same_device_name_is_stable_across_reauthentication(
    client, auth_headers, db
):
    from tests.integration.test_vpn_profile import _create_free_server

    _create_free_server(db)
    first = client.post(
        "/api/vpn/profile",
        json={"device_name": "Linux device (ABCD)", "device_type": "linux"},
        headers=auth_headers,
    )
    assert first.status_code == 200, first.text

    second = client.post(
        "/api/vpn/profile",
        json={"device_name": "Linux device (ABCD)", "device_type": "linux"},
        headers=auth_headers,
    )
    assert second.status_code == 200, second.text
    assert second.json()["device_id"] == first.json()["device_id"]


def test_profile_duplicate_device_name_is_case_insensitive(
    client, auth_headers, db
):
    from tests.integration.test_vpn_profile import _create_free_server

    _create_free_server(db)
    first = client.post(
        "/api/vpn/profile",
        json={"device_name": "Linux device (ABCD)", "device_type": "linux"},
        headers=auth_headers,
    )
    assert first.status_code == 200, first.text

    second = client.post(
        "/api/vpn/profile",
        json={"device_name": "linux device (abcd)", "device_type": "linux"},
        headers=auth_headers,
    )
    assert second.status_code == 200, second.text
    assert second.json()["device_id"] == first.json()["device_id"]


def test_basic_subscription_limit_matches_profile_and_device_list(
    client, auth_headers, test_user, db
):
    from tests.integration.test_vpn_profile import _create_free_server

    _create_free_server(db)
    _create_subscription(db, test_user, "basic")

    for name in ("Laptop", "Desktop", "Phone"):
        response = client.post(
            "/api/vpn/profile",
            json={"device_name": name, "device_type": "linux"},
            headers=auth_headers,
        )
        assert response.status_code == 200, response.text

    fourth = client.post(
        "/api/vpn/profile",
        json={"device_name": "Tablet", "device_type": "linux"},
        headers=auth_headers,
    )
    assert fourth.status_code == 403, fourth.text

    devices = client.get("/api/vpn/devices", headers=auth_headers)
    assert devices.status_code == 200, devices.text
    assert devices.json()["limit"] == 3
    assert devices.json()["total"] == 3


def test_compatibility_device_creation_rejects_duplicate_names(
    client, auth_headers, test_user, db
):
    _create_subscription(db, test_user, "basic")

    first = client.post(
        "/api/vpn/create-device",
        json={"name": "Workstation", "device_type": "linux"},
        headers=auth_headers,
    )
    assert first.status_code == 200, first.text

    duplicate = client.post(
        "/api/vpn/create-device",
        json={"name": "workstation", "device_type": "linux"},
        headers=auth_headers,
    )
    assert duplicate.status_code == 400, duplicate.text


def test_device_removal_frees_the_active_slot_without_deleting_history(
    client, auth_headers, db
):
    from tests.integration.test_vpn_profile import _create_free_server

    _create_free_server(db)
    first = client.post(
        "/api/vpn/profile",
        json={"device_name": "Removable Laptop", "device_type": "linux"},
        headers=auth_headers,
    )
    assert first.status_code == 200, first.text
    device_id = first.json()["device_id"]

    removed = client.delete(f"/api/vpn/devices/{device_id}", headers=auth_headers)
    assert removed.status_code == 204, removed.text

    replacement = client.post(
        "/api/vpn/profile",
        json={"device_name": "Replacement Laptop", "device_type": "linux"},
        headers=auth_headers,
    )
    assert replacement.status_code == 200, replacement.text
    assert replacement.json()["device_id"] != device_id

    db_peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == device_id).one()
    assert db_peer.is_revoked is True
    assert db_peer.is_active is False


def test_expired_subscription_denies_access_and_revokes_peers(
    client, auth_headers, test_user, db, monkeypatch
):
    from tests.integration.test_vpn_profile import _create_free_server
    import services.subscription_access as subscription_access

    _create_free_server(db)
    monkeypatch.setattr(subscription_access, "DEMO_MODE", False)
    monkeypatch.setattr(subscription_access, "WG_MOCK_MODE", False)
    subscription = _create_subscription(
        db, test_user, "basic", expires_at=datetime.utcnow() - timedelta(minutes=1)
    )
    peer = WireGuardPeer(
        user_id=test_user.id,
        public_key="expired-subscription-peer",
        private_key_encrypted="encrypted-key",
        ipv4_address="10.8.0.44/32",
        device_name="Old Laptop",
        is_active=True,
        is_revoked=False,
    )
    db.add(peer)
    db.commit()

    response = client.post(
        "/api/vpn/profile",
        json={"device_name": "New Laptop", "device_type": "linux"},
        headers=auth_headers,
    )
    assert response.status_code == 402, response.text
    db.refresh(subscription)
    db.refresh(peer)
    assert subscription.status == "expired"
    assert peer.is_revoked is True
    assert peer.is_active is False


def test_usage_and_plan_use_peer_byte_counters(client, auth_headers, test_user, db):
    peer = WireGuardPeer(
        user_id=test_user.id,
        public_key="usage-peer",
        private_key_encrypted="encrypted-key",
        ipv4_address="10.8.0.45/32",
        device_name="Usage Laptop",
        total_data_sent=2 * 1024 * 1024,
        total_data_received=3 * 1024 * 1024,
        is_active=True,
        is_revoked=False,
    )
    db.add(peer)
    db.commit()

    usage = client.get("/api/vpn/usage", headers=auth_headers)
    assert usage.status_code == 200, usage.text
    usage_data = usage.json()
    assert usage_data["total_devices"] == 1
    assert usage_data["total_data_sent_mb"] == 2
    assert usage_data["total_data_received_mb"] == 3
    assert usage_data["cap_gb"] == 5
    assert usage_data["remaining_gb"] == 5

    plan = client.get("/api/user/plan", headers=auth_headers)
    assert plan.status_code == 200, plan.text
    assert plan.json()["used_gb"] == round(5 / 1024, 3)
