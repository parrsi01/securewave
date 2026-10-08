"""Account-scoped UTC monthly usage from the durable metering ledger.

Version 2 events are cumulative checkpoints, not increments. Aggregate the
highest counters in this month and subtract the preceding checkpoint for each
session. Version 1 events are increments. Never add peer/kernel snapshots to
this ledger: that would charge the same traffic twice.
"""
from datetime import datetime, timezone

from sqlalchemy import func

from models.subscription import Subscription
from models.vpn_connection import VPNConnection
from models.vpn_usage_event import VPNUsageEvent

FREE_MONTHLY_BYTES = 5_000_000_000  # Decimal GB, also used by the app formatter.


def month_bounds(now=None):
    now = now or datetime.now(timezone.utc)
    if now.tzinfo is not None:
        now = now.astimezone(timezone.utc).replace(tzinfo=None)
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    end = start.replace(year=start.year + 1, month=1) if start.month == 12 else start.replace(month=start.month + 1)
    return start, end


def monthly_totals(db, user_id, now=None):
    start, end = month_bounds(now)
    event = VPNUsageEvent
    current = (db.query(event.connection_id.label("connection_id"),
                       func.max(event.bytes_sent).label("sent"),
                       func.max(event.bytes_received).label("received"))
               .join(VPNConnection, VPNConnection.id == event.connection_id)
               .filter(event.user_id == user_id, VPNConnection.user_id == user_id,
                       VPNConnection.metering_version == 2,
                       event.created_at >= start, event.created_at < end)
               .group_by(event.connection_id).subquery())
    preceding = (db.query(event.connection_id.label("connection_id"),
                         func.max(event.bytes_sent).label("sent"),
                         func.max(event.bytes_received).label("received"))
                 .join(current, current.c.connection_id == event.connection_id)
                 .filter(event.user_id == user_id, event.created_at < start)
                 .group_by(event.connection_id).subquery())
    sent, received = (db.query(
        func.coalesce(func.sum(current.c.sent - func.coalesce(preceding.c.sent, 0)), 0),
        func.coalesce(func.sum(current.c.received - func.coalesce(preceding.c.received, 0)), 0))
        .select_from(current).outerjoin(preceding, preceding.c.connection_id == current.c.connection_id).one())
    legacy_sent, legacy_received = (db.query(
        func.coalesce(func.sum(event.bytes_sent), 0),
        func.coalesce(func.sum(event.bytes_received), 0))
        .join(VPNConnection, VPNConnection.id == event.connection_id)
        .filter(event.user_id == user_id, VPNConnection.user_id == user_id,
                VPNConnection.metering_version == 1,
                event.created_at >= start, event.created_at < end).one())
    return int(sent + legacy_sent), int(received + legacy_received)


def account_plan(db, user_id):
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    sub = (db.query(Subscription).filter(
        Subscription.user_id == user_id, Subscription.status.in_(["active", "trialing"]),
        Subscription.plan_id.in_(["basic", "premium", "pro", "ultra"]),
    ).order_by(Subscription.current_period_end.desc().nullslast()).first())
    if sub and (sub.current_period_end is None or sub.current_period_end > now):
        return sub.plan_id, sub.plan_name
    return "free", "Free"


def _session(row):
    return {"session_id": row.id, "bytes_sent": int(row.total_bytes_sent or 0),
            "bytes_received": int(row.total_bytes_received or 0),
            "connected_at": row.connected_at.isoformat() + "Z",
            "disconnected_at": row.disconnected_at.isoformat() + "Z" if row.disconnected_at else None,
            "recording_quality": row.recording_quality}


def monthly_summary(db, user, session_ids=(), now=None):
    start, end = month_bounds(now)
    sent, received = monthly_totals(db, user.id, now)
    plan_id, plan_name = account_plan(db, user.id)
    quota = FREE_MONTHLY_BYTES if plan_id == "free" else None
    latest = (db.query(VPNConnection).filter(VPNConnection.user_id == user.id)
              .order_by(VPNConnection.id.desc()).first())
    # Explicit IDs allow the app to subtract acknowledged counters from its
    # own pending final observations. Every lookup still checks account owner.
    tracked = (db.query(VPNConnection).filter(VPNConnection.user_id == user.id,
               VPNConnection.id.in_(set(session_ids))).all()) if session_ids else []
    return {"user_id": user.id, "email": user.email,
            "plan_id": plan_id, "plan_name": plan_name,
            "period_start": start.isoformat() + "Z", "period_end": end.isoformat() + "Z",
            "bytes_sent": sent, "bytes_received": received, "used_bytes": sent + received,
            "quota_bytes": quota, "remaining_bytes": max(0, quota - sent - received) if quota is not None else None,
            "limit_reached": quota is not None and sent + received >= quota,
            "last_session": _session(latest) if latest else None,
            "tracked_sessions": [_session(row) for row in tracked],
            "accounting": "upload_plus_download", "units": "decimal",
            "updated_at": datetime.now(timezone.utc).isoformat()}
