import logging
from datetime import datetime
from typing import List, Dict, Optional

from sqlalchemy.orm import Session

from models.vpn_server import VPNServer
from models.vpn_connection import VPNConnection
from models.user import User

logger = logging.getLogger(__name__)


class VPNServerService:
    """Service for managing VPN server fleet and health monitoring"""

    @staticmethod
    def get_active_servers(
        db: Session,
        user_tier: str = "free",
        *,
        protocol: Optional[str] = None,
    ) -> List[VPNServer]:
        """
        Get available servers for user tier

        Args:
            db: Database session
            user_tier: User tier ('free' or 'premium')
            protocol: Optional protocol filter (wireguard/openvpn/ikev2)

        Returns:
            List of available VPN servers
        """
        allowed_statuses = ["active"]

        query = db.query(VPNServer).filter(
            VPNServer.status.in_(allowed_statuses),
            VPNServer.health_status.in_(["healthy", "degraded", "unknown"]),
        )

        if protocol:
            normalized = protocol.strip().lower()
            if normalized in {"wireguard", "wg", "wire_guard"}:
                query = query.filter(VPNServer.supports_wireguard.is_(True))
            elif normalized == "openvpn":
                query = query.filter(VPNServer.supports_openvpn.is_(True))
            elif normalized in {"ikev2", "ikev2/ipsec", "ipsec"}:
                query = query.filter(VPNServer.supports_ikev2.is_(True))

        # Free users can only access unrestricted servers
        if user_tier == "free":
            query = query.filter(
                (VPNServer.tier_restriction.is_(None)) | (VPNServer.tier_restriction == "")
            )

        return query.all()

    @staticmethod
    def get_server_by_id(db: Session, server_id: str) -> Optional[VPNServer]:
        """Get server by server_id"""
        return db.query(VPNServer).filter(VPNServer.server_id == server_id).first()

    @staticmethod
    def update_server_metrics(db: Session, server_id: str, metrics: Dict):
        """
        Update real-time server metrics

        Args:
            db: Database session
            server_id: Server identifier
            metrics: Dictionary of metrics to update
        """
        server = VPNServerService.get_server_by_id(db, server_id)

        if not server:
            logger.warning(f"Attempted to update metrics for non-existent server: {server_id}")
            return

        # Update metrics
        if "current_connections" in metrics:
            server.current_connections = metrics["current_connections"]
        if "cpu_load" in metrics:
            server.cpu_load = metrics["cpu_load"]
        if "memory_usage" in metrics:
            server.memory_usage = metrics["memory_usage"]
        if "latency_ms" in metrics:
            server.latency_ms = metrics["latency_ms"]
            # Persist rolling RTT history for recommendation scoring.
            try:
                from services.rtt_history import record_rtt_sample

                record_rtt_sample(
                    db,
                    vpn_server_id=server.id,
                    rtt_ms=float(metrics["latency_ms"]),
                    source="health_monitor_ping",
                )
            except Exception:
                # Never block health updates on metrics persistence.
                pass
        if "packet_loss" in metrics:
            server.packet_loss = metrics["packet_loss"]
        if "jitter_ms" in metrics:
            server.jitter_ms = metrics["jitter_ms"]
        if "bandwidth_in_mbps" in metrics:
            server.bandwidth_in_mbps = metrics["bandwidth_in_mbps"]
        if "bandwidth_out_mbps" in metrics:
            server.bandwidth_out_mbps = metrics["bandwidth_out_mbps"]

        # Update health status based on metrics
        server.health_status = VPNServerService._calculate_health_status(metrics)
        server.last_health_check = datetime.utcnow()
        server.updated_at = datetime.utcnow()

        db.commit()
        logger.debug(f"Updated metrics for server {server_id}: health={server.health_status}")

    @staticmethod
    def _calculate_health_status(metrics: Dict) -> str:
        """
        Determine server health from metrics

        Args:
            metrics: Dictionary of server metrics

        Returns:
            Health status string ('healthy', 'degraded', 'unstable')
        """
        # Check for critical issues
        if metrics.get("cpu_load", 0) > 0.95:
            return "unstable"
        if metrics.get("packet_loss", 0) > 0.10:  # >10% packet loss
            return "unstable"
        if metrics.get("latency_ms", 0) > 1000:  # >1 second latency
            return "unstable"

        # Check for degraded performance
        if metrics.get("cpu_load", 0) > 0.80:
            return "degraded"
        if metrics.get("packet_loss", 0) > 0.05:  # >5% packet loss
            return "degraded"
        if metrics.get("latency_ms", 0) > 500:  # >500ms latency
            return "degraded"
        if metrics.get("current_connections", 0) > metrics.get("max_connections", 1000) * 0.9:
            return "degraded"

        return "healthy"

    @staticmethod
    def allocate_server_for_user(
        db: Session,
        user: User,
        preferred_location: Optional[str] = None,
    ) -> Optional[VPNServer]:
        """
        Use optimizer to select best server for user.

        IMPORTANT: The optimizer is a *suggestion engine* only. Selection must
        never hard-block VPN connectivity. If the optimizer returns an invalid
        or unknown server, we fall back deterministically to an available server.

        Args:
            db: Database session
            user: User object
            preferred_location: User's preferred location (optional)

        Returns:
            Selected VPN server or None if no servers available
        """
        try:
            from services.vpn_optimizer import get_vpn_optimizer

            optimizer = get_vpn_optimizer()

            # Determine user tier
            is_premium = user.subscription_status == "active"
            user_tier = "premium" if is_premium else "free"

            # Get available servers for this tier
            available_servers = VPNServerService.get_active_servers(db, user_tier)

            if not available_servers:
                logger.warning(f"No available servers for user {user.id} (tier: {user_tier})")
                return None

            # RTT-first fallback so optimizer failures never block connections.
            from services.latency_optimizer import get_latency_optimizer

            latency_optimizer = get_latency_optimizer()
            ranked = latency_optimizer.rank_servers(
                available_servers,
                user_region_hint=preferred_location,
            )
            ranked_map = {server.server_id: server for server in available_servers}
            fallback_server = ranked_map.get(ranked[0].server_id, available_servers[0]) if ranked else available_servers[0]
            allowed_server_ids = {s.server_id for s in available_servers}

            # Use optimizer to select best server
            result = optimizer.select_optimal_server(
                user_id=user.id,
                user_location=preferred_location,
                is_premium=is_premium,
            )

            # Get the selected server from database
            suggested_id = result.get("server_id") if isinstance(result, dict) else None
            if not suggested_id or suggested_id not in allowed_server_ids:
                logger.warning(
                    "Optimizer suggested invalid server_id=%s for user %s; falling back to %s",
                    suggested_id,
                    user.id,
                    fallback_server.server_id,
                )
                return fallback_server

            server = VPNServerService.get_server_by_id(db, suggested_id)

            if server:
                logger.info(
                    f"Allocated server {server.server_id} ({server.location}) to user {user.id}"
                )
            else:
                logger.warning(
                    f"Optimizer selected non-existent server {suggested_id} for user {user.id}"
                )
                return fallback_server

            return server

        except Exception as e:
            logger.error(f"Failed to allocate server for user {user.id}: {e}")
            # Fallback: return first available server
            available_servers = VPNServerService.get_active_servers(
                db, "premium" if user.subscription_status == "active" else "free"
            )
            return available_servers[0] if available_servers else None

    @staticmethod
    def get_server_stats(db: Session) -> Dict:
        """Get overall server fleet statistics"""
        total_servers = db.query(VPNServer).count()
        active_servers = (
            db.query(VPNServer)
            .filter(VPNServer.status == "active", VPNServer.health_status == "healthy")
            .count()
        )
        total_connections = (
            db.query(VPNConnection).filter(VPNConnection.disconnected_at.is_(None)).count()
        )

        avg_cpu = db.query(db.func.avg(VPNServer.cpu_load)).filter(
            VPNServer.status == "active"
        ).scalar() or 0.0

        avg_latency = db.query(db.func.avg(VPNServer.latency_ms)).filter(
            VPNServer.status == "active"
        ).scalar() or 0.0

        return {
            "total_servers": total_servers,
            "active_servers": active_servers,
            "total_connections": total_connections,
            "avg_cpu_load": round(avg_cpu, 2),
            "avg_latency_ms": round(avg_latency, 1),
        }

    @staticmethod
    def record_connection(
        db: Session,
        user_id: int,
        server: VPNServer,
        client_ip: str,
        public_ip: Optional[str] = None,
    ) -> VPNConnection:
        """
        Record a new VPN connection

        Args:
            db: Database session
            user_id: User ID
            server: VPN server object
            client_ip: Allocated VPN IP
            public_ip: User's public IP (optional)

        Returns:
            VPNConnection object
        """
        connection = VPNConnection(
            user_id=user_id,
            server_id=server.id,
            client_ip=client_ip,
            public_ip=public_ip,
            connected_at=datetime.utcnow(),
        )

        db.add(connection)

        # Increment server connection count
        server.current_connections += 1
        server.updated_at = datetime.utcnow()

        db.commit()
        db.refresh(connection)

        logger.info(
            f"Recorded connection: user={user_id}, server={server.server_id}, ip={client_ip}"
        )

        return connection

    @staticmethod
    def disconnect_connection(db: Session, connection_id: int):
        """Mark a connection as disconnected"""
        connection = db.query(VPNConnection).filter(VPNConnection.id == connection_id).first()

        if connection and connection.is_active:
            connection.disconnected_at = datetime.utcnow()

            # Decrement server connection count
            if connection.server:
                connection.server.current_connections = max(
                    0, connection.server.current_connections - 1
                )
                connection.server.updated_at = datetime.utcnow()

            db.commit()
            logger.info(f"Disconnected connection {connection_id}")
