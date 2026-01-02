from datetime import datetime

from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, BigInteger
from sqlalchemy.orm import relationship

from database.base import Base


class VPNConnection(Base):
    """VPN connection tracking for monitoring and quality feedback"""
    __tablename__ = "vpn_connections"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    server_id = Column(Integer, ForeignKey("vpn_servers.id"), nullable=False, index=True)

    # Connection details
    client_ip = Column(String, nullable=True)  # Allocated VPN IP (10.8.0.x)
    public_ip = Column(String, nullable=True)  # User's public IP
    connected_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    disconnected_at = Column(DateTime, nullable=True)

    # Quality metrics (for optimizer feedback)
    avg_latency_ms = Column(Float, nullable=True)
    avg_throughput_mbps = Column(Float, nullable=True)
    total_bytes_sent = Column(BigInteger, default=0)
    total_bytes_received = Column(BigInteger, default=0)

    # Relationships
    user = relationship("User", backref="vpn_connections")
    server = relationship("VPNServer", back_populates="connections")

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
            return int((datetime.utcnow() - self.connected_at).total_seconds())

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
