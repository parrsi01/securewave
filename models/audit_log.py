from datetime import datetime

from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, JSON
from sqlalchemy.orm import relationship

from database.base import Base


class AuditLog(Base):
    """Audit log for tracking security-sensitive actions"""
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    action = Column(String, nullable=False, index=True)  # login, logout, vpn_connect, etc.
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)
    resource = Column(String, nullable=True)  # server_id, endpoint, etc.
    status = Column(String, nullable=False)  # success, failure, error
    details = Column(JSON, nullable=True)  # Additional context

    # Relationships
    user = relationship("User", backref="audit_logs")

    def __repr__(self):
        return f"<AuditLog(id={self.id}, action='{self.action}', status='{self.status}', timestamp={self.timestamp})>"
