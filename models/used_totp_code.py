"""
Model for tracking used TOTP codes to prevent replay attacks within the 90s validity window.
"""

from datetime import datetime

from sqlalchemy import Column, DateTime, Index, Integer, String

from database.base import Base


class UsedTotpCode(Base):
    __tablename__ = "used_totp_codes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, nullable=False, index=True)
    # TOTP codes are 6-digit strings
    code = Column(String(6), nullable=False)
    used_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    __table_args__ = (
        # Composite index to make replay-check lookup fast: filter by user_id + code + used_at
        Index("ix_used_totp_codes_user_code_time", "user_id", "code", "used_at"),
    )
