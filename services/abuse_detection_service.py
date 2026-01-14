"""
SecureWave VPN - Abuse Detection Service
Detect and prevent abuse, policy violations, and suspicious activity
"""

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from models.user import User
from models.vpn_connection import VPNConnection
from models.usage_analytics import UserUsageStats, AbuseDetectionLog

logger = logging.getLogger(__name__)

# Thresholds for abuse detection
EXCESSIVE_BANDWIDTH_GB_PER_DAY = 500  # 500 GB/day
RAPID_RECONNECT_COUNT = 50  # 50 reconnections in 1 hour
MAX_CONCURRENT_CONNECTIONS = 5  # Max simultaneous connections
SUSPICIOUS_TRAFFIC_RATIO = 10.0  # Upload/download ratio > 10:1 or < 1:10
ACCOUNT_SHARING_THRESHOLD = 3  # Different IPs in short timespan


class AbuseDetectionService:
    """
    Production-grade abuse detection and prevention service
    Monitors usage patterns and detects policy violations
    """

    def __init__(self, db: Session):
        """Initialize abuse detection service"""
        self.db = db

    # ===========================
    # ABUSE DETECTION
    # ===========================

    def detect_excessive_bandwidth(self, user_id: int) -> Optional[AbuseDetectionLog]:
        """
        Detect excessive bandwidth usage

        Args:
            user_id: User ID

        Returns:
            AbuseDetectionLog if abuse detected, None otherwise
        """
        try:
            # Get user's recent connections (last 24 hours)
            day_ago = datetime.utcnow() - timedelta(days=1)

            connections = self.db.query(VPNConnection).filter(
                and_(
                    VPNConnection.user_id == user_id,
                    VPNConnection.connected_at >= day_ago
                )
            ).all()

            if not connections:
                return None

            # Calculate total bandwidth
            total_bytes = sum(
                (c.total_bytes_sent or 0) + (c.total_bytes_received or 0)
                for c in connections
            )
            total_gb = total_bytes / 1024 / 1024 / 1024

            if total_gb > EXCESSIVE_BANDWIDTH_GB_PER_DAY:
                return self._log_abuse(
                    user_id=user_id,
                    incident_type="excessive_bandwidth",
                    severity="high",
                    description=f"User exceeded bandwidth limit: {total_gb:.2f} GB in 24 hours",
                    metadata={
                        "total_gb": round(total_gb, 2),
                        "threshold_gb": EXCESSIVE_BANDWIDTH_GB_PER_DAY,
                        "connection_count": len(connections),
                    }
                )

            return None

        except Exception as e:
            logger.error(f"Error detecting excessive bandwidth: {e}")
            return None

    def detect_rapid_reconnects(self, user_id: int) -> Optional[AbuseDetectionLog]:
        """
        Detect rapid connection/disconnection patterns

        Args:
            user_id: User ID

        Returns:
            AbuseDetectionLog if abuse detected
        """
        try:
            # Get connections in last hour
            hour_ago = datetime.utcnow() - timedelta(hours=1)

            connection_count = self.db.query(VPNConnection).filter(
                and_(
                    VPNConnection.user_id == user_id,
                    VPNConnection.connected_at >= hour_ago
                )
            ).count()

            if connection_count > RAPID_RECONNECT_COUNT:
                return self._log_abuse(
                    user_id=user_id,
                    incident_type="rapid_reconnects",
                    severity="medium",
                    description=f"Unusual reconnection pattern: {connection_count} connections in 1 hour",
                    metadata={
                        "connection_count": connection_count,
                        "threshold": RAPID_RECONNECT_COUNT,
                        "timeframe_hours": 1,
                    }
                )

            return None

        except Exception as e:
            logger.error(f"Error detecting rapid reconnects: {e}")
            return None

    def detect_concurrent_connections(self, user_id: int) -> Optional[AbuseDetectionLog]:
        """
        Detect excessive concurrent connections (account sharing)

        Args:
            user_id: User ID

        Returns:
            AbuseDetectionLog if abuse detected
        """
        try:
            # Get active connections
            active_connections = self.db.query(VPNConnection).filter(
                and_(
                    VPNConnection.user_id == user_id,
                    VPNConnection.disconnected_at == None
                )
            ).all()

            if len(active_connections) > MAX_CONCURRENT_CONNECTIONS:
                # Get unique IPs
                unique_ips = set(c.public_ip for c in active_connections if c.public_ip)

                return self._log_abuse(
                    user_id=user_id,
                    incident_type="excessive_concurrent_connections",
                    severity="high",
                    description=f"Too many concurrent connections: {len(active_connections)} active",
                    metadata={
                        "concurrent_connections": len(active_connections),
                        "threshold": MAX_CONCURRENT_CONNECTIONS,
                        "unique_ips": len(unique_ips),
                        "ips": list(unique_ips),
                    }
                )

            return None

        except Exception as e:
            logger.error(f"Error detecting concurrent connections: {e}")
            return None

    def detect_suspicious_traffic_pattern(self, user_id: int) -> Optional[AbuseDetectionLog]:
        """
        Detect suspicious traffic patterns (e.g., upload-only or download-only)

        Args:
            user_id: User ID

        Returns:
            AbuseDetectionLog if abuse detected
        """
        try:
            # Get recent connections
            day_ago = datetime.utcnow() - timedelta(days=1)

            connections = self.db.query(VPNConnection).filter(
                and_(
                    VPNConnection.user_id == user_id,
                    VPNConnection.connected_at >= day_ago
                )
            ).all()

            if not connections:
                return None

            # Calculate totals
            total_sent = sum(c.total_bytes_sent or 0 for c in connections)
            total_received = sum(c.total_bytes_received or 0 for c in connections)

            if total_sent == 0 or total_received == 0:
                return None

            # Calculate ratio
            ratio = total_sent / total_received if total_received > 0 else 0

            if ratio > SUSPICIOUS_TRAFFIC_RATIO or ratio < (1 / SUSPICIOUS_TRAFFIC_RATIO):
                return self._log_abuse(
                    user_id=user_id,
                    incident_type="suspicious_traffic_pattern",
                    severity="medium",
                    description=f"Unusual traffic pattern detected (upload/download ratio: {ratio:.2f})",
                    metadata={
                        "upload_gb": round(total_sent / 1024 / 1024 / 1024, 2),
                        "download_gb": round(total_received / 1024 / 1024 / 1024, 2),
                        "ratio": round(ratio, 2),
                    }
                )

            return None

        except Exception as e:
            logger.error(f"Error detecting suspicious traffic: {e}")
            return None

    def detect_account_sharing(self, user_id: int) -> Optional[AbuseDetectionLog]:
        """
        Detect potential account sharing (multiple IPs in short timespan)

        Args:
            user_id: User ID

        Returns:
            AbuseDetectionLog if abuse detected
        """
        try:
            # Get connections in last hour
            hour_ago = datetime.utcnow() - timedelta(hours=1)

            connections = self.db.query(VPNConnection).filter(
                and_(
                    VPNConnection.user_id == user_id,
                    VPNConnection.connected_at >= hour_ago
                )
            ).all()

            if not connections:
                return None

            # Get unique public IPs
            unique_ips = set(c.public_ip for c in connections if c.public_ip)

            if len(unique_ips) >= ACCOUNT_SHARING_THRESHOLD:
                return self._log_abuse(
                    user_id=user_id,
                    incident_type="potential_account_sharing",
                    severity="high",
                    description=f"Multiple IP addresses detected: {len(unique_ips)} IPs in 1 hour",
                    metadata={
                        "unique_ips": len(unique_ips),
                        "ips": list(unique_ips),
                        "threshold": ACCOUNT_SHARING_THRESHOLD,
                        "connection_count": len(connections),
                    }
                )

            return None

        except Exception as e:
            logger.error(f"Error detecting account sharing: {e}")
            return None

    # ===========================
    # COMPREHENSIVE CHECKS
    # ===========================

    def run_all_checks(self, user_id: int) -> List[AbuseDetectionLog]:
        """
        Run all abuse detection checks for a user

        Args:
            user_id: User ID

        Returns:
            List of detected abuses
        """
        abuses = []

        checks = [
            self.detect_excessive_bandwidth,
            self.detect_rapid_reconnects,
            self.detect_concurrent_connections,
            self.detect_suspicious_traffic_pattern,
            self.detect_account_sharing,
        ]

        for check in checks:
            try:
                result = check(user_id)
                if result:
                    abuses.append(result)
            except Exception as e:
                logger.error(f"Error in abuse check {check.__name__}: {e}")
                continue

        return abuses

    def scan_all_users(self) -> Dict[str, int]:
        """
        Scan all active users for abuse

        Returns:
            Dictionary with scan results
        """
        try:
            # Get all active users
            active_users = self.db.query(User).filter(User.is_active == True).all()

            total_scanned = 0
            total_abuses = 0

            for user in active_users:
                total_scanned += 1
                abuses = self.run_all_checks(user.id)
                total_abuses += len(abuses)

            logger.info(f"✓ Abuse scan complete: {total_scanned} users scanned, {total_abuses} abuses detected")

            return {
                "users_scanned": total_scanned,
                "abuses_detected": total_abuses,
                "scan_completed_at": datetime.utcnow().isoformat(),
            }

        except Exception as e:
            logger.error(f"✗ Abuse scan failed: {e}")
            return {
                "error": str(e),
                "users_scanned": 0,
                "abuses_detected": 0,
            }

    # ===========================
    # ABUSE LOGGING & MANAGEMENT
    # ===========================

    def _log_abuse(
        self,
        user_id: int,
        incident_type: str,
        severity: str,
        description: str,
        metadata: Optional[Dict] = None
    ) -> AbuseDetectionLog:
        """
        Log abuse incident

        Args:
            user_id: User ID
            incident_type: Type of abuse
            severity: Severity level (low, medium, high, critical)
            description: Description
            metadata: Additional metadata

        Returns:
            AbuseDetectionLog
        """
        try:
            log = AbuseDetectionLog(
                user_id=user_id,
                incident_type=incident_type,
                severity=severity,
                description=description,
                metadata=metadata,
                detection_method="automated",
                status="pending",
            )

            self.db.add(log)
            self.db.commit()
            self.db.refresh(log)

            logger.warning(f"⚠️ Abuse detected: {incident_type} for user {user_id} (severity: {severity})")

            # Auto-take action for critical incidents
            if severity == "critical":
                self._auto_mitigate(log)

            return log

        except Exception as e:
            logger.error(f"Failed to log abuse: {e}")
            self.db.rollback()
            raise

    def _auto_mitigate(self, abuse_log: AbuseDetectionLog):
        """
        Automatically mitigate abuse (for critical incidents)

        Args:
            abuse_log: AbuseDetectionLog
        """
        try:
            # For critical incidents, we could:
            # 1. Temporarily suspend account
            # 2. Send warning email
            # 3. Alert admins
            # 4. Rate limit the user

            # For now, just mark action taken
            abuse_log.action_taken = "automated_alert"
            abuse_log.action_notes = "Critical incident detected - admin alerted"
            self.db.commit()

            logger.critical(f"🚨 Critical abuse detected for user {abuse_log.user_id} - auto-mitigation triggered")

        except Exception as e:
            logger.error(f"Auto-mitigation failed: {e}")

    def get_user_abuse_history(self, user_id: int, limit: int = 50) -> List[AbuseDetectionLog]:
        """
        Get abuse history for user

        Args:
            user_id: User ID
            limit: Max number of records

        Returns:
            List of AbuseDetectionLog
        """
        return self.db.query(AbuseDetectionLog).filter(
            AbuseDetectionLog.user_id == user_id
        ).order_by(AbuseDetectionLog.detected_at.desc()).limit(limit).all()

    def get_pending_abuses(self, severity: Optional[str] = None) -> List[AbuseDetectionLog]:
        """
        Get pending abuse incidents

        Args:
            severity: Optional filter by severity

        Returns:
            List of AbuseDetectionLog
        """
        query = self.db.query(AbuseDetectionLog).filter(
            AbuseDetectionLog.status == "pending"
        )

        if severity:
            query = query.filter(AbuseDetectionLog.severity == severity)

        return query.order_by(AbuseDetectionLog.detected_at.desc()).all()

    def resolve_abuse(
        self,
        abuse_id: int,
        action_taken: str,
        action_notes: Optional[str] = None,
        admin_id: Optional[int] = None
    ) -> bool:
        """
        Resolve abuse incident

        Args:
            abuse_id: Abuse log ID
            action_taken: Action taken
            action_notes: Optional notes
            admin_id: Admin user ID

        Returns:
            True if successful
        """
        try:
            abuse = self.db.query(AbuseDetectionLog).filter(
                AbuseDetectionLog.id == abuse_id
            ).first()

            if not abuse:
                return False

            abuse.status = "resolved"
            abuse.action_taken = action_taken
            abuse.action_notes = action_notes
            abuse.action_by_id = admin_id
            abuse.resolved_at = datetime.utcnow()

            self.db.commit()

            logger.info(f"✓ Abuse incident {abuse_id} resolved: {action_taken}")
            return True

        except Exception as e:
            logger.error(f"Failed to resolve abuse: {e}")
            self.db.rollback()
            return False

    def get_abuse_statistics(self, days: int = 30) -> Dict:
        """
        Get abuse statistics

        Args:
            days: Number of days to analyze

        Returns:
            Statistics dictionary
        """
        try:
            start_date = datetime.utcnow() - timedelta(days=days)

            total_incidents = self.db.query(AbuseDetectionLog).filter(
                AbuseDetectionLog.detected_at >= start_date
            ).count()

            # Group by incident type
            by_type = self.db.query(
                AbuseDetectionLog.incident_type,
                func.count(AbuseDetectionLog.id).label("count")
            ).filter(
                AbuseDetectionLog.detected_at >= start_date
            ).group_by(AbuseDetectionLog.incident_type).all()

            # Group by severity
            by_severity = self.db.query(
                AbuseDetectionLog.severity,
                func.count(AbuseDetectionLog.id).label("count")
            ).filter(
                AbuseDetectionLog.detected_at >= start_date
            ).group_by(AbuseDetectionLog.severity).all()

            # Pending count
            pending = self.db.query(AbuseDetectionLog).filter(
                AbuseDetectionLog.status == "pending"
            ).count()

            return {
                "total_incidents": total_incidents,
                "pending_incidents": pending,
                "by_type": {t: c for t, c in by_type},
                "by_severity": {s: c for s, c in by_severity},
                "period_days": days,
            }

        except Exception as e:
            logger.error(f"Failed to get abuse statistics: {e}")
            return {}


def get_abuse_detection_service(db: Session) -> AbuseDetectionService:
    """Get abuse detection service instance"""
    return AbuseDetectionService(db)
