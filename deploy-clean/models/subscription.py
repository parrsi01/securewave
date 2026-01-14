from datetime import datetime
from typing import Optional, Dict

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Float, Boolean, JSON
from sqlalchemy.orm import relationship

from database.base import Base


class Subscription(Base):
    """
    Production-grade subscription model for payment processing
    Supports Stripe and PayPal with full billing automation
    """
    __tablename__ = "subscriptions"

    # Primary identification
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)

    # Plan details
    plan_id = Column(String, nullable=False, index=True)  # free, basic, premium, ultra
    plan_name = Column(String, nullable=False)  # Display name

    # Payment provider (stripe or paypal)
    provider = Column(String, nullable=False, index=True)

    # Status (active, trialing, past_due, canceled, incomplete, incomplete_expired, unpaid)
    status = Column(String, default="incomplete", index=True)

    # Stripe integration fields
    stripe_customer_id = Column(String, nullable=True, index=True)
    stripe_subscription_id = Column(String, nullable=True, index=True, unique=True)
    stripe_payment_method_id = Column(String, nullable=True)
    stripe_price_id = Column(String, nullable=True)  # Stripe Price ID

    # PayPal integration fields
    paypal_customer_id = Column(String, nullable=True, index=True)
    paypal_subscription_id = Column(String, nullable=True, index=True, unique=True)
    paypal_plan_id = Column(String, nullable=True)

    # Billing details
    amount = Column(Float, nullable=False, default=0.0)  # Subscription amount
    currency = Column(String, default="USD")  # USD, EUR, GBP, etc.
    billing_cycle = Column(String, default="monthly")  # monthly, yearly

    # Important dates
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    activated_at = Column(DateTime, nullable=True)  # When subscription became active
    trial_start = Column(DateTime, nullable=True)
    trial_end = Column(DateTime, nullable=True)
    current_period_start = Column(DateTime, nullable=True)
    current_period_end = Column(DateTime, nullable=True)
    next_billing_date = Column(DateTime, nullable=True, index=True)
    expires_at = Column(DateTime, nullable=True)

    # Cancellation tracking
    canceled_at = Column(DateTime, nullable=True)
    cancel_at_period_end = Column(Boolean, default=False)
    cancellation_reason = Column(String, nullable=True)

    # Payment tracking
    last_payment_date = Column(DateTime, nullable=True)
    last_payment_amount = Column(Float, nullable=True)
    last_payment_status = Column(String, nullable=True)  # succeeded, failed, pending
    failed_payment_count = Column(Integer, default=0)

    # Renewal tracking
    auto_renew = Column(Boolean, default=True)
    renewal_count = Column(Integer, default=0)

    # Extra data and notes
    extra_data = Column(JSON, nullable=True)  # Additional data from payment provider
    internal_notes = Column(String, nullable=True)  # Admin notes

    # Relationships
    user = relationship("User", back_populates="subscriptions")

    def __repr__(self):
        return f"<Subscription(id={self.id}, user_id={self.user_id}, plan={self.plan_id}, status={self.status})>"

    @property
    def is_active(self) -> bool:
        """Check if subscription is currently active"""
        return self.status in ["active", "trialing"]

    @property
    def is_trial(self) -> bool:
        """Check if subscription is in trial period"""
        return self.status == "trialing"

    @property
    def is_canceled(self) -> bool:
        """Check if subscription is canceled"""
        return self.status == "canceled" or self.canceled_at is not None

    @property
    def is_past_due(self) -> bool:
        """Check if subscription has failed payments"""
        return self.status == "past_due"

    @property
    def days_until_renewal(self) -> Optional[int]:
        """Calculate days until next billing"""
        if not self.next_billing_date:
            return None
        delta = self.next_billing_date - datetime.utcnow()
        return delta.days

    @property
    def is_stripe(self) -> bool:
        """Check if using Stripe"""
        return self.provider == "stripe"

    @property
    def is_paypal(self) -> bool:
        """Check if using PayPal"""
        return self.provider == "paypal"

    def to_dict(self, include_sensitive: bool = False) -> Dict:
        """
        Convert subscription to dictionary

        Args:
            include_sensitive: Include payment IDs and sensitive data

        Returns:
            Dict representation
        """
        data = {
            "id": self.id,
            "user_id": self.user_id,
            "plan_id": self.plan_id,
            "plan_name": self.plan_name,
            "provider": self.provider,
            "status": self.status,
            "amount": self.amount,
            "currency": self.currency,
            "billing_cycle": self.billing_cycle,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "activated_at": self.activated_at.isoformat() if self.activated_at else None,
            "next_billing_date": self.next_billing_date.isoformat() if self.next_billing_date else None,
            "current_period_end": self.current_period_end.isoformat() if self.current_period_end else None,
            "cancel_at_period_end": self.cancel_at_period_end,
            "canceled_at": self.canceled_at.isoformat() if self.canceled_at else None,
            "auto_renew": self.auto_renew,
            "is_active": self.is_active,
            "is_trial": self.is_trial,
            "days_until_renewal": self.days_until_renewal,
        }

        if include_sensitive:
            data.update({
                "stripe_customer_id": self.stripe_customer_id,
                "stripe_subscription_id": self.stripe_subscription_id,
                "paypal_customer_id": self.paypal_customer_id,
                "paypal_subscription_id": self.paypal_subscription_id,
                "last_payment_date": self.last_payment_date.isoformat() if self.last_payment_date else None,
                "last_payment_amount": self.last_payment_amount,
                "failed_payment_count": self.failed_payment_count,
                "extra_data": self.extra_data,
            })

        return data
