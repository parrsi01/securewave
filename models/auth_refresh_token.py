"""
Refresh token session model for rotating JWT refresh tokens safely.
"""

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class AuthRefreshToken(Base):
    __tablename__ = "auth_refresh_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    token_jti = Column(String(64), nullable=False, unique=True, index=True)
    user_agent = Column(String(512), nullable=True)
    ip_address = Column(String(64), nullable=True)
    issued_at = Column(DateTime, default=utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=False, index=True)
    revoked_at = Column(DateTime, nullable=True, index=True)
    replaced_by_jti = Column(String(64), nullable=True, index=True)

    user = relationship("User", backref="refresh_sessions")
