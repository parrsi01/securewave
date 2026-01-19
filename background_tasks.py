import asyncio
import logging
from typing import Optional

from services.vpn_health_monitor import get_health_monitor
from database.session import SessionLocal
from services.vpn_peer_manager import get_peer_manager

logger = logging.getLogger(__name__)


class BackgroundTaskManager:
    """Manager for background tasks"""

    def __init__(self):
        self.health_monitor_task: Optional[asyncio.Task] = None
        self.policy_worker_task: Optional[asyncio.Task] = None
        self.key_rotation_task: Optional[asyncio.Task] = None

    async def _key_rotation_loop(self, interval_seconds: int = 21600):
        """Rotate due WireGuard keys on a fixed interval."""
        while True:
            db = None
            try:
                db = SessionLocal()
                peer_manager = get_peer_manager(db)
                rotated = peer_manager.rotate_all_due_keys()
                logger.info(f"Key rotation completed: {rotated} peers rotated")
            except Exception as e:
                logger.warning(f"Key rotation failed: {e}")
            finally:
                if db:
                    db.close()
            await asyncio.sleep(interval_seconds)

    async def start_all(self):
        """Start all background tasks"""
        logger.info("Starting background tasks...")

        # Start VPN health monitor
        monitor = get_health_monitor()
        self.health_monitor_task = asyncio.create_task(monitor.start())
        logger.info("VPN Health Monitor task created")

        # Start Policy Engine Worker (Day 14)
        try:
            from services.policy_engine_worker import get_policy_worker
            policy_worker = get_policy_worker()
            self.policy_worker_task = asyncio.create_task(policy_worker.start())
            logger.info("Policy Engine Worker task created")
        except ImportError as e:
            logger.warning(f"Policy Engine Worker not available: {e}")

        # Start key rotation loop (Phase 5)
        self.key_rotation_task = asyncio.create_task(self._key_rotation_loop())
        logger.info("Key rotation task created")

    async def stop_all(self):
        """Stop all background tasks"""
        logger.info("Stopping background tasks...")

        # Stop policy worker
        if self.policy_worker_task:
            try:
                from services.policy_engine_worker import get_policy_worker
                policy_worker = get_policy_worker()
                await policy_worker.stop()

                await asyncio.wait_for(self.policy_worker_task, timeout=5.0)
            except asyncio.TimeoutError:
                logger.warning("Policy worker task did not stop gracefully, cancelling...")
                self.policy_worker_task.cancel()
                try:
                    await self.policy_worker_task
                except asyncio.CancelledError:
                    logger.info("Policy worker task cancelled")
            except Exception as e:
                logger.warning(f"Error stopping policy worker: {e}")

        # Stop key rotation loop
        if self.key_rotation_task:
            self.key_rotation_task.cancel()
            try:
                await self.key_rotation_task
            except asyncio.CancelledError:
                logger.info("Key rotation task cancelled")

        # Stop health monitor
        if self.health_monitor_task:
            monitor = get_health_monitor()
            await monitor.stop()

            try:
                await asyncio.wait_for(self.health_monitor_task, timeout=5.0)
            except asyncio.TimeoutError:
                logger.warning("Health monitor task did not stop gracefully, cancelling...")
                self.health_monitor_task.cancel()
                try:
                    await self.health_monitor_task
                except asyncio.CancelledError:
                    logger.info("Health monitor task cancelled")

        logger.info("All background tasks stopped")


# Singleton instance
_task_manager = None


def get_task_manager() -> BackgroundTaskManager:
    """Get singleton task manager instance"""
    global _task_manager
    if _task_manager is None:
        _task_manager = BackgroundTaskManager()
    return _task_manager
