from __future__ import annotations

from datetime import datetime, timedelta

from models.subscription import Subscription
from models.user import User
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


def test_free_user_server_catalog_is_limited_to_two_non_premium_servers(client, db):
    ensure_default_servers(db)
    user = _create_user(db, email="server-filter-free@securewave.dev")

    response = client.get("/api/vpn/servers", headers=auth_headers_for_user(user))

    assert response.status_code == 200, response.text
    payload = response.json()
    servers = payload["servers"]
    assert len(servers) == 2
    assert all(item["premium_only"] is False for item in servers)
    assert {item["server_id"] for item in servers} == {"de-nue-1", "de-fra-1"}
    assert len({item["server_id"] for item in servers}) == len(servers)


def test_active_premium_user_receives_all_five_servers(client, db):
    ensure_default_servers(db)
    user = _create_user(db, email="server-filter-premium@securewave.dev")
    _create_subscription(db, user=user, plan_id="premium")

    response = client.get("/api/vpn/servers", headers=auth_headers_for_user(user))

    assert response.status_code == 200, response.text
    payload = response.json()
    servers = payload["servers"]
    assert len(servers) == 5
    assert len({item["server_id"] for item in servers}) == len(servers)


def test_active_basic_user_is_treated_as_paid_for_server_catalog(client, db):
    ensure_default_servers(db)
    user = _create_user(db, email="server-filter-basic@securewave.dev")
    _create_subscription(db, user=user, plan_id="basic")

    response = client.get("/api/vpn/servers", headers=auth_headers_for_user(user))

    assert response.status_code == 200, response.text
    payload = response.json()
    servers = payload["servers"]
    assert len(servers) == 5
    assert len({item["server_id"] for item in servers}) == len(servers)
