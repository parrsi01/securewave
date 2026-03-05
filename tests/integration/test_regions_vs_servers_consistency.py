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


def _server_ids_from_servers(payload: dict) -> set[str]:
    return {item["server_id"] for item in payload["servers"]}


def _server_ids_from_regions(payload: dict) -> set[str]:
    server_ids: set[str] = set()
    for item in payload["regions"]:
        if isinstance(item, dict) and item.get("server_id"):
            server_ids.add(str(item["server_id"]))
            continue
        if isinstance(item, dict):
            for nested in item.get("servers") or []:
                if isinstance(nested, dict) and nested.get("server_id"):
                    server_ids.add(str(nested["server_id"]))
    return server_ids


def test_free_and_paid_catalogs_match_between_servers_and_regions(client, db):
    ensure_default_servers(db)

    free_user = _create_user(db, email="regions-consistency-free@securewave.dev")
    premium_user = _create_user(db, email="regions-consistency-premium@securewave.dev")
    _create_subscription(db, user=premium_user, plan_id="premium")

    cases = (
        auth_headers_for_user(free_user),
        auth_headers_for_user(premium_user),
    )

    for headers in cases:
        servers_resp = client.get("/api/vpn/servers", headers=headers)
        regions_resp = client.get("/api/vpn/regions", headers=headers)

        assert servers_resp.status_code == 200, servers_resp.text
        assert regions_resp.status_code == 200, regions_resp.text

        server_ids = _server_ids_from_servers(servers_resp.json())
        region_ids = _server_ids_from_regions(regions_resp.json())

        assert region_ids == server_ids
