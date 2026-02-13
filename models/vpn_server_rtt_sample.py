from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, String, Index
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class VPNServerRTTSample(Base):
    """
    Rolling RTT history samples for VPN servers.

    Notes:
    - This stores *infrastructure* probe RTT (control plane -> VPN node), not end-user RTT.
    - Samples are bounded/cleaned up by TTL in the writer to avoid unbounded growth.
    """

    __tablename__ = "vpn_server_rtt_samples"
    __table_args__ = (
        Index("ix_vpn_server_rtt_samples_server_time", "vpn_server_id", "observed_at"),
    )

    id = Column(Integer, primary_key=True, index=True)
    vpn_server_id = Column(Integer, ForeignKey("vpn_servers.id"), nullable=False, index=True)
    observed_at = Column(DateTime, default=utcnow, nullable=False, index=True)
    rtt_ms = Column(Float, nullable=False)
    source = Column(String, nullable=False, default="health_monitor_ping")

    server = relationship("VPNServer", backref="rtt_samples")

