from sqlalchemy import Boolean, Column, DateTime, Index, Integer, String, UniqueConstraint, func

from database.base import Base
from utils.time_utils import utcnow


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    created_at = Column(DateTime, default=utcnow)
    is_active = Column(Boolean, default=True)
    # Historical account, billing, and verification columns remain in the
    # Alembic history; Beta 1 does not load them into the active ORM.
    auth_token_version = Column(Integer, nullable=False, default=0, server_default="0")

    __table_args__ = (
        UniqueConstraint("email"),
        Index("uq_users_email_lower", func.lower(email), unique=True),
    )
