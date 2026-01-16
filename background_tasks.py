import asyncio
import logging
from typing import Optional

from services.vpn_health_monitor import get_health_monitor

logger = logging.getLogger(__name__)


class BackgroundTaskManager:
    """Manager for background tasks"""

    def __init__(self):
        self.health_monitor_task: Optional[asyncio.Task] = None
        self.policy_worker_task: Optional[asyncio.Task] = None

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
