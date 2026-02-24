from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, Optional, Set


KNOWN_SUBSCRIPTION_STATUSES: Set[str] = {
    "active",
    "trialing",
    "past_due",
    "unpaid",
    "incomplete",
    "incomplete_expired",
    "canceled",
    "expired",
    "pending_approval",
}

ACTIVE_LIKE_STATUSES: Set[str] = {"active", "trialing"}

ALLOWED_TRANSITIONS: Dict[str, Set[str]] = {
    "incomplete": {"trialing", "active", "incomplete_expired", "canceled"},
    "incomplete_expired": {"canceled"},
    "pending_approval": {"active", "canceled", "expired", "incomplete"},
    "trialing": {"active", "past_due", "canceled", "expired"},
    "active": {"past_due", "unpaid", "canceled", "expired"},
    "past_due": {"active", "unpaid", "canceled", "expired"},
    "unpaid": {"active", "canceled", "expired"},
    "expired": {"active", "canceled"},
    "canceled": {"active"},  # re-subscribe/reactivate paths
}


@dataclass(frozen=True)
class SubscriptionTransitionResult:
    applied: bool
    previous_status: str
    target_status: str
    reason: str
    stale_event: bool = False
    blocked: bool = False


def normalize_subscription_status(raw_status: Optional[str], *, default: str = "incomplete") -> str:
    status = (raw_status or "").strip().lower()
    if not status:
        return default
    if status in KNOWN_SUBSCRIPTION_STATUSES:
        return status
    return default


def _extra_data_dict(subscription) -> Dict[str, Any]:
    data = getattr(subscription, "extra_data", None)
    if isinstance(data, dict):
        return dict(data)
    return {}


def transition_subscription_status(
    subscription,
    target_status: str,
    *,
    source: str,
    event_created: Optional[int] = None,
    force: bool = False,
) -> SubscriptionTransitionResult:
    """
    Apply a guarded subscription-status transition.

    - Blocks illegal transitions unless ``force=True``.
    - Drops stale webhook updates using ``event_created`` monotonicity.
    - Persists transition metadata in ``subscription.extra_data``.
    """
    previous = normalize_subscription_status(getattr(subscription, "status", None), default="incomplete")
    target = normalize_subscription_status(target_status, default=previous)
    now = datetime.utcnow()

    extra = _extra_data_dict(subscription)
    last_event_created = int(extra.get("last_event_created") or 0)
    if event_created is not None:
        try:
            incoming_event_created = int(event_created)
        except Exception:
            incoming_event_created = None
        if incoming_event_created is not None and last_event_created and incoming_event_created < last_event_created:
            return SubscriptionTransitionResult(
                applied=False,
                previous_status=previous,
                target_status=target,
                reason=(
                    "stale_event_ignored "
                    f"(incoming={incoming_event_created} < last={last_event_created})"
                ),
                stale_event=True,
            )
    else:
        incoming_event_created = None

    allowed = ALLOWED_TRANSITIONS.get(previous, set())
    if not force and target != previous and target not in allowed:
        return SubscriptionTransitionResult(
            applied=False,
            previous_status=previous,
            target_status=target,
            reason=f"transition_not_allowed:{previous}->{target}",
            blocked=True,
        )

    # Apply transition and normalize side effects.
    subscription.status = target
    if target in ACTIVE_LIKE_STATUSES and not getattr(subscription, "activated_at", None):
        subscription.activated_at = now

    if target == "canceled":
        if not getattr(subscription, "canceled_at", None):
            subscription.canceled_at = now
        subscription.cancel_at_period_end = False

    if target in ACTIVE_LIKE_STATUSES:
        # Reactivation path.
        subscription.cancel_at_period_end = False

    if target in {"past_due", "unpaid"}:
        subscription.last_payment_status = "failed"

    extra["last_transition_source"] = source[:128]
    extra["last_transition_at"] = now.isoformat()
    extra["last_transition_from"] = previous
    extra["last_transition_to"] = target
    if incoming_event_created is not None:
        extra["last_event_created"] = incoming_event_created
    subscription.extra_data = extra

    return SubscriptionTransitionResult(
        applied=True,
        previous_status=previous,
        target_status=target,
        reason="applied",
    )
