import logging
from datetime import datetime
from typing import Optional, Dict, Any

from sqlalchemy.orm import Session
from fastapi import Request

from models.audit_log import AuditLog
from models.user import User

logger = logging.getLogger(__name__)


class AuditService:
    """Service for logging security-sensitive actions"""

    @staticmethod
    def log_action(
        db: Session,
        action: str,
        status: str,
        user: Optional[User] = None,
        user_id: Optional[int] = None,
        request: Optional[Request] = None,
        resource: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
    ) -> AuditLog:
        """
        Log an audit event

        Args:
            db: Database session
            action: Action name (login, logout, vpn_connect, config_download, etc.)
            status: Status (success, failure, error)
            user: User object (if available)
            user_id: User ID (if user object not available)
            request: FastAPI request object (for IP and user agent)
            resource: Resource identifier (server_id, etc.)
            details: Additional context as JSON

        Returns:
            AuditLog: Created audit log entry
        """
        try:
            # Extract IP and user agent from request if available
            ip_address = None
            user_agent = None
            if request:
                ip_address = request.client.host if request.client else None
                user_agent = request.headers.get("user-agent")

            # Determine user_id
            if user:
                user_id = user.id

            audit_log = AuditLog(
                timestamp=datetime.utcnow(),
                user_id=user_id,
                action=action,
                ip_address=ip_address,
                user_agent=user_agent,
                resource=resource,
                status=status,
                details=details,
            )

            db.add(audit_log)
            db.commit()
            db.refresh(audit_log)

            logger.info(
                f"Audit log created: action={action}, status={status}, "
                f"user_id={user_id}, ip={ip_address}"
            )

            return audit_log

        except Exception as e:
            logger.error(f"Failed to create audit log: {e}")
            db.rollback()
            raise

    @staticmethod
    def log_login_success(db: Session, user: User, request: Request):
        """Log successful login"""
        return AuditService.log_action(
            db=db,
            action="login",
            status="success",
            user=user,
            request=request,
        )

    @staticmethod
    def log_login_failure(db: Session, email: str, request: Request):
        """Log failed login attempt"""
        return AuditService.log_action(
            db=db,
            action="login",
            status="failure",
            request=request,
            details={"email": email},
        )

    @staticmethod
    def log_logout(db: Session, user: User, request: Request):
        """Log user logout"""
        return AuditService.log_action(
            db=db,
            action="logout",
            status="success",
            user=user,
            request=request,
        )

    @staticmethod
    def log_vpn_connect(
        db: Session,
        user: User,
        server_id: str,
        request: Request,
        status: str = "success",
    ):
        """Log VPN connection attempt"""
        return AuditService.log_action(
            db=db,
            action="vpn_connect",
            status=status,
            user=user,
            request=request,
            resource=server_id,
        )

    @staticmethod
    def log_config_download(db: Session, user: User, server_id: str, request: Request):
        """Log VPN config download"""
        return AuditService.log_action(
            db=db,
            action="config_download",
            status="success",
            user=user,
            request=request,
            resource=server_id,
        )

    @staticmethod
    def log_subscription_change(
        db: Session,
        user: User,
        old_status: str,
        new_status: str,
        provider: str,
        request: Optional[Request] = None,
    ):
        """Log subscription status change"""
        return AuditService.log_action(
            db=db,
            action="subscription_change",
            status="success",
            user=user,
            request=request,
            resource=provider,
            details={
                "old_status": old_status,
                "new_status": new_status,
                "provider": provider,
            },
        )

    @staticmethod
    def get_user_audit_logs(
        db: Session,
        user_id: int,
        limit: int = 100,
        action: Optional[str] = None,
    ) -> list[AuditLog]:
        """
        Get audit logs for a specific user

        Args:
            db: Database session
            user_id: User ID
            limit: Maximum number of logs to return
            action: Optional filter by action type

        Returns:
            List of audit logs
        """
        query = db.query(AuditLog).filter(AuditLog.user_id == user_id)

        if action:
            query = query.filter(AuditLog.action == action)

        return query.order_by(AuditLog.timestamp.desc()).limit(limit).all()

    @staticmethod
    def get_failed_logins(db: Session, hours: int = 24, limit: int = 100) -> list[AuditLog]:
        """Get failed login attempts from last N hours"""
        since = datetime.utcnow() - timedelta(hours=hours)
        return (
            db.query(AuditLog)
            .filter(
                AuditLog.action == "login",
                AuditLog.status == "failure",
                AuditLog.timestamp >= since,
            )
            .order_by(AuditLog.timestamp.desc())
            .limit(limit)
            .all()
        )


# Import timedelta for time calculations
from datetime import timedelta
