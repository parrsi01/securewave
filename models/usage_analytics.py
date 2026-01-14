"""
Usage Analytics Models - Track and analyze user behavior and system usage
"""

from datetime import datetime
from typing import Dict
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Float, BigInteger, JSON, Index
from sqlalchemy.orm import relationship

from database.base import Base


class UserUsageStats(Base):
    """
    Aggregated usage statistics per user
    Updated periodically by analytics service
    """
    __tablename__ = "user_usage_stats"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, unique=True, index=True)

    # Connection statistics
    total_connections = Column(Integer, default=0)
    active_connections = Column(Integer, default=0)
    total_connection_time_seconds = Column(BigInteger, default=0)
    average_session_duration_seconds = Column(Integer, default=0)
    last_connection_at = Column(DateTime, nullable=True)

    # Data usage
    total_bytes_uploaded = Column(BigInteger, default=0)
    total_bytes_downloaded = Column(BigInteger, default=0)
    total_data_gb = Column(Float, default=0.0)
    current_month_data_gb = Column(Float, default=0.0)  # Reset monthly

    # Server usage
    favorite_server_id = Column(String, nullable=True)  # Most used server
    unique_servers_used = Column(Integer, default=0)
    total_server_switches = Column(Integer, default=0)

    # Quality metrics
    average_latency_ms = Column(Float, default=0.0)
    average_throughput_mbps = Column(Float, default=0.0)
    connection_failure_count = Column(Integer, default=0)
    connection_success_rate = Column(Float, default=100.0)  # 0-100%

    # Account activity
    total_login_count = Column(Integer, default=0)
    failed_login_count = Column(Integer, default=0)
    last_login_at = Column(DateTime, nullable=True)
    account_age_days = Column(Integer, default=0)

    # Subscription
    total_subscription_renewals = Column(Integer, default=0)
    subscription_lifetime_value = Column(Float, default=0.0)  # Total revenue
    current_subscription_tier = Column(String, nullable=True)

    # Support
    total_support_tickets = Column(Integer, default=0)
    open_support_tickets = Column(Integer, default=0)
    average_ticket_resolution_hours = Column(Float, default=0.0)

    # Timestamps
    first_seen_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_activity_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationships
    user = relationship("User", backref="usage_stats")

    def __repr__(self):
        return f"<UserUsageStats(user_id={self.user_id}, total_connections={self.total_connections}, total_data_gb={self.total_data_gb:.2f})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "user_id": self.user_id,
            "total_connections": self.total_connections,
            "active_connections": self.active_connections,
            "total_connection_time_hours": round(self.total_connection_time_seconds / 3600, 2),
            "average_session_duration_minutes": round(self.average_session_duration_seconds / 60, 2),
            "total_data_gb": round(self.total_data_gb, 2),
            "current_month_data_gb": round(self.current_month_data_gb, 2),
            "favorite_server_id": self.favorite_server_id,
            "unique_servers_used": self.unique_servers_used,
            "average_latency_ms": round(self.average_latency_ms, 1),
            "average_throughput_mbps": round(self.average_throughput_mbps, 2),
            "connection_success_rate": round(self.connection_success_rate, 2),
            "total_login_count": self.total_login_count,
            "account_age_days": self.account_age_days,
            "subscription_lifetime_value": round(self.subscription_lifetime_value, 2),
            "last_activity_at": self.last_activity_at.isoformat() if self.last_activity_at else None,
        }


class DailyUsageMetrics(Base):
    """
    Daily aggregated metrics for analytics and billing
    One row per user per day
    """
    __tablename__ = "daily_usage_metrics"
    __table_args__ = (
        Index('ix_daily_usage_user_date', 'user_id', 'date'),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    date = Column(DateTime, nullable=False, index=True)  # Date (midnight UTC)

    # Daily statistics
    connections_count = Column(Integer, default=0)
    total_connection_time_seconds = Column(Integer, default=0)
    data_uploaded_mb = Column(Float, default=0.0)
    data_downloaded_mb = Column(Float, default=0.0)
    total_data_mb = Column(Float, default=0.0)

    # Quality
    avg_latency_ms = Column(Float, default=0.0)
    avg_throughput_mbps = Column(Float, default=0.0)
    connection_failures = Column(Integer, default=0)

    # Server usage
    servers_used = Column(JSON, nullable=True)  # List of server IDs

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    user = relationship("User", backref="daily_metrics")

    def __repr__(self):
        return f"<DailyUsageMetrics(user_id={self.user_id}, date={self.date.date()}, data_mb={self.total_data_mb:.2f})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "user_id": self.user_id,
            "date": self.date.date().isoformat(),
            "connections_count": self.connections_count,
            "total_connection_time_hours": round(self.total_connection_time_seconds / 3600, 2),
            "total_data_mb": round(self.total_data_mb, 2),
            "avg_latency_ms": round(self.avg_latency_ms, 1),
            "avg_throughput_mbps": round(self.avg_throughput_mbps, 2),
            "servers_used": self.servers_used or [],
        }


