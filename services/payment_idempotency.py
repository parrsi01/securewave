from __future__ import annotations

import hashlib
import json
import os
import uuid
from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional, Tuple

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from models.payment_idempotency_key import PaymentIdempotencyKey
from utils.api_errors import ApiException
from utils.time_utils import utcnow


def _stable_json_dumps(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def request_hash_from_payload(payload: Dict[str, Any]) -> str:
    return sha256_hex(_stable_json_dumps(payload).encode("utf-8"))


def _idempotency_window_seconds() -> int:
    raw = os.getenv("PAYMENT_IDEMPOTENCY_WINDOW_SECONDS", "60")
    try:
        val = int(raw)
    except Exception:
        val = 60
    return max(10, min(val, 3600))


def _idempotency_stale_after_seconds() -> int:
    raw = os.getenv("PAYMENT_IDEMPOTENCY_STALE_AFTER_SECONDS", "30")
    try:
        val = int(raw)
    except Exception:
        val = 30
    return max(5, min(val, 3600))


def _make_key(provider: str, operation: str) -> str:
    # Stripe's idempotency key limit is 255; keep ours short and ASCII.
    return f"sw_{provider}_{operation}_{uuid.uuid4().hex}"


@dataclass(frozen=True)
class IdempotencyOutcome:
    response: Dict[str, Any]
    replayed: bool


def run_idempotent(
    db: Session,
    *,
    provider: str,
    operation: str,
    user_id: int,
    request_payload: Dict[str, Any],
    execute: Callable[[str], Dict[str, Any]],
) -> IdempotencyOutcome:
    """
    Execute a payment operation idempotently within a short time window.

    - Prevents double-submits (same user + request fingerprint within window).
    - Persists the provider idempotency key and response for exact replay.
    - If a prior attempt is still in-progress, returns 409 to avoid retry storms.
    """
    window_s = _idempotency_window_seconds()
    stale_after_s = _idempotency_stale_after_seconds()
    now = utcnow()
    bucket = int(now.timestamp() // window_s)
    req_hash = request_hash_from_payload(request_payload)

    # Harden checkout flow against concurrent conflicting requests for the
    # same user in the same idempotency bucket.
    if operation == "checkout_session_create":
        inflight = (
            db.query(PaymentIdempotencyKey)
            .filter_by(
                provider=provider,
                operation=operation,
                user_id=user_id,
                bucket=bucket,
                status="in_progress",
            )
            .order_by(PaymentIdempotencyKey.created_at.desc())
            .first()
        )
        if inflight and inflight.request_hash != req_hash:
            age_s = (now - (inflight.updated_at or inflight.created_at)).total_seconds()
            if age_s < stale_after_s:
                raise ApiException(
                    status_code=409,
                    code="checkout_conflict_in_progress",
                    message="Another checkout request is currently in progress.",
                    details={"provider": provider, "operation": operation},
                )

    record = PaymentIdempotencyKey(
        provider=provider,
        operation=operation,
        user_id=user_id,
        request_hash=req_hash,
        bucket=bucket,
        idempotency_key=_make_key(provider, operation),
        status="in_progress",
        attempt_count=1,
        created_at=now,
        updated_at=now,
    )

    created = False
    try:
        db.add(record)
        db.commit()
        db.refresh(record)
        created = True
    except IntegrityError:
        db.rollback()
        record = (
            db.query(PaymentIdempotencyKey)
            .filter_by(
                provider=provider,
                operation=operation,
                user_id=user_id,
                request_hash=req_hash,
                bucket=bucket,
            )
            .order_by(PaymentIdempotencyKey.created_at.desc())
            .first()
        )
        if not record:
            raise

    if record.status == "succeeded" and isinstance(record.response_json, dict):
        return IdempotencyOutcome(response=record.response_json, replayed=True)

    if record.status == "in_progress" and not created:
        # Another request already reserved this bucket. If it's stale, we can retry.
        age_s = (now - (record.updated_at or record.created_at)).total_seconds()
        if age_s < stale_after_s:
            raise ApiException(
                status_code=409,
                code="idempotency_in_progress",
                message="Request already in progress. Please retry shortly.",
                details={"provider": provider, "operation": operation},
            )

    # Retry path: reuse the same provider idempotency key so Stripe is protected too.
    record.status = "in_progress"
    record.attempt_count = int(record.attempt_count or 0) + (0 if created else 1)
    record.last_error = None
    record.updated_at = now
    db.add(record)
    db.commit()

    try:
        response = execute(record.idempotency_key)
    except Exception as exc:
        record.status = "failed"
        record.last_error = str(exc)[:512]
        record.updated_at = utcnow()
        db.add(record)
        db.commit()
        raise

    record.status = "succeeded"
    record.response_json = response
    record.updated_at = utcnow()
    db.add(record)
    db.commit()

    return IdempotencyOutcome(response=response, replayed=False)
