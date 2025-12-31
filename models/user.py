from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, Integer, String
from sqlalchemy.orm import relationship

from database.base import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)
    wg_public_key = Column(String, nullable=True)
    wg_private_key_encrypted = Column(String, nullable=True)
    subscription_status = Column(String, default="inactive")
    stripe_customer_id = Column(String, nullable=True)
    paypal_subscription_id = Column(String, nullable=True)

    subscriptions = relationship("Subscription", back_populates="user")
