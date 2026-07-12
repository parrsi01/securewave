"""Idempotency ledger for client-reported VPN usage increments."""


from sqlalchemy import BigInteger, Column, DateTime, ForeignKey, Index, Integer, String

from database.base import Base
from utils.time_utils import utcnow


class VPNUsageEvent(Base):
    """A compact event ledger; it intentionally stores counters, not destinations."""

    __tablename__ = "vpn_usage_events"
    __table_args__ = (
        Index("uq_vpn_usage_event_user_key", "user_id", "idempotency_key", unique=True),
    )

    id = Column(Integer, primary_key=True, index=True)
    connection_id = Column(Integer, ForeignKey("vpn_connections.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    idempotency_key = Column(String(128), nullable=False)
    sequence = Column(BigInteger, nullable=False)
    bytes_sent = Column(BigInteger, nullable=False, default=0)
    bytes_received = Column(BigInteger, nullable=False, default=0)
    created_at = Column(DateTime, nullable=False, default=utcnow)
