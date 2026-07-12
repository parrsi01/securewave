from datetime import datetime, timedelta

import pytest
from fastapi import HTTPException

from models.subscription import Subscription
from models.wireguard_peer import WireGuardPeer
from services import subscription_access


def _subscription(user_id: int, **overrides) -> Subscription:
    values = {
        "user_id": user_id,
        "plan_id": "basic",
        "plan_name": "Basic",
        "provider": "stripe",
        "status": "active",
        "amount": 9.0,
        "currency": "USD",
    }
    values.update(overrides)
    return Subscription(**values)


def _peer(user_id: int, **overrides) -> WireGuardPeer:
    values = {
        "user_id": user_id,
        "public_key": f"peer-{user_id}",
        "private_key_encrypted": "encrypted-test-key",
        "ipv4_address": f"10.8.0.{user_id + 20}/32",
        "device_name": "Subscription test device",
        "is_active": True,
        "is_revoked": False,
        "total_data_sent": 0,
        "total_data_received": 0,
    }
    values.update(overrides)
    return WireGuardPeer(**values)


@pytest.mark.asyncio
async def test_free_tier_under_cap_is_allowed(db, test_user, monkeypatch):
    monkeypatch.setattr(subscription_access, "DEMO_MODE", False)
    monkeypatch.setattr(subscription_access, "WG_MOCK_MODE", False)

    result = await subscription_access.require_active_subscription(db, test_user)

    assert result is None


@pytest.mark.asyncio
async def test_free_tier_cap_revokes_peers_and_fails_closed(db, test_user, monkeypatch):
    monkeypatch.setattr(subscription_access, "DEMO_MODE", True)
    monkeypatch.setattr(subscription_access, "WG_MOCK_MODE", False)
    monkeypatch.setattr(subscription_access, "FREE_TIER_MONTHLY_BYTES", 100)
    peer = _peer(test_user.id, total_data_sent=60, total_data_received=40)
    db.add(peer)
    db.commit()

    with pytest.raises(HTTPException) as exc_info:
        await subscription_access.enforce_free_tier_cap(db, test_user)

    assert exc_info.value.status_code == 402
    db.refresh(peer)
    assert peer.is_revoked is True
    assert peer.is_active is False
    assert peer.revoked_at is not None


@pytest.mark.asyncio
async def test_expired_paid_subscription_is_revoked_and_rejected(db, test_user, monkeypatch):
    monkeypatch.setattr(subscription_access, "DEMO_MODE", False)
    monkeypatch.setattr(subscription_access, "WG_MOCK_MODE", False)
    subscription = _subscription(
        test_user.id,
        current_period_end=datetime.utcnow() - timedelta(minutes=1),
    )
    db.add(subscription)
    db.commit()

    with pytest.raises(HTTPException) as exc_info:
        await subscription_access.require_active_subscription(db, test_user)

    assert exc_info.value.status_code == 402
    db.refresh(subscription)
    assert subscription.status == "expired"


@pytest.mark.asyncio
async def test_active_paid_subscription_is_returned(db, test_user, monkeypatch):
    monkeypatch.setattr(subscription_access, "DEMO_MODE", False)
    monkeypatch.setattr(subscription_access, "WG_MOCK_MODE", False)
    subscription = _subscription(
        test_user.id,
        plan_id="premium",
        plan_name="Premium",
        current_period_end=datetime.utcnow() + timedelta(days=30),
    )
    db.add(subscription)
    db.commit()

    result = await subscription_access.require_active_subscription(db, test_user)

    assert result is subscription


def test_effective_device_limits_follow_plan_and_admin_boundaries(db, test_user):
    assert subscription_access.get_effective_device_limit(db, test_user) == 1

    subscription = _subscription(test_user.id, plan_id="basic")
    db.add(subscription)
    db.commit()
    assert subscription_access.get_effective_device_limit(db, test_user) == 3

    subscription.plan_id = "premium"
    db.commit()
    assert subscription_access.get_effective_device_limit(db, test_user) == 5

    subscription.plan_id = "ultra"
    db.commit()
    assert subscription_access.get_effective_device_limit(db, test_user) == 10

    test_user.is_admin = True
    db.commit()
    assert subscription_access.get_effective_device_limit(db, test_user) == 100
