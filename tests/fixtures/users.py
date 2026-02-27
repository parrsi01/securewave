from __future__ import annotations

from datetime import datetime, timedelta

import pytest

from models.subscription import Subscription
from models.user import User
from services.hashing_service import hash_password
from tests.helpers.auth import auth_headers_for_user


FREE_TEST_EMAIL = "free_test@securewave.dev"
PREMIUM_TEST_EMAIL = "premium_test@securewave.dev"
TEST_PASSWORD = "SecureWave!Test123"


def _get_or_create_user(db, *, email: str) -> User:
    user = db.query(User).filter(User.email == email).first()
    if user:
        return user
    user = User(
        email=email,
        hashed_password=hash_password(TEST_PASSWORD),
        email_verified=True,
        is_active=True,
        is_admin=False,
        created_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _ensure_premium_subscription(db, *, user: User) -> Subscription:
    existing = (
        db.query(Subscription)
        .filter(
            Subscription.user_id == user.id,
            Subscription.status.in_(["active", "trialing"]),
        )
        .first()
    )
    if existing:
        return existing

    now = datetime.utcnow()
    sub = Subscription(
        user_id=user.id,
        plan_id="premium",
        plan_name="Premium",
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


@pytest.fixture
def free_user(db) -> User:
    return _get_or_create_user(db, email=FREE_TEST_EMAIL)


@pytest.fixture
def premium_user(db) -> User:
    user = _get_or_create_user(db, email=PREMIUM_TEST_EMAIL)
    _ensure_premium_subscription(db, user=user)
    return user


@pytest.fixture
def free_auth_headers(free_user) -> dict[str, str]:
    return auth_headers_for_user(free_user)


@pytest.fixture
def premium_auth_headers(premium_user) -> dict[str, str]:
    return auth_headers_for_user(premium_user)

