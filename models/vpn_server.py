from sqlalchemy import Boolean, Column, DateTime, Integer, String, UniqueConstraint

from database.base import Base
from utils.time_utils import utcnow


class VPNServer(Base):
    """The one active WireGuard target used by the beta API."""

    __tablename__ = "vpn_servers"
    __table_args__ = (UniqueConstraint("server_id"),)

    id = Column(Integer, primary_key=True, index=True)
    server_id = Column(String, unique=True, nullable=False, index=True)
    city = Column(String, nullable=False)
    country = Column(String, nullable=False)
    public_ip = Column(String, nullable=False)
    endpoint = Column(String, nullable=False)
    wg_listen_port = Column(Integer, default=51820)
    wg_public_key = Column(String, nullable=False)
    wg_private_key_encrypted = Column(String, nullable=False)
    dns_servers = Column(String, default="1.1.1.1,1.0.0.1")
    allowed_ips = Column(String, default="0.0.0.0/0, ::/0")
    supports_wireguard = Column(Boolean, default=True)
    status = Column(String, default="provisioning")
    health_status = Column(String, default="unknown")
    created_at = Column(DateTime, default=utcnow, nullable=False)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)

    def __repr__(self) -> str:
        return f"<VPNServer(server_id={self.server_id!r}, status={self.status!r})>"
