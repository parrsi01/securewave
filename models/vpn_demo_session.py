from datetime import datetime

from sqlalchemy import Column, Integer, String, DateTime

from database.base import Base
from utils.time_utils import utcnow


class VPNDemoSession(Base):
    __tablename__ = "vpn_demo_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True, unique=True, nullable=False)
    status = Column(String, default="DISCONNECTED")
    region = Column(String, nullable=True)
    assigned_node = Column(String, nullable=True)
    mock_ip = Column(String, nullable=True)
    connected_since = Column(DateTime, nullable=True)
    last_error = Column(String, nullable=True)
    updated_at = Column(DateTime, default=utcnow)
    created_at = Column(DateTime, default=utcnow)
