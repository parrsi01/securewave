from __future__ import annotations

from datetime import datetime, timedelta

from models.subscription import Subscription
from models.usage_analytics import UserUsageStats
from models.user import User
from models.vpn_server import VPNServer
from services.hashing_service import hash_password
from services.server_bootstrap import ensure_default_servers
from tests.helpers.auth import auth_headers_for_user


FREE_CAP_BYTES = 5 * 1024 * 1024 * 1024


def _create_user(db, *, email: str) -> User:
    user = User(
        email=email,
        hashed_password=hash_password("SecureWave!Test123"),
        email_verified=True,
        is_active=True,
        is_admin=False,
        created_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _create_subscription(db, *, user: User, plan_id: str) -> Subscription:
    now = datetime.utcnow()
    sub = Subscription(
        user_id=user.id,
        plan_id=plan_id,
        plan_name=plan_id.capitalize(),
        provider="stripe",
        status="active",
        amount=9.99,
        currency="USD",
        billing_cycle="monthly",
        activated_at=now,
        current_period_start=now,
        current_period_end=now + timedelta(days=30),
        next_billing_date=now + timedelta(days=30),
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    return sub


def _seed_healthy_default_servers(db) -> str:
    ensure_default_servers(db)
    servers = db.query(VPNServer).all()
    for server in servers:
        server.health_status = "healthy"
        server.hcloud_server_state = "running"
        db.add(server)
    db.commit()
    return "de-nue-1"


def _set_used_bytes(db, *, user: User, used_bytes: int) -> None:
    usage = (
        db.query(UserUsageStats)
        .filter(UserUsageStats.user_id == user.id)
        .first()
    )
    if not usage:
        usage = UserUsageStats(
            user_id=user.id,
            total_connections=0,
            active_connections=0,
        )
    usage.total_bytes_uploaded = 0
    usage.total_bytes_downloaded = int(used_bytes)
    usage.total_data_gb = float(used_bytes) / (1024 * 1024 * 1024)
    usage.current_month_data_gb = usage.total_data_gb
    db.add(usage)
    db.commit()


def test_free_user_under_cap_can_request_profile(client, db, monkeypatch):
    monkeypatch.setenv("FREE_TIER_MONTHLY_GB", "5")
    free_server_id = _seed_healthy_default_servers(db)
    user = _create_user(db, email="usage-cap-free-allowed@securewave.dev")
    _set_used_bytes(db, user=user, used_bytes=FREE_CAP_BYTES - 1)

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers_for_user(user),
        json={
            "device_name": "Under Cap Free Linux Device",
            "device_type": "linux",
            "server_id": free_server_id,
            "protocol": "wireguard",
        },
    )

    assert response.status_code == 200, response.text
    assert response.json()["server_id"] == free_server_id


def test_free_user_over_cap_cannot_request_profile(client, db, monkeypatch):
    monkeypatch.setenv("FREE_TIER_MONTHLY_GB", "5")
    free_server_id = _seed_healthy_default_servers(db)
    user = _create_user(db, email="usage-cap-free-denied@securewave.dev")
    _set_used_bytes(db, user=user, used_bytes=FREE_CAP_BYTES)

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers_for_user(user),
        json={
            "device_name": "Capped Free Linux Device",
            "device_type": "linux",
            "server_id": free_server_id,
            "protocol": "wireguard",
        },
    )

    assert response.status_code == 403, response.text
    payload = response.json()
    assert payload["error"]["code"] == "quota_exceeded"


def test_premium_user_over_free_cap_can_still_request_profile(client, db, monkeypatch):
    monkeypatch.setenv("FREE_TIER_MONTHLY_GB", "5")
    free_server_id = _seed_healthy_default_servers(db)
    user = _create_user(db, email="usage-cap-premium-allowed@securewave.dev")
    _create_subscription(db, user=user, plan_id="premium")
    _set_used_bytes(db, user=user, used_bytes=FREE_CAP_BYTES)

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers_for_user(user),
        json={
            "device_name": "Paid Linux Device",
            "device_type": "linux",
            "server_id": free_server_id,
            "protocol": "wireguard",
        },
    )

    assert response.status_code == 200, response.text
    assert response.json()["server_id"] == free_server_id
