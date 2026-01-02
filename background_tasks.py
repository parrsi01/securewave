import asyncio
import logging
from typing import Optional

from services.vpn_health_monitor import get_health_monitor

logger = logging.getLogger(__name__)


class BackgroundTaskManager:
    """Manager for background tasks"""

    def __init__(self):
        self.health_monitor_task: Optional[asyncio.Task] = None

    async def start_all(self):
        """Start all background tasks"""
        logger.info("Starting background tasks...")

        # Start VPN health monitor
        monitor = get_health_monitor()
        self.health_monitor_task = asyncio.create_task(monitor.start())
        logger.info("VPN Health Monitor task created")

    async def stop_all(self):
        """Stop all background tasks"""
        logger.info("Stopping background tasks...")

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
