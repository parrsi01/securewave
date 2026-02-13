from __future__ import annotations

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, UniqueConstraint, Index, JSON
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class PaymentIdempotencyKey(Base):
    """
    Stores idempotency state for payment operations initiated by SecureWave.

    This is intentionally provider-agnostic so we can harden payment flows without
    relying on external provider idempotency alone.
    """

    __tablename__ = "payment_idempotency_keys"

    id = Column(Integer, primary_key=True, index=True)

    provider = Column(String(32), nullable=False, index=True)  # e.g., "stripe"
    operation = Column(String(64), nullable=False, index=True)  # e.g., "checkout_session_create"

    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)

    # Stable fingerprint of the request inputs (sha256 hex) to detect misuse.
    request_hash = Column(String(64), nullable=False, index=True)

    # Time bucket (floor(epoch/window_seconds)) to bound idempotency lifetime.
    bucket = Column(Integer, nullable=False, index=True)

    # The idempotency key we also pass to the provider (when supported).
    idempotency_key = Column(String(128), nullable=False, unique=True, index=True)

    status = Column(String(32), nullable=False, default="in_progress", index=True)
    attempt_count = Column(Integer, nullable=False, default=0)

    # Provider/API response payload captured for exact replay.
    response_json = Column(JSON, nullable=True)
    last_error = Column(String(512), nullable=True)

    created_at = Column(DateTime, nullable=False, default=utcnow, index=True)
    updated_at = Column(DateTime, nullable=False, default=utcnow, index=True)

    user = relationship("User")

    __table_args__ = (
        UniqueConstraint(
            "provider",
            "operation",
            "user_id",
            "request_hash",
            "bucket",
            name="uq_payment_idempotency_request_bucket",
        ),
        Index(
            "ix_payment_idempotency_user_op_time",
            "user_id",
            "operation",
            "created_at",
        ),
    )

