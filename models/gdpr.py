"""
GDPR Compliance Models
Models for GDPR compliance tracking and data subject rights
"""

from datetime import datetime
from typing import Dict
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, Boolean, JSON, Enum as SQLEnum
from sqlalchemy.orm import relationship
import enum

from database.base import Base
from utils.time_utils import utcnow


class GDPRRequestType(str, enum.Enum):
    """GDPR request types (Data Subject Rights)"""
    ACCESS = "access"  # Right to access (Article 15)
    RECTIFICATION = "rectification"  # Right to rectification (Article 16)
    ERASURE = "erasure"  # Right to erasure/Right to be forgotten (Article 17)
    RESTRICTION = "restriction"  # Right to restriction of processing (Article 18)
    PORTABILITY = "portability"  # Right to data portability (Article 20)
    OBJECTION = "objection"  # Right to object (Article 21)


class GDPRRequestStatus(str, enum.Enum):
    """GDPR request status"""
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    REJECTED = "rejected"
    CANCELLED = "cancelled"


class ConsentType(str, enum.Enum):
    """Types of user consent"""
    TERMS_OF_SERVICE = "terms_of_service"
    PRIVACY_POLICY = "privacy_policy"
    MARKETING_EMAILS = "marketing_emails"
    ANALYTICS = "analytics"
    THIRD_PARTY_SHARING = "third_party_sharing"


class GDPRRequest(Base):
    """
    GDPR Data Subject Access Requests (DSAR)
    Track user requests for their data rights
    """
    __tablename__ = "gdpr_requests"

    id = Column(Integer, primary_key=True, index=True)

    # Request details
    request_number = Column(String, unique=True, nullable=False, index=True)  # GDPR-202401-00001
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    request_type = Column(SQLEnum(GDPRRequestType), nullable=False, index=True)
    status = Column(SQLEnum(GDPRRequestStatus), nullable=False, default=GDPRRequestStatus.PENDING, index=True)

    # Request content
    description = Column(Text, nullable=True)
    specific_data_requested = Column(JSON, nullable=True)  # Specific fields/categories requested

    # Processing
    assigned_to_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    processed_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    rejection_reason = Column(Text, nullable=True)

    # Verification
    verification_method = Column(String, nullable=True)  # email, id_verification, etc.
    verified_at = Column(DateTime, nullable=True)

    # Output
    data_export_path = Column(String, nullable=True)  # Path to exported data
    data_export_format = Column(String, nullable=True)  # JSON, CSV, PDF
    data_export_size_bytes = Column(Integer, nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=utcnow, nullable=False, index=True)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)
    completed_at = Column(DateTime, nullable=True)
    due_date = Column(DateTime, nullable=False)  # GDPR requires response within 30 days

    # SLA tracking
    sla_breached = Column(Boolean, nullable=False, default=False)

    # Relationships
    user = relationship("User", foreign_keys=[user_id], backref="gdpr_requests")
    assigned_to = relationship("User", foreign_keys=[assigned_to_id])
    processed_by = relationship("User", foreign_keys=[processed_by_id])

    def __repr__(self):
        return f"<GDPRRequest({self.request_number} - {self.request_type.value} - {self.status.value})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "request_number": self.request_number,
            "user_id": self.user_id,
            "request_type": self.request_type.value,
            "status": self.status.value,
            "description": self.description,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "completed_at": self.completed_at.isoformat() if self.completed_at else None,
            "due_date": self.due_date.isoformat() if self.due_date else None,
            "sla_breached": self.sla_breached,
        }


