"""
Email Log Model - Track sent emails for debugging and analytics
"""

from datetime import datetime
from typing import Dict, Optional
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, Boolean, JSON
from sqlalchemy.orm import relationship

from database.base import Base


class EmailLog(Base):
    """
    Email tracking and logging
    Tracks all emails sent through the system
    """
    __tablename__ = "email_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)  # NULL for system emails

    # Email details
    to_email = Column(String, nullable=False, index=True)
    from_email = Column(String, nullable=False)
    subject = Column(String, nullable=False)
    template_name = Column(String, nullable=True, index=True)  # verification, password_reset, welcome, etc.

    # Email type categorization
    email_type = Column(String, nullable=False, index=True)  # transactional, marketing, notification, system
    category = Column(String, nullable=True)  # billing, support, vpn, account, etc.

    # Provider info
    provider = Column(String, nullable=False)  # smtp, sendgrid, aws_ses
    provider_message_id = Column(String, nullable=True)  # External message ID from provider

    # Status tracking
    status = Column(String, nullable=False, index=True)  # queued, sent, delivered, failed, bounced, opened, clicked
    error_message = Column(Text, nullable=True)

    # Extra data
    extra_data = Column(JSON, nullable=True)  # Additional data (template vars, tracking info, etc.)

    # Engagement tracking
    sent_at = Column(DateTime, nullable=True)
    delivered_at = Column(DateTime, nullable=True)
    opened_at = Column(DateTime, nullable=True)
    clicked_at = Column(DateTime, nullable=True)
    bounced_at = Column(DateTime, nullable=True)
    failed_at = Column(DateTime, nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationships
    user = relationship("User", backref="email_logs")

    def __repr__(self):
        return f"<EmailLog(to='{self.to_email}', template='{self.template_name}', status='{self.status}')>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "user_id": self.user_id,
            "to_email": self.to_email,
            "subject": self.subject,
            "template_name": self.template_name,
            "email_type": self.email_type,
            "provider": self.provider,
            "status": self.status,
            "error_message": self.error_message,
            "sent_at": self.sent_at.isoformat() if self.sent_at else None,
            "delivered_at": self.delivered_at.isoformat() if self.delivered_at else None,
            "opened_at": self.opened_at.isoformat() if self.opened_at else None,
            "clicked_at": self.clicked_at.isoformat() if self.clicked_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class EmailTemplate(Base):
    """
    Email template storage
    Store email templates in database for easy updates
    """
    __tablename__ = "email_templates"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, nullable=False, index=True)  # verification_email, welcome_email, etc.
    subject = Column(String, nullable=False)
    html_template = Column(Text, nullable=False)
    text_template = Column(Text, nullable=True)

    # Template metadata
    description = Column(String, nullable=True)
    category = Column(String, nullable=True)  # account, billing, support, vpn, etc.
    variables = Column(JSON, nullable=True)  # List of template variables

    # Status
    is_active = Column(Boolean, default=True)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    def __repr__(self):
        return f"<EmailTemplate(name='{self.name}', subject='{self.subject}')>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "name": self.name,
            "subject": self.subject,
            "description": self.description,
            "category": self.category,
            "variables": self.variables,
            "is_active": self.is_active,
        }
