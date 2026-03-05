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
from models.usage_analytics import UserUsageStats
from models.vpn_connection import VPNConnection
from models.wireguard_peer import WireGuardPeer
from models.user import User
from services.jwt_service import get_current_user
from services.tier_service import get_effective_user_tier
from services.tunnel_runtime import get_tunnel_runtime, is_simulated_tunnel_mode
from utils.time_utils import utcnow

router = APIRouter(prefix="/api/user", tags=["user"])
account_router = APIRouter(prefix="/api/account", tags=["account"])


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
    _sync_simulated_usage(db, user_id)
    peers = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == user_id,
            WireGuardPeer.is_revoked == False,
        )
        .all()
    )
    peer_total = 0
    for p in peers:
        peer_total += (p.total_data_sent or 0) + (p.total_data_received or 0)

    stats = (
        db.query(UserUsageStats)
        .filter(UserUsageStats.user_id == user_id)
        .first()
    )
    stats_total = 0
    if stats:
        stats_total = int(stats.total_bytes_uploaded or 0) + int(stats.total_bytes_downloaded or 0)
    return max(peer_total, stats_total)


def _get_or_create_usage_stats(db: Session, user_id: int) -> UserUsageStats:
    row = (
        db.query(UserUsageStats)
        .filter(UserUsageStats.user_id == user_id)
        .first()
    )
    if row:
        return row
    row = UserUsageStats(
        user_id=user_id,
        total_connections=0,
        active_connections=0,
        total_bytes_uploaded=0,
        total_bytes_downloaded=0,
        total_data_gb=0.0,
        current_month_data_gb=0.0,
        first_seen_at=utcnow(),
        last_activity_at=utcnow(),
    )
    db.add(row)
    db.flush()
    return row


def _sync_simulated_usage(db: Session, user_id: int) -> None:
    if not is_simulated_tunnel_mode():
        return
    runtime = get_tunnel_runtime()
    session_id = runtime.active_session_for_user(user_id)
    if not session_id:
        return
    delta = runtime.pop_traffic_delta(session_id)
    if delta.rx_delta_bytes <= 0 and delta.tx_delta_bytes <= 0:
        return

    usage = _get_or_create_usage_stats(db, user_id)
    usage.total_bytes_downloaded = int(usage.total_bytes_downloaded or 0) + int(delta.rx_delta_bytes)
    usage.total_bytes_uploaded = int(usage.total_bytes_uploaded or 0) + int(delta.tx_delta_bytes)
    total_bytes = int(usage.total_bytes_downloaded or 0) + int(usage.total_bytes_uploaded or 0)
    usage.total_data_gb = float(total_bytes) / (1024 * 1024 * 1024)
    usage.current_month_data_gb = usage.total_data_gb
    usage.last_activity_at = utcnow()
    usage.updated_at = utcnow()
    db.add(usage)

    active_connection = (
        db.query(VPNConnection)
        .filter(
            VPNConnection.user_id == user_id,
            VPNConnection.disconnected_at.is_(None),
        )
        .order_by(VPNConnection.connected_at.desc())
        .first()
    )
    if active_connection:
        active_connection.total_bytes_received = int(active_connection.total_bytes_received or 0) + int(delta.rx_delta_bytes)
        active_connection.total_bytes_sent = int(active_connection.total_bytes_sent or 0) + int(delta.tx_delta_bytes)
        db.add(active_connection)

    db.commit()


def _speed_policy(plan_tier: str) -> tuple[float, float]:
    tier = (plan_tier or "free").strip().lower()
    if tier == "premium":
        down = float(os.getenv("PREMIUM_TIER_SPEED_Mbps_DOWN", "250"))
        up = float(os.getenv("PREMIUM_TIER_SPEED_Mbps_UP", "100"))
        return down, up
    down = float(os.getenv("FREE_TIER_SPEED_Mbps_DOWN", "25"))
    up = float(os.getenv("FREE_TIER_SPEED_Mbps_UP", "10"))
    return down, up


def build_account_usage_payload(db: Session, current_user: User) -> dict[str, object]:
    plan_tier = get_effective_user_tier(current_user, db)
    sub = _active_subscription(db, current_user.id) if plan_tier != "free" else None
    free_cap_gb = float(os.getenv("FREE_TIER_MONTHLY_GB", "5"))
    quota_bytes = 0 if plan_tier != "free" else int(free_cap_gb * 1024 * 1024 * 1024)
    used_bytes = int(_bytes_used(db, current_user.id))
    used_percent = 0.0
    if quota_bytes > 0:
        used_percent = min(100.0, round((used_bytes / quota_bytes) * 100.0, 4))

    devices_count = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.user_id == current_user.id,
            WireGuardPeer.is_revoked == False,
        )
        .count()
    )
    username = (current_user.email or "").split("@", 1)[0] if current_user.email else f"user-{current_user.id}"
    speed_down, speed_up = _speed_policy(plan_tier)
    renewal = sub.current_period_end.isoformat() if sub and sub.current_period_end else None

    return {
        "quota_bytes": quota_bytes,
        "used_bytes": used_bytes,
        "used_percent": used_percent,
        "plan_tier": plan_tier,
        "plan_name": (sub.plan_name or plan_tier.capitalize()) if sub else "Free",
        "data_cap_gb": 0 if plan_tier != "free" else free_cap_gb,
        "used_gb": round(used_bytes / (1024 * 1024 * 1024), 3),
        "speed_limit_mbps_down": speed_down,
        "speed_limit_mbps_up": speed_up,
        "renewal_date": renewal,
        "devices_count": int(devices_count),
        "username": username,
        "display_name": username,
    }


@router.get("/plan")
async def get_user_plan(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Return the user's current plan and usage summary.

    Response shape matches the Flutter app's `UserPlan.fromJson`.
    """
    plan_tier = get_effective_user_tier(current_user, db)
    sub = _active_subscription(db, current_user.id) if plan_tier != "free" else None
    used_gb = _bytes_used(db, current_user.id) / 1024 / 1024 / 1024

    free_cap_gb = float(os.getenv("FREE_TIER_MONTHLY_GB", "5"))
    if plan_tier == "free":
        speed_down, speed_up = _speed_policy("free")
        return {
            "plan_name": "Free",
            "plan_tier": "free",
            "data_cap_gb": free_cap_gb,
            "used_gb": round(used_gb, 3),
            "speed_limit_mbps_down": speed_down,
            "speed_limit_mbps_up": speed_up,
            "renewal_date": None,
        }

    plan_name = sub.plan_name or plan_tier.capitalize()
    speed_down, speed_up = _speed_policy(plan_tier)
    premium_cap_gb = float(os.getenv("PREMIUM_TIER_MONTHLY_GB", "0"))
    data_cap_gb = premium_cap_gb if premium_cap_gb > 0 else 0

    renewal = sub.current_period_end.isoformat() if sub.current_period_end else None
    return {
        "plan_name": plan_name,
        "plan_tier": plan_tier,
        "data_cap_gb": data_cap_gb,  # 0 means unlimited in the app UI.
        "used_gb": round(used_gb, 3),
        "speed_limit_mbps_down": speed_down,
        "speed_limit_mbps_up": speed_up,
        "renewal_date": renewal,
    }


@account_router.get("/usage")
async def get_account_usage(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Canonical usage endpoint for app gauges and simulation harnesses.
    """
    return build_account_usage_payload(db, current_user)
