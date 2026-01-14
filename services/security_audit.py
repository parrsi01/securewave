"""
Security Audit Logging Service
Comprehensive security event logging for compliance and investigation
"""

import os
import logging
from typing import Dict, Optional, Any, List
from datetime import datetime, timedelta
from enum import Enum

logger = logging.getLogger(__name__)


class EventType(str, Enum):
    """Security event types"""
    # Authentication
    LOGIN = "login"
    LOGOUT = "logout"
    LOGIN_FAILED = "login_failed"
    PASSWORD_RESET = "password_reset"
    PASSWORD_CHANGED = "password_changed"
    EMAIL_VERIFIED = "email_verified"
    TWO_FACTOR_ENABLED = "2fa_enabled"
    TWO_FACTOR_DISABLED = "2fa_disabled"
    TWO_FACTOR_FAILED = "2fa_failed"

    # Authorization
    PERMISSION_DENIED = "permission_denied"
    ROLE_CHANGED = "role_changed"
    ACCESS_GRANTED = "access_granted"

    # Data Access
    USER_DATA_ACCESSED = "user_data_accessed"
    USER_DATA_EXPORTED = "user_data_exported"
    USER_DATA_DELETED = "user_data_deleted"
    USER_DATA_MODIFIED = "user_data_modified"

    # VPN Operations
    VPN_CONNECTED = "vpn_connected"
    VPN_DISCONNECTED = "vpn_disconnected"
    VPN_CONNECTION_FAILED = "vpn_connection_failed"
    VPN_CONFIG_GENERATED = "vpn_config_generated"
    VPN_KEY_ROTATED = "vpn_key_rotated"

    # Account Management
    ACCOUNT_CREATED = "account_created"
    ACCOUNT_UPDATED = "account_updated"
    ACCOUNT_DELETED = "account_deleted"
    ACCOUNT_SUSPENDED = "account_suspended"
    ACCOUNT_REACTIVATED = "account_reactivated"

    # Payment & Billing
    PAYMENT_PROCESSED = "payment_processed"
    PAYMENT_FAILED = "payment_failed"
    SUBSCRIPTION_CREATED = "subscription_created"
    SUBSCRIPTION_CANCELLED = "subscription_cancelled"
    REFUND_ISSUED = "refund_issued"

    # Security Events
    SUSPICIOUS_ACTIVITY = "suspicious_activity"
    RATE_LIMIT_EXCEEDED = "rate_limit_exceeded"
    ABUSE_DETECTED = "abuse_detected"
    SECURITY_BREACH_ATTEMPT = "security_breach_attempt"

    # Configuration
    CONFIG_CHANGED = "config_changed"
    SERVER_ADDED = "server_added"
    SERVER_REMOVED = "server_removed"

    # Admin Actions
    ADMIN_ACCESS = "admin_access"
    USER_IMPERSONATION = "user_impersonation"
    BULK_OPERATION = "bulk_operation"


class EventCategory(str, Enum):
    """Event categories"""
    AUTHENTICATION = "authentication"
    AUTHORIZATION = "authorization"
    DATA = "data"
    SYSTEM = "system"
    SECURITY = "security"
    PAYMENT = "payment"
    ADMIN = "admin"


class Severity(str, Enum):
    """Event severity levels"""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


