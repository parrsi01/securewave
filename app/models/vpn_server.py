from datetime import datetime

from sqlalchemy import Column, Integer, String, Boolean, DateTime

from app.db.base import Base


class VPNServer(Base):
    __tablename__ = "vpn_servers"

    id = Column(Integer, primary_key=True, index=True)
    server_id = Column(String, unique=True, index=True, nullable=False)
    location = Column(String, nullable=False)
    region = Column(String, nullable=True)
    endpoint = Column(String, nullable=False)
    wg_public_key = Column(String, nullable=False)
    dns = Column(String, default="1.1.1.1")
    allowed_ips = Column(String, default="0.0.0.0/0, ::/0")
    persistent_keepalive = Column(String, default="25")
    status = Column(String, default="active")
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow)