class UserConsent(Base):
    """
    User Consent Tracking
    Track user consents for GDPR compliance
    """
    __tablename__ = "user_consents"

    id = Column(Integer, primary_key=True, index=True)

    # Consent details
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    consent_type = Column(SQLEnum(ConsentType), nullable=False, index=True)
    consent_version = Column(String, nullable=False)  # Version of T&C/Privacy Policy

    # Consent status
    is_granted = Column(Boolean, nullable=False)
    granted_at = Column(DateTime, nullable=True)
    revoked_at = Column(DateTime, nullable=True)

    # Context
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)
    consent_method = Column(String, nullable=True)  # checkbox, signature, email_confirmation

    # Additional data
    consent_text = Column(Text, nullable=True)  # Copy of what user agreed to
    extra_data = Column(JSON, nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=utcnow, nullable=False, index=True)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)

    # Relationships
    user = relationship("User", backref="consents")

    def __repr__(self):
        status = "granted" if self.is_granted else "revoked"
        return f"<UserConsent({self.consent_type.value} - {status})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "user_id": self.user_id,
            "consent_type": self.consent_type.value,
            "consent_version": self.consent_version,
            "is_granted": self.is_granted,
            "granted_at": self.granted_at.isoformat() if self.granted_at else None,
            "revoked_at": self.revoked_at.isoformat() if self.revoked_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class DataProcessingActivity(Base):
    """
    Data Processing Activities (Article 30 Records)
    Document all data processing activities for GDPR compliance
    """
    __tablename__ = "data_processing_activities"

    id = Column(Integer, primary_key=True, index=True)

    # Activity details
    activity_name = Column(String, nullable=False)
    activity_description = Column(Text, nullable=False)
    purpose = Column(Text, nullable=False)  # Why we process this data

    # Legal basis
    legal_basis = Column(String, nullable=False)  # consent, contract, legal_obligation, legitimate_interest
    legal_basis_details = Column(Text, nullable=True)

    # Data categories
    data_categories = Column(JSON, nullable=False)  # ["name", "email", "payment_info"]
    special_categories = Column(JSON, nullable=True)  # Sensitive data (if any)

    # Data subjects
    data_subjects = Column(String, nullable=False)  # customers, employees, etc.
    data_subject_count_estimate = Column(Integer, nullable=True)

    # Recipients
    recipients = Column(JSON, nullable=True)  # Who receives the data
    third_country_transfers = Column(Boolean, nullable=False, default=False)
    third_countries = Column(JSON, nullable=True)  # Countries data is transferred to
    transfer_safeguards = Column(Text, nullable=True)  # e.g., Standard Contractual Clauses

    # Retention
    retention_period = Column(String, nullable=False)  # e.g., "2 years after account deletion"
    retention_criteria = Column(Text, nullable=True)

    # Security measures
    security_measures = Column(JSON, nullable=False)  # Technical and organizational measures

    # Responsible parties
    data_controller = Column(String, nullable=False)  # Organization name
    data_processor = Column(String, nullable=True)  # If using external processor
    dpo_contact = Column(String, nullable=True)  # Data Protection Officer contact

    # Status
    is_active = Column(Boolean, nullable=False, default=True)
    last_reviewed_at = Column(DateTime, nullable=True)
    next_review_date = Column(DateTime, nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=utcnow, nullable=False)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow, nullable=False)

    def __repr__(self):
        return f"<DataProcessingActivity({self.activity_name})>"


class WarrantCanary(Base):
    """
    Warrant Canary Status
    Track transparency canary for government requests
    """
    __tablename__ = "warrant_canaries"

    id = Column(Integer, primary_key=True, index=True)

    # Canary details
    period_start = Column(DateTime, nullable=False, index=True)
    period_end = Column(DateTime, nullable=False, index=True)
    is_valid = Column(Boolean, nullable=False, default=True)

    # Statement
    statement = Column(Text, nullable=False)
    signed_statement_hash = Column(String, nullable=True)  # Cryptographic hash for verification

    # Metrics
    total_requests_received = Column(Integer, nullable=False, default=0)
    national_security_letters = Column(Integer, nullable=False, default=0)
    gag_orders = Column(Integer, nullable=False, default=0)
    search_warrants = Column(Integer, nullable=False, default=0)

    # Published
    published_at = Column(DateTime, nullable=False)
    published_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)

    # Timestamps
    created_at = Column(DateTime, default=utcnow, nullable=False)

    # Relationships
    published_by = relationship("User", foreign_keys=[published_by_id])

    def __repr__(self):
        status = "VALID" if self.is_valid else "INVALID"
        return f"<WarrantCanary({self.period_start.date()} to {self.period_end.date()} - {status})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "period_start": self.period_start.isoformat(),
            "period_end": self.period_end.isoformat(),
            "is_valid": self.is_valid,
            "statement": self.statement,
            "total_requests_received": self.total_requests_received,
            "national_security_letters": self.national_security_letters,
            "gag_orders": self.gag_orders,
            "search_warrants": self.search_warrants,
            "published_at": self.published_at.isoformat() if self.published_at else None,
        }
