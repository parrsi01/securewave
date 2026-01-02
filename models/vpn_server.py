from datetime import datetime

from sqlalchemy import Column, Integer, String, Float, DateTime, Boolean
from sqlalchemy.orm import relationship

from database.base import Base


class VPNServer(Base):
    """VPN server model for tracking server fleet and metrics"""
    __tablename__ = "vpn_servers"

    id = Column(Integer, primary_key=True, index=True)
    server_id = Column(String, unique=True, nullable=False, index=True)  # us-east-1, eu-west-1, etc.
    location = Column(String, nullable=False)  # New York, London, etc.
    region = Column(String, nullable=True)  # Americas, Europe, Asia
    public_ip = Column(String, nullable=False)
    endpoint = Column(String, nullable=False)  # IP:port for WireGuard
    wg_public_key = Column(String, nullable=False)  # Server's WireGuard public key
    wg_private_key_encrypted = Column(String, nullable=False)  # Encrypted private key

    # Capacity and limits
    max_connections = Column(Integer, default=1000)
    tier_restriction = Column(String, nullable=True)  # NULL=all users, 'premium'=premium only

    # Status
    status = Column(String, default="active")  # active, maintenance, offline, demo
    health_status = Column(String, default="unknown")  # healthy, degraded, unhealthy
    last_health_check = Column(DateTime, nullable=True)

    # Real-time metrics (updated by monitoring service)
    current_connections = Column(Integer, default=0)
    cpu_load = Column(Float, default=0.0)  # 0.0 to 1.0
    memory_usage = Column(Float, default=0.0)  # 0.0 to 1.0
    bandwidth_in_mbps = Column(Float, default=0.0)
    bandwidth_out_mbps = Column(Float, default=0.0)
    latency_ms = Column(Float, default=0.0)
    packet_loss = Column(Float, default=0.0)  # 0.0 to 1.0
    jitter_ms = Column(Float, default=0.0)

    # Metadata
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationships
    connections = relationship("VPNConnection", back_populates="server")

    def __repr__(self):
        return f"<VPNServer(id='{self.server_id}', location='{self.location}', status='{self.status}')>"

    @property
    def is_available(self) -> bool:
        """Check if server is available for new connections"""
        return (
            self.status == "active" and
            self.health_status in ["healthy", "degraded"] and
            self.current_connections < self.max_connections
        )

    def to_dict(self):
        """Convert server to dictionary for API responses"""
        return {
            "server_id": self.server_id,
            "location": self.location,
            "region": self.region,
            "public_ip": self.public_ip,
            "endpoint": self.endpoint,
            "status": self.status,
            "health_status": self.health_status,
            "current_connections": self.current_connections,
            "max_connections": self.max_connections,
            "cpu_load": self.cpu_load,
            "latency_ms": self.latency_ms,
            "packet_loss": self.packet_loss,
            "jitter_ms": self.jitter_ms,
            "last_health_check": self.last_health_check.isoformat() if self.last_health_check else None,
        }
