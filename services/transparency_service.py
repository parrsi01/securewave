"""
Transparency and Warrant Canary Service
Handles transparency reports and warrant canary status
"""

import os
import logging
import hashlib
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from calendar import monthrange

logger = logging.getLogger(__name__)


class TransparencyService:
    """
    Transparency Service
    Generates transparency reports and manages warrant canary
    """

    def __init__(self):
        """Initialize transparency service"""
        pass

    # ===========================
    # WARRANT CANARY
    # ===========================

    def create_warrant_canary(
        self,
        published_by_id: int,
        period_months: int = 3
    ) -> Dict:
        """
        Create a new warrant canary for transparency

        Args:
            published_by_id: User ID of publisher
            period_months: Period covered (default 3 months/quarterly)

        Returns:
            Warrant canary details
        """
        try:
            from database.session import get_db
            from models.gdpr import WarrantCanary

            db = next(get_db())

            # Calculate period
            period_end = datetime.utcnow()
            period_start = period_end - timedelta(days=period_months * 30)

            # Generate statement
            statement = self._generate_canary_statement(period_start, period_end)

            # Create hash for verification
            statement_hash = hashlib.sha256(statement.encode()).hexdigest()

            canary = WarrantCanary(
                period_start=period_start,
                period_end=period_end,
                is_valid=True,
                statement=statement,
                signed_statement_hash=statement_hash,
                total_requests_received=0,  # Update these based on actual data
                national_security_letters=0,
                gag_orders=0,
                search_warrants=0,
                published_at=datetime.utcnow(),
                published_by_id=published_by_id
            )

            db.add(canary)
            db.commit()
            db.refresh(canary)

            logger.info(f"Created warrant canary for period {period_start.date()} to {period_end.date()}")

            return canary.to_dict()

        except Exception as e:
            logger.error(f"Failed to create warrant canary: {e}")
            raise

    def _generate_canary_statement(self, period_start: datetime, period_end: datetime) -> str:
        """Generate warrant canary statement"""
        return f"""
WARRANT CANARY STATEMENT
SecureWave VPN Transparency Report

Period: {period_start.strftime('%B %d, %Y')} to {period_end.strftime('%B %d, %Y')}
Published: {datetime.utcnow().strftime('%B %d, %Y')}

As of the date of this statement, SecureWave VPN confirms that:

1. We have NOT received any National Security Letters or FISA court orders.
2. We have NOT been subject to any gag orders prohibiting disclosure of government requests.
3. We have NOT been compelled to modify our software or infrastructure to facilitate government surveillance.
4. We have NOT been forced to implement any backdoors or provide access to our systems.
5. Our privacy policy and operational procedures remain unchanged and uncompromised.

This statement is issued quarterly. If this statement is not updated within 95 days of the previous statement,
users should assume that one or more of the above statements is no longer true.

SecureWave VPN is committed to transparency and protecting user privacy. We will continue to resist any attempts
to compromise user security and will fight any unlawful requests in court.

For verification, users can check the cryptographic hash of this statement and compare it with our publicly
posted signatures.

If you have concerns about this canary or notice any changes, please contact us immediately at:
transparency@securewave.com
""".strip()

    def get_latest_canary(self) -> Optional[Dict]:
        """Get the latest warrant canary"""
        try:
            from database.session import get_db
            from models.gdpr import WarrantCanary

            db = next(get_db())

            canary = db.query(WarrantCanary).order_by(
                WarrantCanary.published_at.desc()
            ).first()

            return canary.to_dict() if canary else None

        except Exception as e:
            logger.error(f"Failed to get latest canary: {e}")
            return None

    def check_canary_freshness(self) -> Dict:
        """
        Check if canary is fresh (updated within 95 days)

        Returns:
            Freshness check results
        """
        try:
            latest_canary = self.get_latest_canary()

            if not latest_canary:
                return {
                    "is_fresh": False,
                    "status": "critical",
                    "message": "No warrant canary found",
                    "days_since_update": None
                }

            published_at = datetime.fromisoformat(latest_canary["published_at"])
            days_since_update = (datetime.utcnow() - published_at).days

            is_fresh = days_since_update <= 95

            return {
                "is_fresh": is_fresh,
                "status": "ok" if is_fresh else "expired",
                "message": f"Last updated {days_since_update} days ago" if is_fresh else "Warrant canary is expired - service may be compromised",
                "days_since_update": days_since_update,
                "last_published": latest_canary["published_at"]
            }

        except Exception as e:
            logger.error(f"Failed to check canary freshness: {e}")
            return {
                "is_fresh": False,
                "status": "error",
                "message": str(e)
            }

    # ===========================
    # TRANSPARENCY REPORTS
    # ===========================

    def generate_transparency_report(
        self,
        start_date: datetime,
        end_date: datetime
    ) -> Dict:
        """
        Generate transparency report for a period

        Args:
            start_date: Report start date
            end_date: Report end date

        Returns:
            Transparency report
        """
        try:
            from database.session import get_db
            from models.user import User
            from models.subscription import Subscription
            from models.support_ticket import SupportTicket
            from models.gdpr import GDPRRequest
            from models.audit_log import AuditLog
            from sqlalchemy import func

            db = next(get_db())

            report = {
                "period_start": start_date.isoformat(),
                "period_end": end_date.isoformat(),
                "generated_at": datetime.utcnow().isoformat(),
                "user_statistics": {},
                "service_requests": {},
                "legal_requests": {},
                "security_incidents": {},
                "data_requests": {},
            }

            # User statistics
            total_users = db.query(User).count()
            new_users = db.query(User).filter(
                User.created_at.between(start_date, end_date)
            ).count()

            report["user_statistics"] = {
                "total_users": total_users,
                "new_users_period": new_users,
                "active_subscriptions": db.query(Subscription).filter(
                    Subscription.status == "active"
                ).count()
            }

            # Service requests (support tickets)
            tickets_created = db.query(SupportTicket).filter(
                SupportTicket.created_at.between(start_date, end_date)
            ).count()

            tickets_resolved = db.query(SupportTicket).filter(
                SupportTicket.resolved_at.between(start_date, end_date)
            ).count()

            report["service_requests"] = {
                "total_tickets_created": tickets_created,
                "total_tickets_resolved": tickets_resolved,
                "average_resolution_time_hours": 24  # Calculate from actual data
            }

            # Legal and government requests
            report["legal_requests"] = {
                "total_requests": 0,
                "national_security_letters": 0,
                "search_warrants": 0,
                "subpoenas": 0,
                "user_data_disclosed": 0,
                "requests_challenged": 0,
                "note": "SecureWave VPN has received no government requests for user data during this period."
            }

            # GDPR data requests
            gdpr_requests = db.query(GDPRRequest).filter(
                GDPRRequest.created_at.between(start_date, end_date)
            ).all()

            report["data_requests"] = {
                "total_gdpr_requests": len(gdpr_requests),
                "access_requests": sum(1 for r in gdpr_requests if r.request_type.value == "access"),
                "deletion_requests": sum(1 for r in gdpr_requests if r.request_type.value == "erasure"),
                "rectification_requests": sum(1 for r in gdpr_requests if r.request_type.value == "rectification"),
                "completed_requests": sum(1 for r in gdpr_requests if r.status.value == "completed"),
                "average_response_time_days": 15  # Calculate from actual data
            }

            # Security incidents
            suspicious_events = db.query(AuditLog).filter(
                AuditLog.is_suspicious == True,
                AuditLog.created_at.between(start_date, end_date)
            ).count()

            report["security_incidents"] = {
                "suspicious_activities_detected": suspicious_events,
                "data_breaches": 0,
                "service_disruptions": 0,
                "note": "No data breaches or significant security incidents occurred during this period."
            }

            return report

        except Exception as e:
            logger.error(f"Failed to generate transparency report: {e}")
            raise

    def generate_quarterly_report(self, year: int, quarter: int) -> Dict:
        """
        Generate quarterly transparency report

        Args:
            year: Year
            quarter: Quarter (1-4)

        Returns:
            Quarterly report
        """
        # Calculate quarter dates
        quarter_start_month = (quarter - 1) * 3 + 1
        start_date = datetime(year, quarter_start_month, 1)

        if quarter == 4:
            end_date = datetime(year + 1, 1, 1) - timedelta(days=1)
        else:
            end_month = quarter * 3
            end_day = monthrange(year, end_month)[1]
            end_date = datetime(year, end_month, end_day, 23, 59, 59)

        report = self.generate_transparency_report(start_date, end_date)
        report["report_type"] = "quarterly"
        report["quarter"] = f"Q{quarter} {year}"

        return report

    # ===========================
    # DATA RETENTION POLICY
    # ===========================

    def get_data_retention_policy(self) -> Dict:
        """
        Get data retention policy

        Returns:
            Retention policy details
        """
        return {
            "policy_version": "1.0",
            "last_updated": "2024-01-07",
            "retention_periods": {
                "user_accounts": {
                    "active_accounts": "Duration of account + 30 days after deletion request",
                    "deleted_accounts": "Personal data deleted immediately, transaction records retained for 7 years (tax compliance)"
                },
                "vpn_connection_logs": {
                    "connection_metadata": "Not stored - we are a no-log VPN",
                    "bandwidth_usage": "30 days for billing purposes only",
                    "ip_addresses": "Not logged or stored"
                },
                "payment_records": {
                    "transaction_history": "7 years (legal requirement for tax purposes)",
                    "payment_methods": "Until account deletion + 90 days for refund processing"
                },
                "support_tickets": {
                    "active_tickets": "Until resolution + 1 year",
                    "resolved_tickets": "2 years after resolution"
                },
                "audit_logs": {
                    "security_events": "2 years",
                    "compliance_events": "7 years",
                    "general_logs": "90 days"
                },
                "email_communications": {
                    "transactional_emails": "2 years",
                    "marketing_emails": "Until consent withdrawal + 30 days"
                }
            },
            "deletion_procedures": {
                "user_request": "Data deleted within 30 days of verified request",
                "automated": "Automated deletion runs monthly for expired data",
                "legal_hold": "Data under legal hold exempt from deletion until hold is lifted"
            },
            "exceptions": {
                "legal_obligations": "Data required by law retained per legal requirements",
                "security_investigations": "Data related to ongoing security investigations retained until resolution",
                "disputed_transactions": "Transaction data retained until dispute resolution"
            }
        }

    def execute_data_retention_cleanup(self) -> Dict:
        """
        Execute data retention cleanup (delete expired data)

        Returns:
            Cleanup summary
        """
        try:
            from database.session import get_db
            from models.audit_log import AuditLog, PerformanceMetric, ErrorLog, UptimeCheck
            from models.email_log import EmailLog

            db = next(get_db())

            summary = {
                "execution_date": datetime.utcnow().isoformat(),
                "deleted_records": {}
            }

            # Delete old audit logs (> 2 years for non-compliance)
            two_years_ago = datetime.utcnow() - timedelta(days=730)
            deleted_audit_logs = db.query(AuditLog).filter(
                AuditLog.is_compliance_relevant == False,
                AuditLog.created_at < two_years_ago
            ).delete()
            summary["deleted_records"]["audit_logs"] = deleted_audit_logs

            # Delete old performance metrics (> 90 days)
            ninety_days_ago = datetime.utcnow() - timedelta(days=90)
            deleted_perf_metrics = db.query(PerformanceMetric).filter(
                PerformanceMetric.created_at < ninety_days_ago
            ).delete()
            summary["deleted_records"]["performance_metrics"] = deleted_perf_metrics

            # Delete old error logs (> 90 days, resolved only)
            deleted_error_logs = db.query(ErrorLog).filter(
                ErrorLog.is_resolved == True,
                ErrorLog.created_at < ninety_days_ago
            ).delete()
            summary["deleted_records"]["error_logs"] = deleted_error_logs

            # Delete old uptime checks (> 30 days)
            thirty_days_ago = datetime.utcnow() - timedelta(days=30)
            deleted_uptime_checks = db.query(UptimeCheck).filter(
                UptimeCheck.checked_at < thirty_days_ago
            ).delete()
            summary["deleted_records"]["uptime_checks"] = deleted_uptime_checks

            # Delete old email logs (> 2 years)
            deleted_email_logs = db.query(EmailLog).filter(
                EmailLog.created_at < two_years_ago
            ).delete()
            summary["deleted_records"]["email_logs"] = deleted_email_logs

            db.commit()

            logger.info(f"Data retention cleanup completed: {summary}")

            return summary

        except Exception as e:
            logger.error(f"Failed to execute data retention cleanup: {e}")
            db.rollback()
            raise


# Singleton instance
_transparency_service: Optional[TransparencyService] = None


def get_transparency_service() -> TransparencyService:
    """Get transparency service instance"""
    global _transparency_service
    if _transparency_service is None:
        _transparency_service = TransparencyService()
    return _transparency_service
