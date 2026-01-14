"""
Support Ticket Model - User support and helpdesk system
"""

from datetime import datetime
from typing import Optional, Dict, List
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, Enum as SQLEnum, JSON
from sqlalchemy.orm import relationship
import enum

from database.base import Base


class TicketPriority(str, enum.Enum):
    """Ticket priority levels"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    URGENT = "urgent"


class TicketStatus(str, enum.Enum):
    """Ticket status"""
    OPEN = "open"
    IN_PROGRESS = "in_progress"
    WAITING_USER = "waiting_user"
    WAITING_SUPPORT = "waiting_support"
    RESOLVED = "resolved"
    CLOSED = "closed"


class TicketCategory(str, enum.Enum):
    """Ticket categories"""
    TECHNICAL = "technical"
    BILLING = "billing"
    ACCOUNT = "account"
    VPN_CONNECTION = "vpn_connection"
    FEATURE_REQUEST = "feature_request"
    BUG_REPORT = "bug_report"
    OTHER = "other"


class SupportTicket(Base):
    """
    Support ticket model for user helpdesk
    """
    __tablename__ = "support_tickets"

    id = Column(Integer, primary_key=True, index=True)
    ticket_number = Column(String, unique=True, nullable=False, index=True)  # TKT-202401-00001

    # User and assignment
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    assigned_to_id = Column(Integer, ForeignKey("users.id"), nullable=True)  # Admin/support user

    # Ticket details
    subject = Column(String(200), nullable=False)
    description = Column(Text, nullable=False)
    category = Column(SQLEnum(TicketCategory), nullable=False, default=TicketCategory.OTHER, index=True)
    priority = Column(SQLEnum(TicketPriority), nullable=False, default=TicketPriority.MEDIUM, index=True)
    status = Column(SQLEnum(TicketStatus), nullable=False, default=TicketStatus.OPEN, index=True)

    # Extra data
    extra_data = Column(JSON, nullable=True)  # Additional data (server_id, connection_id, error logs, etc.)
    tags = Column(JSON, nullable=True)  # Tags for categorization

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    first_response_at = Column(DateTime, nullable=True)
    resolved_at = Column(DateTime, nullable=True)
    closed_at = Column(DateTime, nullable=True)

    # SLA tracking
    sla_due_at = Column(DateTime, nullable=True)  # When ticket should be resolved by
    sla_breached = Column(Integer, default=0)  # Boolean as int

    # Satisfaction
    user_rating = Column(Integer, nullable=True)  # 1-5 stars
    user_feedback = Column(Text, nullable=True)

    # Relationships
    user = relationship("User", foreign_keys=[user_id], backref="support_tickets")
    assigned_to = relationship("User", foreign_keys=[assigned_to_id], backref="assigned_tickets")
    messages = relationship("TicketMessage", back_populates="ticket", cascade="all, delete-orphan", order_by="TicketMessage.created_at")

    def __repr__(self):
        return f"<SupportTicket(ticket_number='{self.ticket_number}', status='{self.status}', priority='{self.priority}')>"

    @property
    def is_open(self) -> bool:
        """Check if ticket is open"""
        return self.status in [TicketStatus.OPEN, TicketStatus.IN_PROGRESS, TicketStatus.WAITING_USER, TicketStatus.WAITING_SUPPORT]

    @property
    def response_time_seconds(self) -> Optional[int]:
        """Calculate first response time in seconds"""
        if not self.first_response_at:
            return None
        return int((self.first_response_at - self.created_at).total_seconds())

    @property
    def resolution_time_seconds(self) -> Optional[int]:
        """Calculate resolution time in seconds"""
        if not self.resolved_at:
            return None
        return int((self.resolved_at - self.created_at).total_seconds())

    @property
    def time_since_last_update(self) -> int:
        """Seconds since last update"""
        return int((datetime.utcnow() - self.updated_at).total_seconds())

    def to_dict(self, include_messages: bool = False) -> Dict:
        """Convert ticket to dictionary"""
        data = {
            "id": self.id,
            "ticket_number": self.ticket_number,
            "user_id": self.user_id,
            "assigned_to_id": self.assigned_to_id,
            "subject": self.subject,
            "description": self.description,
            "category": self.category.value if self.category else None,
            "priority": self.priority.value if self.priority else None,
            "status": self.status.value if self.status else None,
            "extra_data": self.extra_data,
            "tags": self.tags,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "first_response_at": self.first_response_at.isoformat() if self.first_response_at else None,
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
            "closed_at": self.closed_at.isoformat() if self.closed_at else None,
            "sla_due_at": self.sla_due_at.isoformat() if self.sla_due_at else None,
            "sla_breached": bool(self.sla_breached),
            "user_rating": self.user_rating,
            "is_open": self.is_open,
            "response_time_seconds": self.response_time_seconds,
            "resolution_time_seconds": self.resolution_time_seconds,
        }

        if include_messages and self.messages:
            data["messages"] = [msg.to_dict() for msg in self.messages]

        return data


class TicketMessage(Base):
    """
    Ticket messages/replies
    """
    __tablename__ = "ticket_messages"

    id = Column(Integer, primary_key=True, index=True)
    ticket_id = Column(Integer, ForeignKey("support_tickets.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)  # Who sent the message

    message = Column(Text, nullable=False)
    is_internal = Column(Integer, default=0)  # Internal notes (not visible to user)
    is_automated = Column(Integer, default=0)  # Auto-generated message

    # Attachments (JSON array of file paths/URLs)
    attachments = Column(JSON, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    ticket = relationship("SupportTicket", back_populates="messages")
    user = relationship("User", backref="ticket_messages")

    def __repr__(self):
        return f"<TicketMessage(ticket_id={self.ticket_id}, user_id={self.user_id})>"

    def to_dict(self) -> Dict:
        """Convert message to dictionary"""
        return {
            "id": self.id,
            "ticket_id": self.ticket_id,
            "user_id": self.user_id,
            "message": self.message,
            "is_internal": bool(self.is_internal),
            "is_automated": bool(self.is_automated),
            "attachments": self.attachments,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
