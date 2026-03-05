from __future__ import annotations

from sqlalchemy.orm import Session

from models.subscription import Subscription
from models.user import User


def get_effective_user_tier(user: User, db: Session) -> str:
    """
    Resolve the canonical effective tier for a user.

    - no active/trialing subscription: free
    - active/trialing premium/ultra: premium
    - active/trialing other plan_id: that plan_id
    """
    subscription = (
        db.query(Subscription)
        .filter(
            Subscription.user_id == user.id,
            Subscription.status.in_(["active", "trialing"]),
        )
        .order_by(Subscription.current_period_end.desc().nullslast())
        .first()
    )
    if not subscription:
        return "free"

    plan_id = (subscription.plan_id or "").strip().lower()
    if not plan_id:
        return "free"
    if plan_id in {"premium", "ultra"}:
        return "premium"
    return plan_id
