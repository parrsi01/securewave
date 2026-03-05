from __future__ import annotations

from datetime import datetime, timedelta

from models.subscription import Subscription
from models.user import User
from models.vpn_server import VPNServer
from services.hashing_service import hash_password
from services.server_bootstrap import ensure_default_servers
from tests.helpers.auth import auth_headers_for_user


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


def _seed_healthy_default_servers(db) -> list[VPNServer]:
    ensure_default_servers(db)
    servers = db.query(VPNServer).all()
    for server in servers:
        server.health_status = "healthy"
        server.hcloud_server_state = "running"
        db.add(server)
    db.commit()
    return servers


def _premium_server_ids(db) -> list[str]:
    servers = _seed_healthy_default_servers(db)
    premium_ids = [
        str(server.server_id)
        for server in servers
        if (server.tier_restriction or "").strip().lower() == "premium"
    ]
    assert len(premium_ids) == 3
    return premium_ids


def test_free_user_cannot_request_profile_for_seeded_premium_server(client, db):
    premium_server_id = _premium_server_ids(db)[0]
    user = _create_user(db, email="profile-tier-free@securewave.dev")

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers_for_user(user),
        json={
            "device_name": "Free Linux Device",
            "device_type": "linux",
            "server_id": premium_server_id,
            "protocol": "wireguard",
        },
    )

    assert response.status_code == 403, response.text
    payload = response.json()
    assert payload["error"]["code"] == "server_tier_restricted"


def test_premium_user_can_request_profile_for_seeded_premium_server(client, db):
    premium_server_id = _premium_server_ids(db)[0]
    user = _create_user(db, email="profile-tier-premium@securewave.dev")
    _create_subscription(db, user=user, plan_id="premium")

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers_for_user(user),
        json={
            "device_name": "Premium Linux Device",
            "device_type": "linux",
            "server_id": premium_server_id,
            "protocol": "wireguard",
        },
    )

    assert response.status_code == 200, response.text
    assert response.json()["server_id"] == premium_server_id


def test_basic_user_is_treated_as_paid_for_premium_profile_request(client, db):
    premium_server_id = _premium_server_ids(db)[0]
    user = _create_user(db, email="profile-tier-basic@securewave.dev")
    _create_subscription(db, user=user, plan_id="basic")

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers_for_user(user),
        json={
            "device_name": "Basic Linux Device",
            "device_type": "linux",
            "server_id": premium_server_id,
            "protocol": "wireguard",
        },
    )

    assert response.status_code == 200, response.text
    assert response.json()["server_id"] == premium_server_id
