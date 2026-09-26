from typing import Dict, Optional

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import relationship

from database.base import Base
from utils.time_utils import utcnow


class Subscription(Base):
    """Simple plan/status record used by VPN access checks."""

    __tablename__ = "subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    plan_id = Column(String, nullable=False, server_default="free", index=True)
    plan_name = Column(String, nullable=False, server_default="Free")
    status = Column(String, default="active", index=True)
    created_at = Column(DateTime, default=utcnow, nullable=False, server_default=func.now())
    activated_at = Column(DateTime, nullable=True)
    current_period_start = Column(DateTime, nullable=True)
    current_period_end = Column(DateTime, nullable=True)
    expires_at = Column(DateTime, nullable=True)
    canceled_at = Column(DateTime, nullable=True)
    cancel_at_period_end = Column(Boolean, default=False)

    user = relationship("User", back_populates="subscriptions")

    def __repr__(self):
        return f"<Subscription(id={self.id}, user_id={self.user_id}, plan={self.plan_id}, status={self.status})>"

    @property
    def is_active(self) -> bool:
        return self.status in {"active", "trialing"}

    @property
    def is_trial(self) -> bool:
        return self.status == "trialing"

    @property
    def is_canceled(self) -> bool:
        return self.status == "canceled" or self.canceled_at is not None

    @property
    def days_until_renewal(self) -> Optional[int]:
        if not self.current_period_end:
            return None
        return (self.current_period_end - utcnow()).days

    def to_dict(self, include_sensitive: bool = False) -> Dict:
        return {
            "id": self.id,
            "user_id": self.user_id,
            "plan_id": self.plan_id,
            "plan_name": self.plan_name,
            "status": self.status,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "activated_at": self.activated_at.isoformat() if self.activated_at else None,
            "current_period_end": self.current_period_end.isoformat() if self.current_period_end else None,
            "cancel_at_period_end": self.cancel_at_period_end,
            "canceled_at": self.canceled_at.isoformat() if self.canceled_at else None,
            "is_active": self.is_active,
            "is_trial": self.is_trial,
            "days_until_renewal": self.days_until_renewal,
        }
