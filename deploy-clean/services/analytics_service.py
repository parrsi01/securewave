"""
SecureWave VPN - Analytics Service
Track and analyze user behavior, system performance, and business metrics
"""

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import func, and_

from models.user import User
from models.vpn_connection import VPNConnection
from models.subscription import Subscription
from models.support_ticket import SupportTicket, TicketStatus
from models.usage_analytics import (
    UserUsageStats,
    DailyUsageMetrics,
    SystemMetrics
)

logger = logging.getLogger(__name__)


class AnalyticsService:
    """
    Production-grade analytics service
    Aggregates and analyzes usage data for insights
    """

    def __init__(self, db: Session):
        """Initialize analytics service"""
        self.db = db

    # ===========================
    # USER ANALYTICS
    # ===========================

    def get_or_create_user_stats(self, user_id: int) -> UserUsageStats:
        """
        Get or create usage stats for user

        Args:
            user_id: User ID

        Returns:
            UserUsageStats object
        """
        stats = self.db.query(UserUsageStats).filter(
            UserUsageStats.user_id == user_id
        ).first()

        if not stats:
            stats = UserUsageStats(user_id=user_id)
            self.db.add(stats)
            self.db.commit()
            self.db.refresh(stats)

        return stats

    def update_user_stats(self, user_id: int) -> UserUsageStats:
        """
        Update user usage statistics from raw data

        Args:
            user_id: User ID

        Returns:
            Updated UserUsageStats
        """
        try:
            stats = self.get_or_create_user_stats(user_id)
            user = self.db.query(User).filter(User.id == user_id).first()

            if not user:
                return stats

            # Get all connections
            connections = self.db.query(VPNConnection).filter(
                VPNConnection.user_id == user_id
            ).all()

            # Calculate connection statistics
            stats.total_connections = len(connections)
            stats.active_connections = sum(1 for c in connections if c.is_active)

            if connections:
                total_duration = sum(c.duration_seconds for c in connections)
                stats.total_connection_time_seconds = total_duration
                stats.average_session_duration_seconds = total_duration // len(connections) if len(connections) > 0 else 0

                # Last connection
                last_conn = max(connections, key=lambda c: c.connected_at)
                stats.last_connection_at = last_conn.connected_at

                # Data usage
                total_sent = sum(c.total_bytes_sent or 0 for c in connections)
                total_received = sum(c.total_bytes_received or 0 for c in connections)
                stats.total_bytes_uploaded = total_sent
                stats.total_bytes_downloaded = total_received
                stats.total_data_gb = (total_sent + total_received) / 1024 / 1024 / 1024

                # Quality metrics
                latencies = [c.avg_latency_ms for c in connections if c.avg_latency_ms]
                if latencies:
                    stats.average_latency_ms = sum(latencies) / len(latencies)

                throughputs = [c.avg_throughput_mbps for c in connections if c.avg_throughput_mbps]
                if throughputs:
                    stats.average_throughput_mbps = sum(throughputs) / len(throughputs)

                # Server usage
                server_ids = [c.server_id for c in connections if c.server_id]
                if server_ids:
                    stats.unique_servers_used = len(set(server_ids))
                    # Find most used server
                    from collections import Counter
                    server_counts = Counter(server_ids)
                    most_common = server_counts.most_common(1)
                    if most_common:
                        # Get server_id from VPNServer table
                        from models.vpn_server import VPNServer
                        server = self.db.query(VPNServer).filter(
                            VPNServer.id == most_common[0][0]
                        ).first()
                        if server:
                            stats.favorite_server_id = server.server_id

            # Account activity
            stats.total_login_count = user.total_login_count if hasattr(user, 'total_login_count') else 0
            stats.last_login_at = user.last_login
            account_age = (datetime.utcnow() - user.created_at).days if user.created_at else 0
            stats.account_age_days = account_age

            # Subscription info
            active_sub = self.db.query(Subscription).filter(
                Subscription.user_id == user_id,
                Subscription.status.in_(["active", "trialing"])
            ).first()

            if active_sub:
                stats.current_subscription_tier = active_sub.plan_id

            # Support tickets
            all_tickets = self.db.query(SupportTicket).filter(
                SupportTicket.user_id == user_id
            ).all()

            stats.total_support_tickets = len(all_tickets)
            stats.open_support_tickets = sum(1 for t in all_tickets if t.is_open)

            # Update timestamp
            stats.last_activity_at = datetime.utcnow()
            stats.updated_at = datetime.utcnow()

            self.db.commit()
            self.db.refresh(stats)

            logger.info(f"✓ User stats updated for user {user_id}")
            return stats

        except Exception as e:
            logger.error(f"✗ Failed to update user stats: {e}")
            self.db.rollback()
            raise

    def get_user_daily_metrics(
        self,
        user_id: int,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None
    ) -> List[DailyUsageMetrics]:
        """
        Get daily usage metrics for user

        Args:
            user_id: User ID
            start_date: Start date (default: 30 days ago)
            end_date: End date (default: today)

        Returns:
            List of DailyUsageMetrics
        """
        if not start_date:
            start_date = datetime.utcnow() - timedelta(days=30)
        if not end_date:
            end_date = datetime.utcnow()

        metrics = self.db.query(DailyUsageMetrics).filter(
            and_(
                DailyUsageMetrics.user_id == user_id,
                DailyUsageMetrics.date >= start_date,
                DailyUsageMetrics.date <= end_date
            )
        ).order_by(DailyUsageMetrics.date).all()

        return metrics

    # ===========================
    # SYSTEM-WIDE ANALYTICS
    # ===========================

    def update_system_metrics(self) -> SystemMetrics:
        """
        Update system-wide metrics

        Returns:
            SystemMetrics object
        """
        try:
            metrics = SystemMetrics()

            # User metrics
            metrics.total_users = self.db.query(User).count()

            # Active users (last 24h, 7d, 30d)
            now = datetime.utcnow()
            day_ago = now - timedelta(days=1)
            week_ago = now - timedelta(days=7)
            month_ago = now - timedelta(days=30)

            metrics.active_users_24h = self.db.query(User).filter(
                User.last_login >= day_ago
            ).count()

            metrics.active_users_7d = self.db.query(User).filter(
                User.last_login >= week_ago
            ).count()

            metrics.active_users_30d = self.db.query(User).filter(
                User.last_login >= month_ago
            ).count()

            # New users today
            today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
            metrics.new_users_today = self.db.query(User).filter(
                User.created_at >= today_start
            ).count()

            # Connection metrics
            metrics.total_connections = self.db.query(VPNConnection).count()
            metrics.active_connections = self.db.query(VPNConnection).filter(
                VPNConnection.disconnected_at == None
            ).count()

            # Server metrics
            from models.vpn_server import VPNServer
            total_servers = self.db.query(VPNServer).count()
            metrics.total_servers = total_servers

            metrics.healthy_servers = self.db.query(VPNServer).filter(
                VPNServer.health_status == "healthy"
            ).count()

            metrics.degraded_servers = self.db.query(VPNServer).filter(
                VPNServer.health_status == "degraded"
            ).count()

            metrics.offline_servers = self.db.query(VPNServer).filter(
                VPNServer.status == "offline"
            ).count()

            # Subscription metrics
            metrics.total_subscriptions = self.db.query(Subscription).count()
            metrics.active_subscriptions = self.db.query(Subscription).filter(
                Subscription.status.in_(["active", "trialing"])
            ).count()

            # Calculate MRR (Monthly Recurring Revenue)
            active_subs = self.db.query(Subscription).filter(
                Subscription.status == "active"
            ).all()

            mrr = sum(
                sub.amount if sub.billing_cycle == "monthly" else sub.amount / 12
                for sub in active_subs
            )
            metrics.mrr = mrr

            # Support metrics
            metrics.open_tickets = self.db.query(SupportTicket).filter(
                SupportTicket.status.in_([
                    TicketStatus.OPEN,
                    TicketStatus.IN_PROGRESS,
                    TicketStatus.WAITING_USER,
                    TicketStatus.WAITING_SUPPORT
                ])
            ).count()

            resolved_24h = self.db.query(SupportTicket).filter(
                SupportTicket.resolved_at >= day_ago
            ).count()
            metrics.tickets_resolved_24h = resolved_24h

            # Save metrics
            self.db.add(metrics)
            self.db.commit()
            self.db.refresh(metrics)

            logger.info("✓ System metrics updated")
            return metrics

        except Exception as e:
            logger.error(f"✗ Failed to update system metrics: {e}")
            self.db.rollback()
            raise

    def get_latest_system_metrics(self) -> Optional[SystemMetrics]:
        """
        Get latest system metrics

        Returns:
            SystemMetrics object or None
        """
        return self.db.query(SystemMetrics).order_by(
            SystemMetrics.timestamp.desc()
        ).first()

    # ===========================
    # REPORTING
    # ===========================

    def get_user_report(self, user_id: int) -> Dict:
        """
        Generate comprehensive user report

        Args:
            user_id: User ID

        Returns:
            Report dictionary
        """
        stats = self.get_or_create_user_stats(user_id)
        user = self.db.query(User).filter(User.id == user_id).first()

        if not user:
            return {}

        # Get recent connections
        recent_connections = self.db.query(VPNConnection).filter(
            VPNConnection.user_id == user_id
        ).order_by(VPNConnection.connected_at.desc()).limit(10).all()

        # Get active subscription
        active_sub = self.db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status.in_(["active", "trialing"])
        ).first()

        return {
            "user": {
                "id": user.id,
                "email": user.email,
                "created_at": user.created_at.isoformat() if user.created_at else None,
                "email_verified": user.email_verified,
            },
            "usage_stats": stats.to_dict(),
            "subscription": active_sub.to_dict() if active_sub else None,
            "recent_connections": [conn.to_dict() for conn in recent_connections],
            "account_health": {
                "is_active": user.is_active,
                "has_2fa": user.has_2fa_enabled,
                "open_tickets": stats.open_support_tickets,
                "days_since_last_activity": (datetime.utcnow() - stats.last_activity_at).days if stats.last_activity_at else None,
            }
        }

    def get_admin_dashboard_stats(self) -> Dict:
        """
        Get statistics for admin dashboard

        Returns:
            Statistics dictionary
        """
        latest_metrics = self.get_latest_system_metrics()

        if not latest_metrics:
            # Generate metrics if none exist
            latest_metrics = self.update_system_metrics()

        return {
            "system_metrics": latest_metrics.to_dict(),
            "top_users_by_data": self._get_top_users_by_data(limit=10),
            "top_users_by_connections": self._get_top_users_by_connections(limit=10),
            "server_health": self._get_server_health_summary(),
            "revenue_metrics": self._get_revenue_metrics(),
        }

    def _get_top_users_by_data(self, limit: int = 10) -> List[Dict]:
        """Get top users by data usage"""
        top_users = self.db.query(UserUsageStats).order_by(
            UserUsageStats.total_data_gb.desc()
        ).limit(limit).all()

        return [
            {
                "user_id": stats.user_id,
                "total_data_gb": round(stats.total_data_gb, 2),
                "current_month_data_gb": round(stats.current_month_data_gb, 2),
            }
            for stats in top_users
        ]

    def _get_top_users_by_connections(self, limit: int = 10) -> List[Dict]:
        """Get top users by connection count"""
        top_users = self.db.query(UserUsageStats).order_by(
            UserUsageStats.total_connections.desc()
        ).limit(limit).all()

        return [
            {
                "user_id": stats.user_id,
                "total_connections": stats.total_connections,
                "total_connection_time_hours": round(stats.total_connection_time_seconds / 3600, 2),
            }
            for stats in top_users
        ]

    def _get_server_health_summary(self) -> Dict:
        """Get server health summary"""
        from models.vpn_server import VPNServer

        servers = self.db.query(VPNServer).all()

        return {
            "total": len(servers),
            "healthy": sum(1 for s in servers if s.health_status == "healthy"),
            "degraded": sum(1 for s in servers if s.health_status == "degraded"),
            "unhealthy": sum(1 for s in servers if s.health_status == "unhealthy"),
            "offline": sum(1 for s in servers if s.status == "offline"),
            "average_capacity": round(sum(s.capacity_percentage for s in servers) / len(servers), 2) if servers else 0,
        }

    def _get_revenue_metrics(self) -> Dict:
        """Get revenue metrics"""
        active_subs = self.db.query(Subscription).filter(
            Subscription.status == "active"
        ).all()

        mrr = sum(
            sub.amount if sub.billing_cycle == "monthly" else sub.amount / 12
            for sub in active_subs
        )

        arr = mrr * 12  # Annual Recurring Revenue

        return {
            "mrr": round(mrr, 2),
            "arr": round(arr, 2),
            "active_subscriptions": len(active_subs),
            "subscription_breakdown": self._get_subscription_breakdown(),
        }

    def _get_subscription_breakdown(self) -> Dict:
        """Get subscription tier breakdown"""
        subs = self.db.query(
            Subscription.plan_id,
            func.count(Subscription.id).label("count")
        ).filter(
            Subscription.status == "active"
        ).group_by(Subscription.plan_id).all()

        return {plan_id: count for plan_id, count in subs}


def get_analytics_service(db: Session) -> AnalyticsService:
    """Get analytics service instance"""
    return AnalyticsService(db)
