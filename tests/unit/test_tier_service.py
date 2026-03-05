from datetime import datetime, timedelta

from models.subscription import Subscription
from services.tier_service import get_effective_user_tier


def _create_subscription(db, user, *, plan_id: str, status: str) -> Subscription:
    sub = Subscription(
        user_id=user.id,
        plan_id=plan_id,
        plan_name=plan_id.capitalize(),
        provider="stripe",
        status=status,
        amount=0.0,
        current_period_end=datetime.utcnow() + timedelta(days=30),
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    return sub


def test_user_with_no_subscription_is_free(db, test_user):
    assert get_effective_user_tier(test_user, db) == "free"


def test_user_with_inactive_subscription_is_free(db, test_user):
    _create_subscription(db, test_user, plan_id="premium", status="canceled")
    assert get_effective_user_tier(test_user, db) == "free"


def test_user_with_active_premium_is_premium(db, test_user):
    _create_subscription(db, test_user, plan_id="premium", status="active")
    assert get_effective_user_tier(test_user, db) == "premium"


def test_user_with_active_ultra_maps_to_premium(db, test_user):
    _create_subscription(db, test_user, plan_id="ultra", status="active")
    assert get_effective_user_tier(test_user, db) == "premium"


def test_user_with_active_basic_is_basic(db, test_user):
    _create_subscription(db, test_user, plan_id="basic", status="active")
    assert get_effective_user_tier(test_user, db) == "basic"
