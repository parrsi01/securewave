from datetime import datetime
from typing import Dict, Optional

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Float, Boolean, JSON
from sqlalchemy.orm import relationship

from database.base import Base


class Invoice(Base):
    """
    Invoice model for tracking all payment transactions
    Supports Stripe and PayPal invoices
    """
    __tablename__ = "invoices"

    # Primary identification
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    subscription_id = Column(Integer, ForeignKey("subscriptions.id"), nullable=True, index=True)

    # Invoice identification
    invoice_number = Column(String, unique=True, nullable=False, index=True)  # INV-2026-001234

    # Payment provider
    provider = Column(String, nullable=False, index=True)  # stripe or paypal

    # Provider IDs
    stripe_invoice_id = Column(String, nullable=True, index=True, unique=True)
    stripe_charge_id = Column(String, nullable=True)
    stripe_payment_intent_id = Column(String, nullable=True)
    paypal_invoice_id = Column(String, nullable=True, index=True, unique=True)
    paypal_transaction_id = Column(String, nullable=True)

    # Invoice details
    description = Column(String, nullable=True)
    amount_due = Column(Float, nullable=False)
    amount_paid = Column(Float, default=0.0)
    amount_remaining = Column(Float, default=0.0)
    currency = Column(String, default="USD")

    # Tax and fees
    tax_amount = Column(Float, default=0.0)
    tax_rate = Column(Float, default=0.0)  # Percentage
    subtotal = Column(Float, nullable=False)  # Before tax

    # Status (draft, open, paid, void, uncollectible)
    status = Column(String, default="open", index=True)

    # Important dates
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    due_date = Column(DateTime, nullable=True)
    paid_at = Column(DateTime, nullable=True)
    voided_at = Column(DateTime, nullable=True)

    # Billing period
    period_start = Column(DateTime, nullable=True)
    period_end = Column(DateTime, nullable=True)

    # Payment method
    payment_method = Column(String, nullable=True)  # card, paypal, bank_transfer
    card_last4 = Column(String, nullable=True)
    card_brand = Column(String, nullable=True)  # visa, mastercard, amex

    # Retry tracking for failed payments
    attempt_count = Column(Integer, default=0)
    next_payment_attempt = Column(DateTime, nullable=True)

    # PDF and receipt
    pdf_url = Column(String, nullable=True)
    receipt_url = Column(String, nullable=True)
    hosted_invoice_url = Column(String, nullable=True)  # Stripe hosted invoice page

    # Extra data
    extra_data = Column(JSON, nullable=True)
    internal_notes = Column(String, nullable=True)

    # Relationships
    user = relationship("User", backref="invoices")
    subscription = relationship("Subscription", backref="invoices")

    def __repr__(self):
        return f"<Invoice(id={self.id}, number={self.invoice_number}, amount={self.amount_due}, status={self.status})>"

    @property
    def is_paid(self) -> bool:
        """Check if invoice is fully paid"""
        return self.status == "paid"

    @property
    def is_open(self) -> bool:
        """Check if invoice is awaiting payment"""
        return self.status == "open"

    @property
    def is_overdue(self) -> bool:
        """Check if invoice is past due date"""
        if not self.due_date or self.is_paid:
            return False
        return datetime.utcnow() > self.due_date

    @property
    def days_overdue(self) -> Optional[int]:
        """Calculate days overdue"""
        if not self.is_overdue:
            return None
        delta = datetime.utcnow() - self.due_date
        return delta.days

    def to_dict(self, include_urls: bool = True) -> Dict:
        """
        Convert invoice to dictionary

        Args:
            include_urls: Include PDF and receipt URLs

        Returns:
            Dict representation
        """
        data = {
            "id": self.id,
            "invoice_number": self.invoice_number,
            "user_id": self.user_id,
            "subscription_id": self.subscription_id,
            "provider": self.provider,
            "description": self.description,
            "amount_due": self.amount_due,
            "amount_paid": self.amount_paid,
            "amount_remaining": self.amount_remaining,
            "currency": self.currency,
            "subtotal": self.subtotal,
            "tax_amount": self.tax_amount,
            "tax_rate": self.tax_rate,
            "status": self.status,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "due_date": self.due_date.isoformat() if self.due_date else None,
            "paid_at": self.paid_at.isoformat() if self.paid_at else None,
            "period_start": self.period_start.isoformat() if self.period_start else None,
            "period_end": self.period_end.isoformat() if self.period_end else None,
            "payment_method": self.payment_method,
            "card_last4": self.card_last4,
            "card_brand": self.card_brand,
            "is_paid": self.is_paid,
            "is_overdue": self.is_overdue,
            "days_overdue": self.days_overdue,
        }

        if include_urls:
            data.update({
                "pdf_url": self.pdf_url,
                "receipt_url": self.receipt_url,
                "hosted_invoice_url": self.hosted_invoice_url,
            })

        return data