class SecurityAuditService:
    """
    Security Audit Logging Service
    Logs all security-relevant events for compliance and investigation
    """

    def __init__(self):
        """Initialize security audit service"""
        self.enabled = True

    # ===========================
    # CORE AUDIT LOGGING
    # ===========================

    def log_event(
        self,
        event_type: EventType,
        event_category: EventCategory,
        action: str,
        user_id: Optional[int] = None,
        actor_email: Optional[str] = None,
        resource_type: Optional[str] = None,
        resource_id: Optional[str] = None,
        resource_name: Optional[str] = None,
        description: str = "",
        details: Optional[Dict[str, Any]] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
        request_id: Optional[str] = None,
        severity: Severity = Severity.INFO,
        is_suspicious: bool = False,
        success: bool = True,
        error_message: Optional[str] = None
    ) -> Optional[int]:
        """
        Log a security event

        Args:
            event_type: Type of event
            event_category: Event category
            action: Action performed
            user_id: User ID (if applicable)
            actor_email: Actor email for faster queries
            resource_type: Type of resource affected
            resource_id: ID of resource
            resource_name: Name of resource
            description: Human-readable description
            details: Additional event details
            ip_address: IP address
            user_agent: User agent
            request_id: Request ID for tracing
            severity: Event severity
            is_suspicious: Flag for suspicious activity
            success: Whether operation succeeded
            error_message: Error message if failed

        Returns:
            Audit log ID or None
        """
        if not self.enabled:
            return None

        try:
            from database.session import get_db
            from models.audit_log import AuditLog

            db = next(get_db())

            # Determine actor type
            actor_type = "system"
            if user_id:
                actor_type = "user"
                # Check if admin
                try:
                    from models.user import User
                    user = db.query(User).filter(User.id == user_id).first()
                    if user and user.is_admin:
                        actor_type = "admin"
                except:
                    pass

            audit_log = AuditLog(
                event_type=event_type.value,
                event_category=event_category.value,
                action=action,
                user_id=user_id,
                actor_type=actor_type,
                actor_email=actor_email,
                resource_type=resource_type,
                resource_id=str(resource_id) if resource_id else None,
                resource_name=resource_name,
                description=description,
                details=details or {},
                ip_address=ip_address,
                user_agent=user_agent,
                request_id=request_id,
                severity=severity.value,
                is_suspicious=is_suspicious,
                is_compliance_relevant=True,
                success=success,
                error_message=error_message
            )

            db.add(audit_log)
            db.commit()

            # Log to application logger
            log_level = {
                Severity.INFO: logging.INFO,
                Severity.WARNING: logging.WARNING,
                Severity.ERROR: logging.ERROR,
                Severity.CRITICAL: logging.CRITICAL
            }.get(severity, logging.INFO)

            logger.log(
                log_level,
                f"Security Event: {event_type.value} - {description}",
                extra={
                    "user_id": user_id,
                    "ip_address": ip_address,
                    "event_type": event_type.value,
                    "success": success
                }
            )

            return audit_log.id

        except Exception as e:
            logger.error(f"Failed to log security event: {e}")
            return None

    # ===========================
    # AUTHENTICATION EVENTS
    # ===========================

    def log_login(
        self,
        user_id: int,
        email: str,
        ip_address: str,
        user_agent: str,
        success: bool,
        method: str = "password",
        error_message: Optional[str] = None
    ) -> None:
        """Log login attempt"""
        event_type = EventType.LOGIN if success else EventType.LOGIN_FAILED
        severity = Severity.INFO if success else Severity.WARNING

        self.log_event(
            event_type=event_type,
            event_category=EventCategory.AUTHENTICATION,
            action="login",
            user_id=user_id if success else None,
            actor_email=email,
            description=f"User {'successfully logged in' if success else 'failed to log in'} using {method}",
            details={"method": method},
            ip_address=ip_address,
            user_agent=user_agent,
            severity=severity,
            is_suspicious=not success,
            success=success,
            error_message=error_message
        )

    def log_logout(self, user_id: int, email: str, ip_address: str) -> None:
        """Log logout"""
        self.log_event(
            event_type=EventType.LOGOUT,
            event_category=EventCategory.AUTHENTICATION,
            action="logout",
            user_id=user_id,
            actor_email=email,
            description="User logged out",
            ip_address=ip_address,
            severity=Severity.INFO,
            success=True
        )

    def log_password_reset(
        self,
        user_id: int,
        email: str,
        ip_address: str,
        initiated: bool = True
    ) -> None:
        """Log password reset"""
        action = "initiated" if initiated else "completed"

        self.log_event(
            event_type=EventType.PASSWORD_RESET,
            event_category=EventCategory.AUTHENTICATION,
            action=action,
            user_id=user_id,
            actor_email=email,
            description=f"Password reset {action}",
            ip_address=ip_address,
            severity=Severity.WARNING,
            success=True
        )

    def log_2fa_event(
        self,
        user_id: int,
        email: str,
        action: str,  # enabled, disabled, failed
        ip_address: str,
        success: bool = True
    ) -> None:
        """Log 2FA event"""
        event_type_map = {
            "enabled": EventType.TWO_FACTOR_ENABLED,
            "disabled": EventType.TWO_FACTOR_DISABLED,
            "failed": EventType.TWO_FACTOR_FAILED
        }

        severity = Severity.WARNING if action == "failed" else Severity.INFO

        self.log_event(
            event_type=event_type_map.get(action, EventType.TWO_FACTOR_ENABLED),
            event_category=EventCategory.AUTHENTICATION,
            action=action,
            user_id=user_id,
            actor_email=email,
            description=f"Two-factor authentication {action}",
            ip_address=ip_address,
            severity=severity,
            is_suspicious=(action == "failed"),
            success=success
        )

    # ===========================
    # DATA ACCESS EVENTS
    # ===========================

    def log_data_access(
        self,
        user_id: int,
        email: str,
        resource_type: str,
        resource_id: str,
        action: str,  # accessed, exported, deleted, modified
        ip_address: Optional[str] = None,
        details: Optional[Dict] = None
    ) -> None:
        """Log data access event"""
        event_type_map = {
            "accessed": EventType.USER_DATA_ACCESSED,
            "exported": EventType.USER_DATA_EXPORTED,
            "deleted": EventType.USER_DATA_DELETED,
            "modified": EventType.USER_DATA_MODIFIED
        }

        severity = Severity.WARNING if action in ["deleted", "exported"] else Severity.INFO

        self.log_event(
            event_type=event_type_map.get(action, EventType.USER_DATA_ACCESSED),
            event_category=EventCategory.DATA,
            action=action,
            user_id=user_id,
            actor_email=email,
            resource_type=resource_type,
            resource_id=resource_id,
            description=f"{resource_type} {action}",
            details=details or {},
            ip_address=ip_address,
            severity=severity,
            is_compliance_relevant=True,
            success=True
        )

    # ===========================
    # VPN EVENTS
    # ===========================

    def log_vpn_connection(
        self,
        user_id: int,
        email: str,
        server_id: int,
        server_name: str,
        ip_address: str,
        success: bool,
        error_message: Optional[str] = None
    ) -> None:
        """Log VPN connection attempt"""
        event_type = EventType.VPN_CONNECTED if success else EventType.VPN_CONNECTION_FAILED
        severity = Severity.INFO if success else Severity.WARNING

        self.log_event(
            event_type=event_type,
            event_category=EventCategory.SYSTEM,
            action="connect" if success else "failed",
            user_id=user_id,
            actor_email=email,
            resource_type="vpn_server",
            resource_id=str(server_id),
            resource_name=server_name,
            description=f"VPN connection {'established' if success else 'failed'} to {server_name}",
            details={"server_id": server_id, "server_name": server_name},
            ip_address=ip_address,
            severity=severity,
            success=success,
            error_message=error_message
        )

    def log_vpn_config_generation(
        self,
        user_id: int,
        email: str,
        server_id: int,
        peer_id: int,
        ip_address: str
    ) -> None:
        """Log VPN configuration generation"""
        self.log_event(
            event_type=EventType.VPN_CONFIG_GENERATED,
            event_category=EventCategory.SYSTEM,
            action="generated",
            user_id=user_id,
            actor_email=email,
            resource_type="vpn_peer",
            resource_id=str(peer_id),
            description="VPN configuration generated",
            details={"server_id": server_id, "peer_id": peer_id},
            ip_address=ip_address,
            severity=Severity.INFO,
            success=True
        )

    # ===========================
    # SECURITY EVENTS
    # ===========================

    def log_suspicious_activity(
        self,
        user_id: Optional[int],
        email: Optional[str],
        activity_type: str,
        description: str,
        ip_address: str,
        details: Optional[Dict] = None,
        severity: Severity = Severity.WARNING
    ) -> None:
        """Log suspicious activity"""
        self.log_event(
            event_type=EventType.SUSPICIOUS_ACTIVITY,
            event_category=EventCategory.SECURITY,
            action="detected",
            user_id=user_id,
            actor_email=email,
            description=description,
            details={**(details or {}), "activity_type": activity_type},
            ip_address=ip_address,
            severity=severity,
            is_suspicious=True,
            success=True
        )

    def log_rate_limit_exceeded(
        self,
        user_id: Optional[int],
        email: Optional[str],
        endpoint: str,
        ip_address: str,
        limit: int,
        window: int
    ) -> None:
        """Log rate limit exceeded"""
        self.log_event(
            event_type=EventType.RATE_LIMIT_EXCEEDED,
            event_category=EventCategory.SECURITY,
            action="exceeded",
            user_id=user_id,
            actor_email=email,
            description=f"Rate limit exceeded for {endpoint}",
            details={
                "endpoint": endpoint,
                "limit": limit,
                "window_seconds": window
            },
            ip_address=ip_address,
            severity=Severity.WARNING,
            is_suspicious=True,
            success=True
        )

    def log_abuse_detected(
        self,
        user_id: int,
        email: str,
        abuse_type: str,
        severity: str,
        description: str,
        details: Optional[Dict] = None
    ) -> None:
        """Log abuse detection"""
        severity_map = {
            "low": Severity.INFO,
            "medium": Severity.WARNING,
            "high": Severity.ERROR,
            "critical": Severity.CRITICAL
        }

        self.log_event(
            event_type=EventType.ABUSE_DETECTED,
            event_category=EventCategory.SECURITY,
            action="detected",
            user_id=user_id,
            actor_email=email,
            description=description,
            details={**(details or {}), "abuse_type": abuse_type},
            severity=severity_map.get(severity, Severity.WARNING),
            is_suspicious=True,
            success=True
        )

    # ===========================
    # PAYMENT EVENTS
    # ===========================

    def log_payment_event(
        self,
        user_id: int,
        email: str,
        amount: float,
        currency: str,
        provider: str,
        success: bool,
        transaction_id: Optional[str] = None,
        error_message: Optional[str] = None
    ) -> None:
        """Log payment event"""
        event_type = EventType.PAYMENT_PROCESSED if success else EventType.PAYMENT_FAILED
        severity = Severity.INFO if success else Severity.WARNING

        self.log_event(
            event_type=event_type,
            event_category=EventCategory.PAYMENT,
            action="processed" if success else "failed",
            user_id=user_id,
            actor_email=email,
            description=f"Payment {'processed' if success else 'failed'}: {currency} {amount}",
            details={
                "amount": amount,
                "currency": currency,
                "provider": provider,
                "transaction_id": transaction_id
            },
            severity=severity,
            success=success,
            error_message=error_message
        )

    # ===========================
    # ADMIN EVENTS
    # ===========================

    def log_admin_action(
        self,
        admin_id: int,
        admin_email: str,
        action: str,
        resource_type: str,
        resource_id: Optional[str] = None,
        description: str = "",
        details: Optional[Dict] = None,
        ip_address: Optional[str] = None
    ) -> None:
        """Log admin action"""
        self.log_event(
            event_type=EventType.ADMIN_ACCESS,
            event_category=EventCategory.ADMIN,
            action=action,
            user_id=admin_id,
            actor_email=admin_email,
            resource_type=resource_type,
            resource_id=resource_id,
            description=description,
            details=details or {},
            ip_address=ip_address,
            severity=Severity.WARNING,  # Admin actions always logged as warnings
            is_compliance_relevant=True,
            success=True
        )

    # ===========================
    # AUDIT LOG QUERIES
    # ===========================

    def get_user_audit_log(
        self,
        user_id: int,
        days: int = 30,
        event_types: Optional[List[str]] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Get audit log for a user

        Args:
            user_id: User ID
            days: Number of days to look back
            event_types: Filter by event types
            limit: Maximum results

        Returns:
            List of audit log entries
        """
        try:
            from database.session import get_db
            from models.audit_log import AuditLog

            db = next(get_db())

            start_date = datetime.utcnow() - timedelta(days=days)

            query = db.query(AuditLog).filter(
                AuditLog.user_id == user_id,
                AuditLog.created_at >= start_date
            )

            if event_types:
                query = query.filter(AuditLog.event_type.in_(event_types))

            logs = query.order_by(AuditLog.created_at.desc()).limit(limit).all()

            return [log.to_dict() for log in logs]

        except Exception as e:
            logger.error(f"Failed to get user audit log: {e}")
            return []

    def get_suspicious_events(self, hours: int = 24) -> List[Dict]:
        """Get suspicious events"""
        try:
            from database.session import get_db
            from models.audit_log import AuditLog

            db = next(get_db())

            start_time = datetime.utcnow() - timedelta(hours=hours)

            logs = db.query(AuditLog).filter(
                AuditLog.is_suspicious == True,
                AuditLog.created_at >= start_time
            ).order_by(AuditLog.created_at.desc()).limit(100).all()

            return [log.to_dict() for log in logs]

        except Exception as e:
            logger.error(f"Failed to get suspicious events: {e}")
            return []


# Singleton instance
_security_audit: Optional[SecurityAuditService] = None


def get_security_audit() -> SecurityAuditService:
    """Get security audit service instance"""
    global _security_audit
    if _security_audit is None:
        _security_audit = SecurityAuditService()
    return _security_audit
