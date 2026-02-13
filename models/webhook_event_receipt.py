from __future__ import annotations

from sqlalchemy import Column, DateTime, Integer, String, UniqueConstraint, Index

from database.base import Base
from utils.time_utils import utcnow


class WebhookEventReceipt(Base):
    """
    Tracks processed webhook events for replay protection and auditability.

    Stores only minimal metadata (no raw payloads) to avoid sensitive data
    persistence while still enabling idempotent processing.
    """

    __tablename__ = "webhook_event_receipts"

    id = Column(Integer, primary_key=True, index=True)

    provider = Column(String(32), nullable=False, index=True)  # e.g., "stripe"
    event_id = Column(String(255), nullable=False)
    event_type = Column(String(128), nullable=True, index=True)

    status = Column(String(32), nullable=False, default="received", index=True)
    attempt_count = Column(Integer, nullable=False, default=0)

    payload_hash = Column(String(64), nullable=True)
    last_error = Column(String(512), nullable=True)

    received_at = Column(DateTime, nullable=False, default=utcnow, index=True)
    processed_at = Column(DateTime, nullable=True, index=True)

    __table_args__ = (
        UniqueConstraint("provider", "event_id", name="uq_webhook_provider_event"),
        Index("ix_webhook_receipts_provider_time", "provider", "received_at"),
    )

