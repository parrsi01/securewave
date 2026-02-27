import asyncio
import logging
import os
from typing import Optional

from services.vpn_health_monitor import get_health_monitor
from database.session import SessionLocal
from services.vpn_peer_manager import get_peer_manager

logger = logging.getLogger(__name__)


class BackgroundTaskManager:
    """Manager for background tasks"""

    def __init__(self):
        self.health_monitor_task: Optional[asyncio.Task] = None
        self.watchdog_task: Optional[asyncio.Task] = None
        self.region_watchdog_task: Optional[asyncio.Task] = None
        self.key_rotation_task: Optional[asyncio.Task] = None
        self.token_purge_task: Optional[asyncio.Task] = None

    async def _region_health_watchdog_loop(self) -> None:
        interval_raw = os.getenv("SECUREWAVE_REGION_WATCHDOG_INTERVAL_SECONDS", "15").strip()
        try:
            interval = int(interval_raw)
        except ValueError:
            interval = 15
        interval = max(5, min(interval, 300))

        while True:
            db = None
            try:
                from routes.vpn import run_region_health_watchdog_cycle

                db = SessionLocal()
                summary = run_region_health_watchdog_cycle(db)
                logger.info("Region health watchdog cycle: %s", summary)
            except Exception as e:
                logger.warning("Region health watchdog cycle failed: %s", e)
            finally:
                if db:
                    db.close()
            await asyncio.sleep(interval)

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

    async def _jwt_blacklist_purge_loop(self, interval_seconds: int = 3600):
        """Delete expired JWT blacklist entries on a fixed interval."""
        while True:
            db = None
            try:
                db = SessionLocal()
                from services.jwt_service import purge_expired_blacklist_tokens

                deleted = purge_expired_blacklist_tokens(db)
                logger.info(f"JWT blacklist purge completed: {deleted} expired entries removed")
            except Exception as e:
                logger.warning(f"JWT blacklist purge failed: {e}")
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

        # Start tunnel watchdog (self-healing layer)
        try:
            from services.tunnel_watchdog import get_tunnel_watchdog

            watchdog = get_tunnel_watchdog()
            self.watchdog_task = asyncio.create_task(watchdog.start())
            logger.info("Tunnel Watchdog task created")
        except Exception as e:
            logger.warning(f"Tunnel Watchdog not available: {e}")

        # Start control-plane region health watchdog.
        self.region_watchdog_task = asyncio.create_task(self._region_health_watchdog_loop())
        logger.info("Region health watchdog task created")

        # Start key rotation loop (Phase 5)
        self.key_rotation_task = asyncio.create_task(self._key_rotation_loop())
        logger.info("Key rotation task created")

        # Start expired JWT blacklist purge
        self.token_purge_task = asyncio.create_task(self._jwt_blacklist_purge_loop())
        logger.info("JWT blacklist purge task created")

    async def stop_all(self):
        """Stop all background tasks"""
        logger.info("Stopping background tasks...")

        # Stop key rotation loop
        if self.key_rotation_task:
            self.key_rotation_task.cancel()
            try:
                await self.key_rotation_task
            except asyncio.CancelledError:
                logger.info("Key rotation task cancelled")

        # Stop JWT blacklist purge loop
        if self.token_purge_task:
            self.token_purge_task.cancel()
            try:
                await self.token_purge_task
            except asyncio.CancelledError:
                logger.info("JWT blacklist purge task cancelled")

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

        # Stop watchdog
        if self.watchdog_task:
            try:
                from services.tunnel_watchdog import get_tunnel_watchdog

                watchdog = get_tunnel_watchdog()
                await watchdog.stop()
                await asyncio.wait_for(self.watchdog_task, timeout=5.0)
            except asyncio.TimeoutError:
                logger.warning("Watchdog task did not stop gracefully, cancelling...")
                self.watchdog_task.cancel()
                try:
                    await self.watchdog_task
                except asyncio.CancelledError:
                    logger.info("Watchdog task cancelled")
            except Exception as e:
                logger.warning(f"Error stopping watchdog: {e}")

        # Stop region watchdog
        if self.region_watchdog_task:
            self.region_watchdog_task.cancel()
            try:
                await self.region_watchdog_task
            except asyncio.CancelledError:
                logger.info("Region health watchdog task cancelled")

        logger.info("All background tasks stopped")


# Singleton instance
_task_manager = None


def get_task_manager() -> BackgroundTaskManager:
    """Get singleton task manager instance"""
    global _task_manager
    if _task_manager is None:
        _task_manager = BackgroundTaskManager()
    return _task_manager
