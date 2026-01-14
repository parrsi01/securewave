"""
Audit Log Models - Track all security and compliance events
"""

from datetime import datetime
from typing import Dict, Optional
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, Boolean, JSON, Index
from sqlalchemy.orm import relationship

from database.base import Base


class AuditLog(Base):
    """
    Audit Log - Track all security-relevant events
    Immutable records for compliance and security investigations
    """
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True)

    # Event identification
    event_type = Column(String, nullable=False, index=True)  # login, logout, data_access, config_change, etc.
    event_category = Column(String, nullable=False, index=True)  # authentication, authorization, data, system, security
    action = Column(String, nullable=False)  # created, updated, deleted, accessed, failed, etc.

    # Actor information
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)  # NULL for system events
    actor_type = Column(String, nullable=False)  # user, admin, system, api, automated
    actor_email = Column(String, nullable=True, index=True)  # Denormalized for faster queries

    # Resource affected
    resource_type = Column(String, nullable=True, index=True)  # user, subscription, vpn_server, config, etc.
    resource_id = Column(String, nullable=True, index=True)  # ID of affected resource
    resource_name = Column(String, nullable=True)  # Human-readable name

    # Event details
    description = Column(Text, nullable=False)  # Human-readable description
    details = Column(JSON, nullable=True)  # Additional event data

    # Request metadata
    ip_address = Column(String, nullable=True, index=True)
    user_agent = Column(String, nullable=True)
    request_id = Column(String, nullable=True, index=True)  # Trace requests across services

    # Security flags
    severity = Column(String, nullable=False, index=True)  # info, warning, error, critical
    is_suspicious = Column(Boolean, nullable=False, default=False, index=True)
    is_compliance_relevant = Column(Boolean, nullable=False, default=True)

    # Result
    success = Column(Boolean, nullable=False)
    error_message = Column(Text, nullable=True)

    # Backward compatibility
    status = Column(String, nullable=True)  # Deprecated: use success field
    resource = Column(String, nullable=True)  # Deprecated: use resource_type/resource_id
    timestamp = Column(DateTime, nullable=True)  # Deprecated: use created_at

    # Timestamp (immutable)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)

    # Relationships
    user = relationship("User", backref="audit_logs_new", foreign_keys=[user_id])

    # Table arguments for composite indexes
    __table_args__ = (
        Index('ix_audit_user_event', 'user_id', 'event_type'),
        Index('ix_audit_category_severity', 'event_category', 'severity'),
        Index('ix_audit_resource', 'resource_type', 'resource_id'),
        Index('ix_audit_created_category', 'created_at', 'event_category'),
        Index('ix_audit_suspicious', 'is_suspicious', 'created_at'),
    )

    def __repr__(self):
        return f"<AuditLog({self.event_type} by {self.actor_email} at {self.created_at})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "event_type": self.event_type,
            "event_category": self.event_category,
            "action": self.action,
            "user_id": self.user_id,
            "actor_type": self.actor_type,
            "actor_email": self.actor_email,
            "resource_type": self.resource_type,
            "resource_id": self.resource_id,
            "resource_name": self.resource_name,
            "description": self.description,
            "details": self.details,
            "ip_address": self.ip_address,
            "severity": self.severity,
            "is_suspicious": self.is_suspicious,
            "success": self.success,
            "error_message": self.error_message,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


class PerformanceMetric(Base):
    """
    Performance Metrics - Track application performance
    """
    __tablename__ = "performance_metrics"

    id = Column(Integer, primary_key=True, index=True)

    # Metric identification
    metric_type = Column(String, nullable=False, index=True)  # api_response_time, database_query, vpn_connection, etc.
    endpoint = Column(String, nullable=True, index=True)  # API endpoint or operation name

    # Timing metrics (milliseconds)
    response_time_ms = Column(Integer, nullable=True)
    database_time_ms = Column(Integer, nullable=True)
    external_api_time_ms = Column(Integer, nullable=True)
    total_time_ms = Column(Integer, nullable=True)

    # Resource metrics
    memory_mb = Column(Integer, nullable=True)
    cpu_percent = Column(Integer, nullable=True)

    # Request details
    request_id = Column(String, nullable=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    status_code = Column(Integer, nullable=True)

    # Extra data
    extra_data = Column(JSON, nullable=True)

    # Timestamp
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)

    # Relationships
    user = relationship("User", backref="performance_metrics")

    # Table arguments
    __table_args__ = (
        Index('ix_perf_endpoint_created', 'endpoint', 'created_at'),
        Index('ix_perf_type_created', 'metric_type', 'created_at'),
    )

    def __repr__(self):
        return f"<PerformanceMetric({self.metric_type} - {self.total_time_ms}ms)>"


