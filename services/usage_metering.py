"""Current-period VPN usage accounting helpers."""

import os
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

from models.subscription import Subscription
from models.usage_analytics import DailyUsageMetrics
from models.user import User
from models.wireguard_peer import WireGuardPeer

BYTES_PER_MIB = 1024 * 1024
BYTES_PER_GIB = 1024 * 1024 * 1024
ACTIVE_SUBSCRIPTION_STATUSES = ("active", "trialing")


@dataclass(frozen=True)
class UsagePeriod:
    start: datetime
    end: datetime
    subscription: Optional[Subscription]


def active_subscription(db: Session, user_id: int) -> Optional[Subscription]:
    return (
        db.query(Subscription)
        .filter(
            Subscription.user_id == user_id,
            Subscription.status.in_(ACTIVE_SUBSCRIPTION_STATUSES),
        )
        .order_by(Subscription.current_period_end.desc().nullslast())
        .first()
    )


def _start_of_day(value: datetime) -> datetime:
    return datetime(value.year, value.month, value.day)


def _next_month(value: datetime) -> datetime:
    if value.month == 12:
        return datetime(value.year + 1, 1, 1)
    return datetime(value.year, value.month + 1, 1)


def _period_end_day(value: datetime) -> datetime:
    return _start_of_day(value) + timedelta(days=1)


def current_usage_period(
    db: Session,
    user_id: int,
    *,
    now: Optional[datetime] = None,
) -> UsagePeriod:
    """Return the billing/current-month period used for plan usage display."""
    now = now or datetime.utcnow()
    sub = active_subscription(db, user_id)
    if sub and sub.current_period_start and sub.current_period_end:
        return UsagePeriod(
            start=_start_of_day(sub.current_period_start),
            end=_period_end_day(sub.current_period_end),
            subscription=sub,
        )

    start = datetime(now.year, now.month, 1)
    return UsagePeriod(start=start, end=_next_month(start), subscription=sub)


def lifetime_peer_usage_bytes(db: Session, user_id: int) -> int:
    peers = db.query(WireGuardPeer).filter(WireGuardPeer.user_id == user_id).all()
    return sum(
        (p.total_data_sent or 0) + (p.total_data_received or 0) for p in peers
    )


def current_period_usage_bytes(
    db: Session,
    user_id: int,
    *,
    period: Optional[UsagePeriod] = None,
) -> int:
    period = period or current_usage_period(db, user_id)
    row_count, total_mb = (
        db.query(
            func.count(DailyUsageMetrics.id),
            func.coalesce(func.sum(DailyUsageMetrics.total_data_mb), 0.0),
        )
        .filter(
            DailyUsageMetrics.user_id == user_id,
            DailyUsageMetrics.date >= period.start,
            DailyUsageMetrics.date < period.end,
        )
        .one()
    )
    if row_count == 0:
        return lifetime_peer_usage_bytes(db, user_id)
    return int(round(float(total_mb or 0.0) * BYTES_PER_MIB))


def record_usage_delta(
    db: Session,
    *,
    user_id: int,
    rx_bytes: int,
    tx_bytes: int,
    server_id: Optional[str] = None,
    when: Optional[datetime] = None,
) -> DailyUsageMetrics:
    """Persist a compact daily aggregate for current-period usage display."""
    when = when or datetime.utcnow()
    usage_date = _start_of_day(when)
    metrics = (
        db.query(DailyUsageMetrics)
        .filter(
            DailyUsageMetrics.user_id == user_id,
            DailyUsageMetrics.date == usage_date,
        )
        .first()
    )
    if metrics is None:
        metrics = DailyUsageMetrics(user_id=user_id, date=usage_date)
        db.add(metrics)

    uploaded_mb = max(0, tx_bytes) / BYTES_PER_MIB
    downloaded_mb = max(0, rx_bytes) / BYTES_PER_MIB
    metrics.data_uploaded_mb = (metrics.data_uploaded_mb or 0.0) + uploaded_mb
    metrics.data_downloaded_mb = (
        metrics.data_downloaded_mb or 0.0
    ) + downloaded_mb
    metrics.total_data_mb = (
        metrics.total_data_mb or 0.0
    ) + uploaded_mb + downloaded_mb

    if server_id:
        servers_used = list(metrics.servers_used or [])
        if server_id not in servers_used:
            servers_used.append(server_id)
        metrics.servers_used = servers_used

    return metrics


def plan_payload(db: Session, user: User) -> dict:
    period = current_usage_period(db, user.id)
    sub = period.subscription
    used_gb = (
        current_period_usage_bytes(db, user.id, period=period) / BYTES_PER_GIB
    )
    free_cap_gb = float(os.getenv("FREE_TIER_MONTHLY_GB", "5"))
    if not sub:
        return {
            "plan_name": "Free",
            "plan_tier": "free",
            "data_cap_gb": free_cap_gb,
            "used_gb": round(used_gb, 3),
            "renewal_date": None,
        }

    return {
        "plan_name": sub.plan_name or (sub.plan_id or "premium").capitalize(),
        "plan_tier": "premium",
        "data_cap_gb": 0,
        "used_gb": round(used_gb, 3),
        "renewal_date": sub.current_period_end.isoformat()
        if sub.current_period_end
        else None,
    }
