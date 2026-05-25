"""
User-facing account endpoints used by the native apps.
"""

import os
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.session import get_db
from models.subscription import Subscription
from models.wireguard_peer import WireGuardPeer
from models.user import User
from services.jwt_service import get_current_user

router = APIRouter(prefix="/api/user", tags=["user"])


def _active_subscription(db: Session, user_id: int) -> Optional[Subscription]:
    return (
        db.query(Subscription)
        .filter(
            Subscription.user_id == user_id,
            Subscription.status.in_(["active", "trialing"]),
        )
        .order_by(Subscription.current_period_end.desc().nullslast())
        .first()
    )


def _bytes_used(db: Session, user_id: int) -> int:
    peers = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user_id,
        )
        .all()
    )
    total = 0
    for p in peers:
        total += (p.total_data_sent or 0) + (p.total_data_received or 0)
    return total


@router.get("/plan")
async def get_user_plan(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Return the user's current plan and usage summary.

    Response shape matches the Flutter app's `UserPlan.fromJson`.
    """
    sub = _active_subscription(db, current_user.id)
    used_gb = _bytes_used(db, current_user.id) / 1024 / 1024 / 1024

    free_cap_gb = float(os.getenv("FREE_TIER_MONTHLY_GB", "5"))
    if not sub:
        return {
            "plan_name": "Free",
            "plan_tier": "free",
            "data_cap_gb": free_cap_gb,
            "used_gb": round(used_gb, 3),
            "renewal_date": None,
        }

    plan_id = (sub.plan_id or "premium").lower()
    # The app currently treats "premium" as the paid/unlimited tier.
    plan_tier = "premium"
    plan_name = sub.plan_name or plan_id.capitalize()

    renewal = sub.current_period_end.isoformat() if sub.current_period_end else None
    return {
        "plan_name": plan_name,
        "plan_tier": plan_tier,
        "data_cap_gb": 0,  # 0 means unlimited in the app UI.
        "used_gb": round(used_gb, 3),
        "renewal_date": renewal,
    }
