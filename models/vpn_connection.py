
from sqlalchemy import BigInteger, Column, DateTime, Float, ForeignKey, Index, Integer, String, text
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class VPNConnection(Base):
    """VPN connection tracking for monitoring and quality feedback"""
    __tablename__ = "vpn_connections"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    server_id = Column(Integer, ForeignKey("vpn_servers.id"), nullable=False, index=True)
    device_id = Column(Integer, ForeignKey("wireguard_peers.id"), nullable=True, index=True)
    protocol = Column(String, nullable=False, default="wireguard", server_default="wireguard")

    # A caller-provided key makes start/reconnect retries safe without treating
    # a control-plane record as proof that a client tunnel is established.
    start_idempotency_key = Column(String(128), nullable=True)

    # Connection details
    client_ip = Column(String, nullable=True)  # Allocated VPN IP (10.8.0.x)
    public_ip = Column(String, nullable=True)  # User's public IP
    connected_at = Column(DateTime, default=utcnow, nullable=False, index=True)
    disconnected_at = Column(DateTime, nullable=True)

    # Quality metrics (for optimizer feedback)
    avg_latency_ms = Column(Float, nullable=True)
    avg_throughput_mbps = Column(Float, nullable=True)
    total_bytes_sent = Column(BigInteger, default=0)
    total_bytes_received = Column(BigInteger, default=0)
    last_meter_sequence = Column(BigInteger, nullable=False, default=0, server_default="0")
    last_metered_at = Column(DateTime, nullable=True)
    finalization_idempotency_key = Column(String(128), nullable=True)
    finalization_reason = Column(String(32), nullable=True)

    __table_args__ = (
        Index("uq_vpn_connection_user_start_key", "user_id", "start_idempotency_key", unique=True),
        Index(
            "uq_vpn_connection_active_device",
            "device_id",
            unique=True,
            postgresql_where=text("device_id IS NOT NULL AND disconnected_at IS NULL"),
            sqlite_where=text("device_id IS NOT NULL AND disconnected_at IS NULL"),
        ),
    )

    # Relationships
    user = relationship("User", backref="vpn_connections")
    server = relationship("VPNServer", back_populates="connections")
    device = relationship("WireGuardPeer", backref="vpn_connections")

    def __repr__(self):
        status = "active" if self.disconnected_at is None else "disconnected"
        return f"<VPNConnection(id={self.id}, user_id={self.user_id}, server_id={self.server_id}, status='{status}')>"

    @property
    def is_active(self) -> bool:
        """Check if connection is currently active"""
        return self.disconnected_at is None

    @property
    def duration_seconds(self) -> int:
        """Calculate connection duration in seconds"""
        if self.disconnected_at:
            return int((self.disconnected_at - self.connected_at).total_seconds())
        else:
            return int((utcnow() - self.connected_at).total_seconds())

    def to_dict(self):
        """Convert connection to dictionary for API responses"""
        return {
            "id": self.id,
            "user_id": self.user_id,
            "server_id": self.server_id,
            "client_ip": self.client_ip,
            "connected_at": self.connected_at.isoformat() if self.connected_at else None,
            "disconnected_at": self.disconnected_at.isoformat() if self.disconnected_at else None,
            "is_active": self.is_active,
            "duration_seconds": self.duration_seconds,
            "avg_latency_ms": self.avg_latency_ms,
            "avg_throughput_mbps": self.avg_throughput_mbps,
        }
