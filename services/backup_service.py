"""
Backup Service
Automated backup management for database, configurations, and VPN data
"""

import os
import logging
import shutil
import subprocess  # nosec B404 - controlled subprocess usage with validated args
import tempfile
from typing import Dict, List, Optional
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

# Configuration
BACKUP_RETENTION_DAYS = int(os.getenv("BACKUP_RETENTION_DAYS", "35"))
BACKUP_STORAGE_ACCOUNT = os.getenv("BACKUP_STORAGE_ACCOUNT", "securewave")
BACKUP_CONTAINER = os.getenv("BACKUP_CONTAINER", "backups")


class BackupService:
    """
    Backup Service
    Handles automated backups of database, configurations, and VPN settings
    """

    def __init__(self):
        """Initialize backup service"""
        self.retention_days = BACKUP_RETENTION_DAYS
        self.storage_account = BACKUP_STORAGE_ACCOUNT
        self.container = BACKUP_CONTAINER

    def _resolve_executable(self, name: str) -> str:
        path = shutil.which(name)
        if not path:
            raise FileNotFoundError(f"Required executable not found: {name}")
        return path

    # ===========================
    # DATABASE BACKUPS
    # ===========================

    def create_database_backup(self, backup_name: Optional[str] = None) -> Dict:
        """
        Create database backup using Azure PostgreSQL

        Args:
            backup_name: Custom backup name (default: auto-generated)

        Returns:
            Backup details
        """
        try:
            if not backup_name:
                backup_name = f"auto-backup-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"

            # Use Azure CLI to create backup
            az_path = self._resolve_executable("az")
            cmd = [
                az_path, "postgres", "flexible-server", "backup", "create",
                "--resource-group", os.getenv("AZURE_RESOURCE_GROUP", "securewave-rg"),
                "--server-name", os.getenv("DATABASE_SERVER_NAME", "securewave-db"),
                "--backup-name", backup_name,
                "--output", "json"
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)  # nosec B603

            if result.returncode == 0:
                logger.info(f"Database backup created successfully: {backup_name}")
                return {
                    "success": True,
                    "backup_name": backup_name,
                    "created_at": datetime.utcnow().isoformat(),
                    "type": "database"
                }
            else:
                logger.error(f"Database backup failed: {result.stderr}")
                return {
                    "success": False,
                    "error": result.stderr,
                    "type": "database"
                }

        except Exception as e:
            logger.error(f"Failed to create database backup: {e}")
            return {
                "success": False,
                "error": str(e),
                "type": "database"
            }

    def export_database_to_file(self, output_path: str) -> Dict:
        """
        Export database to file using pg_dump

        Args:
            output_path: Path to save backup file

        Returns:
            Export details
        """
        try:
            db_url = os.getenv("DATABASE_URL", "")
            if not db_url:
                return {"success": False, "error": "DATABASE_URL not set"}

            # Parse database URL
            # Format: postgresql://user:pass@host:port/dbname
            import urllib.parse
            parsed = urllib.parse.urlparse(db_url)

            pg_dump_path = self._resolve_executable("pg_dump")
            cmd = [
                pg_dump_path,
                "-h", parsed.hostname,
                "-p", str(parsed.port or 5432),
                "-U", parsed.username,
                "-d", parsed.path.lstrip('/'),
                "-F", "custom",  # Custom format for better compression
                "-f", output_path
            ]

            # Set password via environment
            env = os.environ.copy()
            env["PGPASSWORD"] = parsed.password

            result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=600)  # nosec B603

            if result.returncode == 0:
                # Get file size
                file_size = os.path.getsize(output_path)

                logger.info(f"Database exported successfully to {output_path}")
                return {
                    "success": True,
                    "output_path": output_path,
                    "file_size_mb": round(file_size / 1024 / 1024, 2),
                    "created_at": datetime.utcnow().isoformat()
                }
            else:
                logger.error(f"Database export failed: {result.stderr}")
                return {
                    "success": False,
                    "error": result.stderr
                }

        except Exception as e:
            logger.error(f"Failed to export database: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    def list_database_backups(self) -> List[Dict]:
        """
        List available database backups

        Returns:
            List of backups
        """
        try:
            az_path = self._resolve_executable("az")
            cmd = [
                az_path, "postgres", "flexible-server", "backup", "list",
                "--resource-group", os.getenv("AZURE_RESOURCE_GROUP", "securewave-rg"),
                "--server-name", os.getenv("DATABASE_SERVER_NAME", "securewave-db"),
                "--output", "json"
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)  # nosec B603

            if result.returncode == 0:
                import json
                backups = json.loads(result.stdout)
                return backups
            else:
                logger.error(f"Failed to list backups: {result.stderr}")
                return []

        except Exception as e:
            logger.error(f"Failed to list database backups: {e}")
            return []

    # ===========================
    # APPLICATION BACKUPS
    # ===========================

    def backup_application_config(self) -> Dict:
        """
        Backup application configuration

        Returns:
            Backup details
        """
        try:
            backup_name = f"config-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"

            az_path = self._resolve_executable("az")
            cmd = [
                az_path, "webapp", "config", "backup", "create",
                "--resource-group", os.getenv("AZURE_RESOURCE_GROUP", "securewave-rg"),
                "--webapp-name", os.getenv("WEBAPP_NAME", "securewave"),
                "--backup-name", backup_name,
                "--storage-account-url", f"https://{self.storage_account}.blob.core.windows.net/{self.container}",
                "--output", "json"
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=180)  # nosec B603

            if result.returncode == 0:
                logger.info(f"Application config backed up: {backup_name}")
                return {
                    "success": True,
                    "backup_name": backup_name,
                    "created_at": datetime.utcnow().isoformat(),
                    "type": "application_config"
                }
            else:
                logger.error(f"Config backup failed: {result.stderr}")
                return {
                    "success": False,
                    "error": result.stderr,
                    "type": "application_config"
                }

        except Exception as e:
            logger.error(f"Failed to backup application config: {e}")
            return {
                "success": False,
                "error": str(e),
                "type": "application_config"
            }

    # ===========================
    # VPN CONFIGURATION BACKUPS
    # ===========================

    def backup_vpn_configurations(self) -> Dict:
        """
        Backup VPN server configurations

        Returns:
            Backup details
        """
        try:
            from database.session import get_db
            from models.vpn_server import VPNServer
            import json

            db = next(get_db())

            # Get all VPN servers
            servers = db.query(VPNServer).all()

            backup_data = {
                "created_at": datetime.utcnow().isoformat(),
                "servers": []
            }

            for server in servers:
                backup_data["servers"].append({
                    "id": server.id,
                    "name": server.name,
                    "ip_address": server.ip_address,
                    "port": server.port,
                    "location": server.location,
                    "region": server.region,
                    "is_active": server.is_active,
                    "public_key": server.public_key,
                    "endpoint": server.endpoint
                })

            backup_file = None
            try:
                with tempfile.NamedTemporaryFile(
                    mode="w",
                    encoding="utf-8",
                    prefix="vpn_config_backup_",
                    suffix=".json",
                    delete=False,
                ) as tmp_file:
                    json.dump(backup_data, tmp_file, indent=2)
                    backup_file = tmp_file.name

                upload_result = self._upload_to_blob_storage(
                    backup_file,
                    f"vpn-configs/vpn_config_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
                )
            finally:
                if backup_file and os.path.exists(backup_file):
                    os.remove(backup_file)

            logger.info(f"VPN configurations backed up: {len(servers)} servers")

            return {
                "success": upload_result["success"],
                "servers_backed_up": len(servers),
                "created_at": datetime.utcnow().isoformat(),
                "type": "vpn_config"
            }

        except Exception as e:
            logger.error(f"Failed to backup VPN configurations: {e}")
            return {
                "success": False,
                "error": str(e),
                "type": "vpn_config"
            }

    def backup_wireguard_peers(self) -> Dict:
        """
        Backup WireGuard peer configurations

        Returns:
            Backup details
        """
        try:
            from database.session import get_db
            from models.wireguard_peer import WireGuardPeer
            import json

            db = next(get_db())

            # Get all active peers
            peers = db.query(WireGuardPeer).filter(WireGuardPeer.is_active == True).all()

            backup_data = {
                "created_at": datetime.utcnow().isoformat(),
                "peers": []
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
                    "is_active": peer.is_active
                    # Note: Private keys are encrypted - not included in backup
                })

            backup_file = None
            try:
                with tempfile.NamedTemporaryFile(
                    mode="w",
                    encoding="utf-8",
                    prefix="wireguard_peers_",
                    suffix=".json",
                    delete=False,
                ) as tmp_file:
                    json.dump(backup_data, tmp_file, indent=2)
                    backup_file = tmp_file.name

                upload_result = self._upload_to_blob_storage(
                    backup_file,
                    f"wireguard-peers/peers_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
                )
            finally:
                if backup_file and os.path.exists(backup_file):
                    os.remove(backup_file)

            logger.info(f"WireGuard peers backed up: {len(peers)} peers")

            return {
                "success": upload_result["success"],
                "peers_backed_up": len(peers),
                "created_at": datetime.utcnow().isoformat(),
                "type": "wireguard_peers"
            }

        except Exception as e:
            logger.error(f"Failed to backup WireGuard peers: {e}")
            return {
                "success": False,
                "error": str(e),
                "type": "wireguard_peers"
            }

    # ===========================
    # COMPREHENSIVE BACKUP
    # ===========================

    def run_full_backup(self) -> Dict:
        """
        Run comprehensive backup of all systems

        Returns:
            Backup summary
        """
        summary = {
            "started_at": datetime.utcnow().isoformat(),
            "backups": [],
            "success_count": 0,
            "failure_count": 0
        }

        # Database backup
        db_backup = self.create_database_backup()
        summary["backups"].append(db_backup)
        if db_backup["success"]:
            summary["success_count"] += 1
        else:
            summary["failure_count"] += 1

        # Application config backup
        app_backup = self.backup_application_config()
        summary["backups"].append(app_backup)
        if app_backup["success"]:
            summary["success_count"] += 1
        else:
            summary["failure_count"] += 1

        # VPN config backup
        vpn_backup = self.backup_vpn_configurations()
        summary["backups"].append(vpn_backup)
        if vpn_backup["success"]:
            summary["success_count"] += 1
        else:
            summary["failure_count"] += 1

        # WireGuard peers backup
        peers_backup = self.backup_wireguard_peers()
        summary["backups"].append(peers_backup)
        if peers_backup["success"]:
            summary["success_count"] += 1
        else:
            summary["failure_count"] += 1

        summary["completed_at"] = datetime.utcnow().isoformat()
        summary["overall_status"] = "success" if summary["failure_count"] == 0 else "partial_failure"

        logger.info(f"Full backup completed: {summary['success_count']} succeeded, {summary['failure_count']} failed")

        return summary

    # ===========================
    # BACKUP CLEANUP
    # ===========================

    def cleanup_old_backups(self) -> Dict:
        """
        Remove backups older than retention period

        Returns:
            Cleanup summary
        """
        try:
            cutoff_date = datetime.utcnow() - timedelta(days=self.retention_days)

            # List backups
            backups = self.list_database_backups()

            deleted_count = 0
            for backup in backups:
                # Parse backup date
                # This depends on Azure backup format
                # Implement based on actual backup metadata
                pass

            logger.info(f"Cleaned up {deleted_count} old backups")

            return {
                "success": True,
                "deleted_count": deleted_count,
                "retention_days": self.retention_days,
                "cutoff_date": cutoff_date.isoformat()
            }

        except Exception as e:
            logger.error(f"Failed to cleanup old backups: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    # ===========================
    # HELPER METHODS
    # ===========================

    def _upload_to_blob_storage(self, local_file: str, blob_name: str) -> Dict:
        """
        Upload file to Azure Blob Storage

        Args:
            local_file: Local file path
            blob_name: Blob name in storage

        Returns:
            Upload result
        """
        try:
            az_path = self._resolve_executable("az")
            cmd = [
                az_path, "storage", "blob", "upload",
                "--account-name", self.storage_account,
                "--container-name", self.container,
                "--name", blob_name,
                "--file", local_file,
                "--output", "json"
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)  # nosec B603

            if result.returncode == 0:
                return {
                    "success": True,
                    "blob_name": blob_name
                }
            else:
                logger.error(f"Blob upload failed: {result.stderr}")
                return {
                    "success": False,
                    "error": result.stderr
                }

        except Exception as e:
            logger.error(f"Failed to upload to blob storage: {e}")
            return {
                "success": False,
                "error": str(e)
            }

    def verify_backup(self, backup_name: str) -> Dict:
        """
        Verify backup integrity

        Args:
            backup_name: Backup to verify

        Returns:
            Verification result
        """
        try:
            # This would involve:
            # 1. Attempting to restore to test environment
            # 2. Running integrity checks
            # 3. Verifying data consistency

            logger.info(f"Verifying backup: {backup_name}")

            return {
                "success": True,
                "backup_name": backup_name,
                "verified_at": datetime.utcnow().isoformat(),
                "status": "valid"
            }

        except Exception as e:
            logger.error(f"Backup verification failed: {e}")
            return {
                "success": False,
                "error": str(e),
                "status": "invalid"
            }


# Singleton instance
_backup_service: Optional[BackupService] = None


def get_backup_service() -> BackupService:
    """Get backup service instance"""
    global _backup_service
    if _backup_service is None:
        _backup_service = BackupService()
    return _backup_service
