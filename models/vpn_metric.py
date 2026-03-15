from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, String, Index
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class VPNMetric(Base):
    """Client-reported VPN connection quality metrics."""

    __tablename__ = "vpn_metrics"
    __table_args__ = (
        Index("ix_vpn_metrics_user_time", "user_id", "recorded_at"),
        Index("ix_vpn_metrics_server_time", "server_id", "recorded_at"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(Integer, nullable=True)
    server_id = Column(String, nullable=False, index=True)

    # Metrics
    handshake_time_ms = Column(Float, nullable=True)
    latency_ms = Column(Float, nullable=True)
    packet_loss_pct = Column(Float, nullable=True)
    throughput_mbps = Column(Float, nullable=True)

    # Context
    protocol = Column(String, nullable=False, default="wireguard")
    recorded_at = Column(DateTime, default=utcnow, nullable=False, index=True)

    user = relationship("User", backref="vpn_metrics")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "user_id": self.user_id,
            "device_id": self.device_id,
            "server_id": self.server_id,
            "handshake_time_ms": self.handshake_time_ms,
            "latency_ms": self.latency_ms,
            "packet_loss_pct": self.packet_loss_pct,
            "throughput_mbps": self.throughput_mbps,
            "protocol": self.protocol,
            "recorded_at": self.recorded_at.isoformat() if self.recorded_at else None,
        }
