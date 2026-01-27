"""
GDPR Compliance Service
Handles GDPR data subject rights and compliance requirements
"""

import os
import json
import logging
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

# Configuration
GDPR_RESPONSE_DEADLINE_DAYS = int(os.getenv("GDPR_RESPONSE_DEADLINE_DAYS", "30"))  # 30 days per GDPR


class GDPRComplianceService:
    """
    GDPR Compliance Service
    Implements data subject rights and GDPR requirements
    """

    def __init__(self):
        """Initialize GDPR service"""
        self.response_deadline_days = GDPR_RESPONSE_DEADLINE_DAYS

    # ===========================
    # DATA SUBJECT ACCESS REQUEST
    # ===========================

    def create_access_request(
        self,
        user_id: int,
        description: Optional[str] = None,
        specific_data: Optional[List[str]] = None
    ) -> Dict:
        """
        Create a GDPR data access request

        Args:
            user_id: User ID
            description: Request description
            specific_data: Specific data categories requested

        Returns:
            Request details
        """
        try:
            from database.session import get_db
            from models.gdpr import GDPRRequest, GDPRRequestType, GDPRRequestStatus

            db = next(get_db())

            # Generate request number
            request_number = self._generate_request_number()

            # Calculate due date (30 days)
            due_date = datetime.utcnow() + timedelta(days=self.response_deadline_days)

            request = GDPRRequest(
                request_number=request_number,
                user_id=user_id,
                request_type=GDPRRequestType.ACCESS,
                status=GDPRRequestStatus.PENDING,
                description=description,
                specific_data_requested=specific_data or [],
                due_date=due_date,
                verification_method="email"
            )

            db.add(request)
            db.commit()
            db.refresh(request)

            logger.info(f"Created GDPR access request {request_number} for user {user_id}")

            return request.to_dict()

        except Exception as e:
            logger.error(f"Failed to create GDPR access request: {e}")
            raise

    def export_user_data(self, user_id: int, format: str = "json") -> Dict[str, Any]:
        """
        Export all user data for GDPR compliance

        Args:
            user_id: User ID
            format: Export format (json, csv)

        Returns:
            User data export
        """
        try:
            from database.session import get_db
            from models.user import User
            from models.subscription import Subscription
            from models.vpn_connection import VPNConnection
            from models.wireguard_peer import WireGuardPeer
            from models.support_ticket import SupportTicket
            from models.usage_analytics import UserUsageStats
            from models.audit_log import AuditLog

            db = next(get_db())

            # Get user
            user = db.query(User).filter(User.id == user_id).first()
            if not user:
                raise ValueError(f"User {user_id} not found")

            # Collect all user data
            data_export = {
                "export_date": datetime.utcnow().isoformat(),
                "user_id": user_id,
                "personal_information": {
                    "email": user.email,
                    "full_name": getattr(user, "full_name", None),
                    "created_at": user.created_at.isoformat() if user.created_at else None,
                    "email_verified": user.email_verified,
                    "totp_enabled": user.totp_enabled,
                },
                "subscriptions": [],
                "vpn_connections": [],
                "wireguard_peers": [],
                "support_tickets": [],
                "usage_statistics": None,
                "audit_logs": [],
            }

            # Subscriptions
            subscriptions = db.query(Subscription).filter(Subscription.user_id == user_id).all()
            for sub in subscriptions:
                data_export["subscriptions"].append({
                    "plan": sub.plan,
                    "status": sub.status,
                    "start_date": sub.start_date.isoformat() if sub.start_date else None,
                    "end_date": sub.end_date.isoformat() if sub.end_date else None,
                    "price": float(sub.price) if sub.price else None,
                })

            # VPN Connections
            connections = db.query(VPNConnection).filter(VPNConnection.user_id == user_id).limit(1000).all()
            for conn in connections:
                data_export["vpn_connections"].append({
                    "server_id": conn.server_id,
                    "connected_at": conn.connected_at.isoformat() if conn.connected_at else None,
                    "disconnected_at": conn.disconnected_at.isoformat() if conn.disconnected_at else None,
                    "data_sent": conn.data_sent,
                    "data_received": conn.data_received,
                })

            # WireGuard Peers
            peers = db.query(WireGuardPeer).filter(WireGuardPeer.user_id == user_id).all()
            for peer in peers:
                data_export["wireguard_peers"].append({
                    "device_name": peer.device_name,
                    "device_type": peer.device_type,
                    "ipv4_address": peer.ipv4_address,
                    "created_at": peer.created_at.isoformat() if peer.created_at else None,
                    "is_active": peer.is_active,
                })

            # Support Tickets
            tickets = db.query(SupportTicket).filter(SupportTicket.user_id == user_id).all()
            for ticket in tickets:
                data_export["support_tickets"].append({
                    "ticket_number": ticket.ticket_number,
                    "subject": ticket.subject,
                    "category": ticket.category,
                    "status": ticket.status,
                    "created_at": ticket.created_at.isoformat() if ticket.created_at else None,
                })

            # Usage Statistics
            stats = db.query(UserUsageStats).filter(UserUsageStats.user_id == user_id).first()
            if stats:
                data_export["usage_statistics"] = {
                    "total_connections": stats.total_connections,
                    "total_data_gb": stats.total_data_gb,
                    "account_age_days": stats.account_age_days,
                }

            # Audit Logs (last 100 entries)
            audit_logs = db.query(AuditLog).filter(AuditLog.user_id == user_id).order_by(AuditLog.created_at.desc()).limit(100).all()
            for log in audit_logs:
                data_export["audit_logs"].append({
                    "event_type": log.event_type,
                    "action": log.action,
                    "description": log.description,
                    "created_at": log.created_at.isoformat() if log.created_at else None,
                })

            return data_export

        except Exception as e:
            logger.error(f"Failed to export user data: {e}")
            raise

    # ===========================
    # RIGHT TO ERASURE (RTBF)
    # ===========================

    def create_deletion_request(
        self,
        user_id: int,
        description: Optional[str] = None
    ) -> Dict:
        """
        Create a data deletion request (Right to be Forgotten)

        Args:
            user_id: User ID
            description: Request description

        Returns:
            Request details
        """
        try:
            from database.session import get_db
            from models.gdpr import GDPRRequest, GDPRRequestType, GDPRRequestStatus

            db = next(get_db())

            request_number = self._generate_request_number()
            due_date = datetime.utcnow() + timedelta(days=self.response_deadline_days)

            request = GDPRRequest(
                request_number=request_number,
                user_id=user_id,
                request_type=GDPRRequestType.ERASURE,
                status=GDPRRequestStatus.PENDING,
                description=description,
                due_date=due_date
            )

            db.add(request)
            db.commit()
            db.refresh(request)

            logger.info(f"Created GDPR deletion request {request_number} for user {user_id}")

            return request.to_dict()

        except Exception as e:
            logger.error(f"Failed to create deletion request: {e}")
            raise

    def delete_user_data(self, user_id: int, retention_required: bool = False) -> Dict:
        """
        Delete all user data (Right to be Forgotten)

        Args:
            user_id: User ID
            retention_required: Whether some data must be retained for legal reasons

        Returns:
            Deletion summary
        """
        try:
            from database.session import get_db
            from models.user import User

            db = next(get_db())

            summary = {
                "user_id": user_id,
                "deletion_date": datetime.utcnow().isoformat(),
                "deleted_records": {},
                "anonymized_records": {},
                "retained_records": {},
            }

            # If retention required (e.g., tax records), anonymize instead of delete
            if retention_required:
                # Anonymize user data
                user = db.query(User).filter(User.id == user_id).first()
                if user:
                    user.email = f"deleted_user_{user_id}@anonymized.local"
                    user.full_name = f"Deleted User {user_id}"
                    user.password_hash = ""  # nosec B105 - clearing password hash for GDPR anonymization
                    user.totp_secret = None

                    summary["anonymized_records"]["user"] = 1

                # Keep audit logs, payment records for legal retention
                summary["retained_records"]["audit_logs"] = "retained for legal compliance"
                summary["retained_records"]["payment_records"] = "retained for tax compliance (7 years)"
            else:
                # Full deletion
                # Delete user and cascade will handle related records
                user = db.query(User).filter(User.id == user_id).first()
                if user:
                    db.delete(user)
                    summary["deleted_records"]["user"] = 1

            db.commit()

            logger.info(f"Deleted data for user {user_id}")

            return summary

        except Exception as e:
            logger.error(f"Failed to delete user data: {e}")
            db.rollback()
            raise

    # ===========================
    # CONSENT MANAGEMENT
    # ===========================

    def record_consent(
        self,
        user_id: int,
        consent_type: str,
        is_granted: bool,
        consent_version: str,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None
    ) -> Dict:
        """
        Record user consent

        Args:
            user_id: User ID
            consent_type: Type of consent
            is_granted: Whether consent was granted
            consent_version: Version of T&C/Privacy Policy
            ip_address: IP address
            user_agent: User agent

        Returns:
            Consent record
        """
        try:
            from database.session import get_db
            from models.gdpr import UserConsent, ConsentType

            db = next(get_db())

            consent = UserConsent(
                user_id=user_id,
                consent_type=ConsentType[consent_type.upper()],
                consent_version=consent_version,
                is_granted=is_granted,
                granted_at=datetime.utcnow() if is_granted else None,
                revoked_at=None if is_granted else datetime.utcnow(),
                ip_address=ip_address,
                user_agent=user_agent,
                consent_method="checkbox"
            )

            db.add(consent)
            db.commit()
            db.refresh(consent)

            logger.info(f"Recorded {consent_type} consent for user {user_id}: {is_granted}")

            return consent.to_dict()

        except Exception as e:
            logger.error(f"Failed to record consent: {e}")
            raise

    def get_user_consents(self, user_id: int) -> List[Dict]:
        """Get all consents for a user"""
        try:
            from database.session import get_db
            from models.gdpr import UserConsent

            db = next(get_db())

            consents = db.query(UserConsent).filter(
                UserConsent.user_id == user_id
            ).order_by(UserConsent.created_at.desc()).all()

            return [consent.to_dict() for consent in consents]

        except Exception as e:
            logger.error(f"Failed to get user consents: {e}")
            return []

    # ===========================
    # HELPER METHODS
    # ===========================

    def _generate_request_number(self) -> str:
        """Generate GDPR request number"""
        from datetime import datetime
        import secrets

        timestamp = datetime.utcnow().strftime("%Y%m")
        random_part = secrets.randbelow(90000) + 10000
        return f"GDPR-{timestamp}-{random_part}"

    def get_pending_requests(self) -> List[Dict]:
        """Get pending GDPR requests"""
        try:
            from database.session import get_db
            from models.gdpr import GDPRRequest, GDPRRequestStatus

            db = next(get_db())

            requests = db.query(GDPRRequest).filter(
                GDPRRequest.status.in_([GDPRRequestStatus.PENDING, GDPRRequestStatus.IN_PROGRESS])
            ).order_by(GDPRRequest.due_date.asc()).all()

            return [req.to_dict() for req in requests]

        except Exception as e:
            logger.error(f"Failed to get pending requests: {e}")
            return []

    def check_sla_breaches(self) -> List[Dict]:
        """Check for SLA breaches on GDPR requests"""
        try:
            from database.session import get_db
            from models.gdpr import GDPRRequest, GDPRRequestStatus

            db = next(get_db())

            now = datetime.utcnow()

            # Find overdue requests
            overdue_requests = db.query(GDPRRequest).filter(
                GDPRRequest.status != GDPRRequestStatus.COMPLETED,
                GDPRRequest.due_date < now,
                GDPRRequest.sla_breached == False
            ).all()

            # Mark as breached
            for req in overdue_requests:
                req.sla_breached = True

            db.commit()

            return [req.to_dict() for req in overdue_requests]

        except Exception as e:
            logger.error(f"Failed to check SLA breaches: {e}")
            return []


# Singleton instance
_gdpr_service: Optional[GDPRComplianceService] = None


def get_gdpr_service() -> GDPRComplianceService:
    """Get GDPR compliance service instance"""
    global _gdpr_service
    if _gdpr_service is None:
        _gdpr_service = GDPRComplianceService()
    return _gdpr_service
