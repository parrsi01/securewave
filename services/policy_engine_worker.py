"""
SecureWave Async Policy Engine Worker (Day 14)

Background worker that periodically evaluates all active connections
and triggers policy decisions (reroute, throttle, rotate, alert).

Features:
- Runs as async background task
- Evaluates connections every N seconds
- Integrates with MARL policy engine
- Updates optimizer with decisions
- Logs all policy actions
"""

import asyncio
import logging
from datetime import datetime
from typing import Dict, List, Optional

from sqlalchemy.orm import Session

from database.session import SessionLocal
from models.vpn_demo_session import VPNDemoSession
from models.audit_log import AuditLog

logger = logging.getLogger(__name__)


class PolicyEngineWorker:
    """
    Async background worker for policy evaluation.
    Implements periodic evaluation loop (Day 14).
    """

    def __init__(self, evaluation_interval: int = 30):
        """
        Initialize policy engine worker.

        Args:
            evaluation_interval: Seconds between policy evaluations
        """
        self.evaluation_interval = evaluation_interval
        self.is_running = False
        self.evaluation_count = 0
        self.last_evaluation: Optional[datetime] = None
        self.action_history: List[Dict] = []

    async def start(self) -> None:
        """Start the policy evaluation loop"""
        self.is_running = True
        logger.info(f"Policy Engine Worker started (interval: {self.evaluation_interval}s)")

        while self.is_running:
            try:
                await self.evaluate_all_connections()
                await asyncio.sleep(self.evaluation_interval)
            except Exception as e:
                logger.error(f"Policy evaluation error: {e}", exc_info=True)
                await asyncio.sleep(self.evaluation_interval * 2)  # Back off on error

    async def stop(self) -> None:
        """Stop the policy evaluation loop"""
        self.is_running = False
        logger.info("Policy Engine Worker stopped")

    async def evaluate_all_connections(self) -> None:
        """
        Evaluate all active VPN connections and make policy decisions.
        """
        db: Optional[Session] = None
        try:
            db = SessionLocal()

            # Get all active demo sessions
            active_sessions = db.query(VPNDemoSession).filter(
                VPNDemoSession.status == "CONNECTED"
            ).all()

            logger.debug(f"Evaluating {len(active_sessions)} active connections")

            for session in active_sessions:
                try:
                    await self._evaluate_session(db, session)
                except Exception as e:
                    logger.warning(f"Failed to evaluate session {session.id}: {e}")

            self.evaluation_count += 1
            self.last_evaluation = datetime.utcnow()

            db.commit()

        except Exception as e:
            logger.error(f"Failed to evaluate connections: {e}", exc_info=True)
            if db:
                db.rollback()
        finally:
            if db:
                db.close()

    async def _evaluate_session(self, db: Session, session: VPNDemoSession) -> None:
        """
        Evaluate single session and apply policy decision.
        """
        try:
            from services.marl_policy import evaluate_connection, get_policy_engine, PolicyAction
            from services.vpn_optimizer import get_vpn_optimizer
        except ImportError as e:
            logger.warning(f"Policy modules not available: {e}")
            return

        # Get optimizer for server metrics
        optimizer = get_vpn_optimizer()
        policy_engine = get_policy_engine()

        # Get current server metrics (simulated for demo)
        server_id = session.assigned_node or "demo-server"
        server_metrics = optimizer.servers.get(server_id, None)

        # Default metrics if server not found
        latency_ms = 50.0
        packet_loss = 0.01
        jitter_ms = 3.0
        server_load = 0.3
        bandwidth_mbps = 100.0

        if server_metrics:
            latency_ms = server_metrics.latency_ms
            packet_loss = server_metrics.packet_loss
            jitter_ms = server_metrics.jitter_ms
            server_load = server_metrics.cpu_load
            bandwidth_mbps = server_metrics.bandwidth_mbps

        # Evaluate connection
        result = evaluate_connection(
            user_id=session.user_id,
            server_id=server_id,
            latency_ms=latency_ms,
            packet_loss=packet_loss,
            jitter_ms=jitter_ms,
            bandwidth_mbps=bandwidth_mbps,
            server_load=server_load,
            user_priority=0,  # Could look up from subscription
            reconnect_count=0,  # Could track in session
        )

        action = result["action"]

        # Log action if not NO_ACTION
        if action != "no_action":
            await self._apply_action(db, session, result)

    async def _apply_action(
        self,
        db: Session,
        session: VPNDemoSession,
        decision: Dict
    ) -> None:
        """
        Apply policy action to session.
        """
        action = decision["action"]
        reason = decision["reason"]
        target_server = decision.get("target_server")

        logger.info(
            f"Policy action for user {session.user_id}: "
            f"{action} - {reason}"
        )

        # Record action in history
        action_record = {
            "timestamp": datetime.utcnow().isoformat(),
            "user_id": session.user_id,
            "session_id": session.id,
            "action": action,
            "reason": reason,
            "target_server": target_server,
            "qos": decision.get("qos", {}),
            "risk": decision.get("risk", {}),
        }
        self.action_history.append(action_record)

        # Keep history bounded
        if len(self.action_history) > 1000:
            self.action_history = self.action_history[-1000:]

        # Apply action based on type
        if action == "reroute":
            # In production, this would trigger actual rerouting
            if target_server:
                session.assigned_node = target_server
                logger.info(f"Rerouted user {session.user_id} to {target_server}")

        elif action == "throttle":
            # In production, this would adjust bandwidth allocation
            logger.info(f"Throttle applied to user {session.user_id}")

        elif action == "rotate_server":
            if target_server:
                session.assigned_node = target_server
                logger.info(f"Rotated user {session.user_id} to {target_server}")

        elif action == "alert":
            # Create audit log entry for alert
            self._create_alert(db, session, decision)

        db.add(session)

    def _create_alert(self, db: Session, session: VPNDemoSession, decision: Dict) -> None:
        """Create audit log entry for policy alert"""
        try:
            audit_entry = AuditLog(
                event_type="POLICY_ALERT",
                event_category="security",
                action="alert",
                user_id=session.user_id,
                actor_type="system",
                resource_type="vpn_session",
                resource_id=str(session.id),
                description=f"Policy alert: {decision['reason']}",
                details={
                    "qos": decision.get("qos", {}),
                    "risk": decision.get("risk", {}),
                    "safety_override": decision.get("safety_override", False),
                },
                severity="warning" if decision.get("safety_override") else "info",
                is_suspicious=decision.get("risk", {}).get("level") in ["high", "critical"],
                is_compliance_relevant=False,
                success=True,
            )
            db.add(audit_entry)
        except Exception as e:
            logger.warning(f"Failed to create audit log: {e}")

    def get_stats(self) -> Dict:
        """Get worker statistics"""
        return {
            "is_running": self.is_running,
            "evaluation_interval": self.evaluation_interval,
            "evaluation_count": self.evaluation_count,
            "last_evaluation": self.last_evaluation.isoformat() if self.last_evaluation else None,
            "action_history_size": len(self.action_history),
            "recent_actions": self.action_history[-10:] if self.action_history else [],
        }


# Singleton instance
_policy_worker: Optional[PolicyEngineWorker] = None


def get_policy_worker() -> PolicyEngineWorker:
    """Get or create singleton policy worker"""
    global _policy_worker
    if _policy_worker is None:
        _policy_worker = PolicyEngineWorker()
    return _policy_worker


async def start_policy_worker() -> None:
    """Start the policy worker as background task"""
    worker = get_policy_worker()
    await worker.start()


async def stop_policy_worker() -> None:
    """Stop the policy worker"""
    worker = get_policy_worker()
    await worker.stop()
