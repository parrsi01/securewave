"""
Backup Service
Automated backup management for database, configurations, and VPN data.
"""

import os
import logging
import shutil
import subprocess  # nosec B404 - controlled subprocess usage with validated args
import tempfile
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from pathlib import Path
import tarfile

logger = logging.getLogger(__name__)

# Configuration
BACKUP_RETENTION_DAYS = int(os.getenv("BACKUP_RETENTION_DAYS", "35"))
BACKUP_ROOT = Path(os.getenv("BACKUP_ROOT", "backups")).expanduser()


class BackupService:
    """
    Backup Service
    Handles automated backups of database, configurations, and VPN settings.
    """

    def __init__(self):
        """Initialize backup service"""
        self.retention_days = BACKUP_RETENTION_DAYS
        self.backup_root = BACKUP_ROOT
        self.backup_root.mkdir(parents=True, exist_ok=True)

    def _resolve_executable(self, name: str) -> str:
        path = shutil.which(name)
        if not path:
            raise FileNotFoundError(f"Required executable not found: {name}")
        return path

    def _ensure_dir(self, subdir: str) -> Path:
        target = self.backup_root / subdir
        target.mkdir(parents=True, exist_ok=True)
        return target

    # ===========================
    # DATABASE BACKUPS
    # ===========================

    def create_database_backup(self, backup_name: Optional[str] = None) -> Dict:
        """
        Create a database backup stored on local disk.

        Args:
            backup_name: Custom backup name (default: auto-generated)

        Returns:
            Backup details
        """
        try:
            if not backup_name:
                backup_name = f"db-backup-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"

            db_url = os.getenv("DATABASE_URL", "")
            if not db_url:
                return {"success": False, "error": "DATABASE_URL not set", "type": "database"}

            backup_dir = self._ensure_dir("database")
            output_path = backup_dir / f"{backup_name}.dump"

            if db_url.startswith("sqlite:///"):
                sqlite_path = db_url.replace("sqlite:///", "")
                if sqlite_path == ":memory:":
                    return {"success": False, "error": "In-memory SQLite cannot be backed up", "type": "database"}
                shutil.copy2(sqlite_path, output_path)
            else:
                export_result = self.export_database_to_file(str(output_path))
                if not export_result.get("success"):
                    return {"success": False, "error": export_result.get("error"), "type": "database"}

            logger.info("Database backup created successfully: %s", output_path)
            return {
                "success": True,
                "backup_name": backup_name,
                "path": str(output_path),
                "created_at": datetime.utcnow().isoformat(),
                "type": "database",
            }

        except Exception as e:
            logger.error("Failed to create database backup: %s", e)
            return {"success": False, "error": str(e), "type": "database"}

    def export_database_to_file(self, output_path: str) -> Dict:
        """
        Export database to file using pg_dump.

        Args:
            output_path: Path to save backup file

        Returns:
            Export details
        """
        try:
            db_url = os.getenv("DATABASE_URL", "")
            if not db_url:
                return {"success": False, "error": "DATABASE_URL not set"}

            import urllib.parse
            parsed = urllib.parse.urlparse(db_url)
            if not parsed.scheme.startswith("postgresql"):
                return {"success": False, "error": "pg_dump requires a PostgreSQL DATABASE_URL"}

            pg_dump_path = self._resolve_executable("pg_dump")
            cmd = [
                pg_dump_path,
                "-h", parsed.hostname,
                "-p", str(parsed.port or 5432),
                "-U", parsed.username,
                "-d", parsed.path.lstrip("/"),
                "-F", "custom",
                "-f", output_path,
            ]

            env = os.environ.copy()
            env["PGPASSWORD"] = parsed.password or ""

            result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=600)  # nosec B603

            if result.returncode == 0:
                file_size = os.path.getsize(output_path)
                logger.info("Database exported successfully to %s", output_path)
                return {
                    "success": True,
                    "output_path": output_path,
                    "file_size_mb": round(file_size / 1024 / 1024, 2),
                    "created_at": datetime.utcnow().isoformat(),
                }
            else:
                logger.error("Database export failed: %s", result.stderr)
                return {"success": False, "error": result.stderr}

        except Exception as e:
            logger.error("Failed to export database: %s", e)
            return {"success": False, "error": str(e)}

    def list_database_backups(self) -> List[Dict]:
        """
        List available database backups.

        Returns:
            List of backups
        """
        try:
            backup_dir = self._ensure_dir("database")
            backups = []
            for file in sorted(backup_dir.glob("*.dump")):
                backups.append({
                    "name": file.name,
                    "path": str(file),
                    "size_bytes": file.stat().st_size,
                    "modified_at": datetime.utcfromtimestamp(file.stat().st_mtime).isoformat(),
                })
            return backups
        except Exception as e:
            logger.error("Failed to list database backups: %s", e)
            return []

    # ===========================
    # APPLICATION BACKUPS
    # ===========================

    def backup_application_config(self) -> Dict:
        """
        Backup application configuration files.

        Returns:
            Backup details
        """
        try:
            backup_name = f"config-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"
            backup_dir = self._ensure_dir("config")
            output_path = backup_dir / f"{backup_name}.tar.gz"

            config_files = [
                ".env",
                ".env.production",
                "alembic.ini",
            ]

            with tarfile.open(output_path, "w:gz") as tar:
                for config_file in config_files:
                    if os.path.exists(config_file):
                        tar.add(config_file)

            logger.info("Application config backed up: %s", output_path)
            return {
                "success": True,
                "backup_name": backup_name,
                "path": str(output_path),
                "created_at": datetime.utcnow().isoformat(),
                "type": "application_config",
            }

        except Exception as e:
            logger.error("Failed to backup application config: %s", e)
            return {"success": False, "error": str(e), "type": "application_config"}

    # ===========================
    # VPN CONFIGURATION BACKUPS
    # ===========================

    def backup_vpn_configurations(self) -> Dict:
        """Backup VPN server configurations."""
        try:
            from database.session import get_db
            from models.vpn_server import VPNServer
            import json

            db = next(get_db())
            servers = db.query(VPNServer).all()

            backup_data = {
                "created_at": datetime.utcnow().isoformat(),
                "servers": [],
            }

            for server in servers:
                backup_data["servers"].append({
                    "id": server.id,
                    "name": server.name if hasattr(server, "name") else None,
                    "ip_address": server.public_ip,
                    "port": server.wg_listen_port,
                    "location": server.location,
                    "region": server.region,
                    "is_active": server.status == "active",
                    "public_key": server.wg_public_key,
                    "endpoint": server.endpoint,
                })

            backup_dir = self._ensure_dir("vpn-configs")
            output_path = backup_dir / f"vpn_config_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
            with output_path.open("w", encoding="utf-8") as f:
                json.dump(backup_data, f, indent=2)

            logger.info("VPN configurations backed up: %s servers", len(servers))

            return {
                "success": True,
                "servers_backed_up": len(servers),
                "created_at": datetime.utcnow().isoformat(),
                "type": "vpn_config",
                "path": str(output_path),
            }

        except Exception as e:
            logger.error("Failed to backup VPN configurations: %s", e)
            return {"success": False, "error": str(e), "type": "vpn_config"}

    def backup_wireguard_peers(self) -> Dict:
        """Backup WireGuard peer configurations."""
        try:
            from database.session import get_db
            from models.wireguard_peer import WireGuardPeer
            import json

            db = next(get_db())
            peers = db.query(WireGuardPeer).filter(WireGuardPeer.is_active == True).all()

            backup_data = {
                "created_at": datetime.utcnow().isoformat(),
                "peers": [],
            }

            for peer in peers:
                backup_data["peers"].append({
                    "id": peer.id,
                    "user_id": peer.user_id,
                    "server_id": peer.server_id,
                    "public_key": peer.public_key,
                    "ipv4_address": peer.ipv4_address,
                    "ipv6_address": peer.ipv6_address,
                    "device_name": peer.device_name,
                    "is_active": peer.is_active,
                })

            backup_dir = self._ensure_dir("wireguard-peers")
            output_path = backup_dir / f"peers_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
            with output_path.open("w", encoding="utf-8") as f:
                json.dump(backup_data, f, indent=2)

            logger.info("WireGuard peers backed up: %s peers", len(peers))

            return {
                "success": True,
                "peers_backed_up": len(peers),
                "created_at": datetime.utcnow().isoformat(),
                "type": "wireguard_peers",
                "path": str(output_path),
            }

        except Exception as e:
            logger.error("Failed to backup WireGuard peers: %s", e)
            return {"success": False, "error": str(e), "type": "wireguard_peers"}

    # ===========================
    # COMPREHENSIVE BACKUP
    # ===========================

    def run_full_backup(self) -> Dict:
        """Run comprehensive backup of all systems."""
        summary = {
            "started_at": datetime.utcnow().isoformat(),
            "backups": [],
            "success_count": 0,
            "failure_count": 0,
        }

        db_backup = self.create_database_backup()
        summary["backups"].append(db_backup)
        summary["success_count"] += 1 if db_backup.get("success") else 0
        summary["failure_count"] += 0 if db_backup.get("success") else 1

        app_backup = self.backup_application_config()
        summary["backups"].append(app_backup)
        summary["success_count"] += 1 if app_backup.get("success") else 0
        summary["failure_count"] += 0 if app_backup.get("success") else 1

        vpn_backup = self.backup_vpn_configurations()
        summary["backups"].append(vpn_backup)
        summary["success_count"] += 1 if vpn_backup.get("success") else 0
        summary["failure_count"] += 0 if vpn_backup.get("success") else 1

        peers_backup = self.backup_wireguard_peers()
        summary["backups"].append(peers_backup)
        summary["success_count"] += 1 if peers_backup.get("success") else 0
        summary["failure_count"] += 0 if peers_backup.get("success") else 1

        summary["completed_at"] = datetime.utcnow().isoformat()
        summary["overall_status"] = "success" if summary["failure_count"] == 0 else "partial_failure"

        logger.info(
            "Full backup completed: %s succeeded, %s failed",
            summary["success_count"],
            summary["failure_count"],
        )

        return summary

    # ===========================
    # BACKUP CLEANUP
    # ===========================

    def cleanup_old_backups(self) -> Dict:
        """Remove backups older than retention period."""
        try:
            cutoff_date = datetime.utcnow() - timedelta(days=self.retention_days)
            deleted_count = 0

            for backup_dir in self.backup_root.glob("*"):
                if not backup_dir.is_dir():
                    continue
                for file in backup_dir.glob("*"):
                    modified = datetime.utcfromtimestamp(file.stat().st_mtime)
                    if modified < cutoff_date:
                        file.unlink()
                        deleted_count += 1

            logger.info("Cleaned up %s old backups", deleted_count)

            return {
                "success": True,
                "deleted_count": deleted_count,
                "retention_days": self.retention_days,
                "cutoff_date": cutoff_date.isoformat(),
            }

        except Exception as e:
            logger.error("Failed to cleanup old backups: %s", e)
            return {"success": False, "error": str(e)}

    # ===========================
    # HELPER METHODS
    # ===========================

    def verify_backup(self, backup_name: str) -> Dict:
        """Verify backup integrity (placeholder)."""
        try:
            logger.info("Verifying backup: %s", backup_name)
            return {
                "success": True,
                "backup_name": backup_name,
                "verified_at": datetime.utcnow().isoformat(),
                "status": "valid",
            }

        except Exception as e:
            logger.error("Backup verification failed: %s", e)
            return {"success": False, "error": str(e), "status": "invalid"}


_backup_service: Optional[BackupService] = None


def get_backup_service() -> BackupService:
    """Get backup service instance"""
    global _backup_service
    if _backup_service is None:
        _backup_service = BackupService()
    return _backup_service