class AbuseDetectionLog(Base):
    """
    Abuse detection and security incident logs
    Tracks suspicious activity and policy violations
    """
    __tablename__ = "abuse_detection_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)

    # Incident details
    incident_type = Column(String, nullable=False, index=True)  # excessive_bandwidth, rapid_reconnects, port_scanning, etc.
    severity = Column(String, nullable=False, index=True)  # low, medium, high, critical
    description = Column(String, nullable=False)

    # Evidence/extra data
    extra_data = Column(JSON, nullable=True)  # IP addresses, bandwidth stats, timestamps, etc.

    # Detection
    detection_method = Column(String, nullable=True)  # automated, manual, user_report
    detected_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)  # Admin who flagged it

    # Action taken
    action_taken = Column(String, nullable=True)  # warning_sent, account_suspended, account_banned, none
    action_notes = Column(String, nullable=True)
    action_by_id = Column(Integer, ForeignKey("users.id"), nullable=True)

    # Status
    status = Column(String, default="pending", index=True)  # pending, investigating, resolved, false_positive
    resolved_at = Column(DateTime, nullable=True)

    # Timestamps
    detected_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationships
    user = relationship("User", foreign_keys=[user_id], backref="abuse_logs")
    detected_by = relationship("User", foreign_keys=[detected_by_id])
    action_by = relationship("User", foreign_keys=[action_by_id])

    def __repr__(self):
        return f"<AbuseDetectionLog(user_id={self.user_id}, type='{self.incident_type}', severity='{self.severity}')>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "id": self.id,
            "user_id": self.user_id,
            "incident_type": self.incident_type,
            "severity": self.severity,
            "description": self.description,
            "extra_data": self.extra_data,
            "detection_method": self.detection_method,
            "action_taken": self.action_taken,
            "status": self.status,
            "detected_at": self.detected_at.isoformat() if self.detected_at else None,
            "resolved_at": self.resolved_at.isoformat() if self.resolved_at else None,
        }


class SystemMetrics(Base):
    """
    System-wide metrics and health indicators
    Aggregated from all servers and users
    """
    __tablename__ = "system_metrics"

    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # User metrics
    total_users = Column(Integer, default=0)
    active_users_24h = Column(Integer, default=0)
    active_users_7d = Column(Integer, default=0)
    active_users_30d = Column(Integer, default=0)
    new_users_today = Column(Integer, default=0)

    # Connection metrics
    total_connections = Column(Integer, default=0)
    active_connections = Column(Integer, default=0)
    average_session_duration_minutes = Column(Float, default=0.0)

    # Server metrics
    total_servers = Column(Integer, default=0)
    healthy_servers = Column(Integer, default=0)
    degraded_servers = Column(Integer, default=0)
    offline_servers = Column(Integer, default=0)
    average_server_load = Column(Float, default=0.0)

    # Bandwidth
    total_bandwidth_gb_24h = Column(Float, default=0.0)
    average_throughput_mbps = Column(Float, default=0.0)
    peak_bandwidth_mbps = Column(Float, default=0.0)

    # Quality
    average_latency_ms = Column(Float, default=0.0)
    average_packet_loss = Column(Float, default=0.0)
    connection_success_rate = Column(Float, default=100.0)

    # Subscription metrics
    total_subscriptions = Column(Integer, default=0)
    active_subscriptions = Column(Integer, default=0)
    mrr = Column(Float, default=0.0)  # Monthly Recurring Revenue
    churn_rate = Column(Float, default=0.0)  # Percentage

    # Support metrics
    open_tickets = Column(Integer, default=0)
    tickets_resolved_24h = Column(Integer, default=0)
    average_resolution_time_hours = Column(Float, default=0.0)

    # Security
    abuse_incidents_24h = Column(Integer, default=0)
    failed_logins_24h = Column(Integer, default=0)

    def __repr__(self):
        return f"<SystemMetrics(timestamp={self.timestamp}, active_connections={self.active_connections})>"

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            "timestamp": self.timestamp.isoformat(),
            "total_users": self.total_users,
            "active_users_24h": self.active_users_24h,
            "active_connections": self.active_connections,
            "total_servers": self.total_servers,
            "healthy_servers": self.healthy_servers,
            "total_bandwidth_gb_24h": round(self.total_bandwidth_gb_24h, 2),
            "average_latency_ms": round(self.average_latency_ms, 1),
            "connection_success_rate": round(self.connection_success_rate, 2),
            "mrr": round(self.mrr, 2),
            "open_tickets": self.open_tickets,
        }