class UptimeCheck(Base):
    """
    Uptime Monitoring - Track service availability
    """
    __tablename__ = "uptime_checks"

    id = Column(Integer, primary_key=True, index=True)

    # Check configuration
    check_name = Column(String, nullable=False, index=True)  # api, vpn_server_1, database, etc.
    check_type = Column(String, nullable=False)  # http, tcp, icmp, database
    target = Column(String, nullable=False)  # URL, IP, hostname

    # Check result
    is_up = Column(Boolean, nullable=False, index=True)
    response_time_ms = Column(Integer, nullable=True)
    status_code = Column(Integer, nullable=True)

    # Error details
    error_message = Column(Text, nullable=True)

    # Extra data
    extra_data = Column(JSON, nullable=True)

    # Timestamp
    checked_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)

    # Table arguments
    __table_args__ = (
        Index('ix_uptime_name_checked', 'check_name', 'checked_at'),
        Index('ix_uptime_status_checked', 'is_up', 'checked_at'),
    )

    def __repr__(self):
        status = "UP" if self.is_up else "DOWN"
        return f"<UptimeCheck({self.check_name} - {status})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "check_name": self.check_name,
            "check_type": self.check_type,
            "target": self.target,
            "is_up": self.is_up,
            "response_time_ms": self.response_time_ms,
            "status_code": self.status_code,
            "error_message": self.error_message,
            "checked_at": self.checked_at.isoformat() if self.checked_at else None,
        }


class ErrorLog(Base):
    """
    Error Logs - Track application errors and exceptions
    """
    __tablename__ = "error_logs"

    id = Column(Integer, primary_key=True, index=True)

    # Error identification
    error_type = Column(String, nullable=False, index=True)  # Exception class name
    error_message = Column(Text, nullable=False)
    error_code = Column(String, nullable=True, index=True)

    # Error details
    stack_trace = Column(Text, nullable=True)
    file_path = Column(String, nullable=True)
    line_number = Column(Integer, nullable=True)
    function_name = Column(String, nullable=True)

    # Context
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    request_id = Column(String, nullable=True, index=True)
    endpoint = Column(String, nullable=True, index=True)
    http_method = Column(String, nullable=True)

    # Request details
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)

    # Severity
    severity = Column(String, nullable=False, index=True)  # debug, info, warning, error, critical

    # Error count (for deduplication)
    occurrence_count = Column(Integer, nullable=False, default=1)
    first_seen_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    last_seen_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    # Resolution
    is_resolved = Column(Boolean, nullable=False, default=False, index=True)
    resolved_at = Column(DateTime, nullable=True)
    resolved_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    resolution_notes = Column(Text, nullable=True)

    # Extra data
    extra_data = Column(JSON, nullable=True)

    # Timestamp
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)

    # Relationships
    user = relationship("User", backref="error_logs", foreign_keys=[user_id])
    resolved_by = relationship("User", foreign_keys=[resolved_by_id])

    # Table arguments
    __table_args__ = (
        Index('ix_error_type_created', 'error_type', 'created_at'),
        Index('ix_error_severity_resolved', 'severity', 'is_resolved'),
        Index('ix_error_endpoint_created', 'endpoint', 'created_at'),
    )

    def __repr__(self):
        return f"<ErrorLog({self.error_type} - {self.severity})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "error_type": self.error_type,
            "error_message": self.error_message,
            "error_code": self.error_code,
            "file_path": self.file_path,
            "line_number": self.line_number,
            "severity": self.severity,
            "occurrence_count": self.occurrence_count,
            "is_resolved": self.is_resolved,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "last_seen_at": self.last_seen_at.isoformat() if self.last_seen_at else None,
        }
