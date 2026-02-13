"""
JWT blacklist token model for access/refresh token revocation.
"""

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class JWTBlacklistToken(Base):
    __tablename__ = "jwt_blacklist_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    token_jti = Column(String(64), nullable=False, unique=True, index=True)
    token_type = Column(String(16), nullable=False, index=True)  # access | refresh
    reason = Column(String(128), nullable=True)
    revoked_at = Column(DateTime, nullable=False, default=utcnow, index=True)
    expires_at = Column(DateTime, nullable=False, index=True)

    user = relationship("User", backref="jwt_blacklist_entries")
