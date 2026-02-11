#!/usr/bin/env python3
"""
SecureWave VPN - Database Backup & Maintenance Manager
Local backup, restore, and maintenance operations.
"""

import os
import sys
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional

from services.backup_service import BackupService

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class DatabaseBackupManager:
    """Manages database backups, restores, and maintenance"""

    def __init__(self):
        self.backup_service = BackupService()

    def create_manual_backup(self, backup_name: Optional[str] = None) -> Dict:
        """
        Create a manual backup stored on local disk.
        """
        logger.info("Creating manual backup")
        result = self.backup_service.create_database_backup(backup_name)
        if result.get("success"):
            result["type"] = "manual"
        return result

    def list_backups(self) -> List[Dict]:
        """List all available backups."""
        backups = self.backup_service.list_database_backups()
        for backup in backups:
            backup.setdefault("type", "manual")
        return backups

    def restore_from_backup(
        self,
        backup_name: Optional[str] = None,
        backup_file: Optional[str] = None,
        target_database_url: Optional[str] = None,
    ) -> Dict:
        """
        Restore database from a backup file.
        """
        if not backup_file and not backup_name:
            return {"status": "failed", "error": "backup_name or backup_file required"}

        if backup_file:
            backup_path = Path(backup_file)
        else:
            backup_path = self._resolve_backup_path(backup_name)

        if not backup_path.exists():
            return {"status": "failed", "error": f"Backup file not found: {backup_path}"}

        database_url = target_database_url or os.getenv("DATABASE_URL", "")
        if not database_url:
            return {"status": "failed", "error": "DATABASE_URL not set"}

        try:
            if database_url.startswith("sqlite:///"):
                db_path = database_url.replace("sqlite:///", "")
                if db_path == ":memory:":
                    return {"status": "failed", "error": "Cannot restore to in-memory SQLite"}
                backup_path.replace(db_path)
                return {
                    "status": "completed",
                    "restored_to": db_path,
                    "backup": str(backup_path),
                    "timestamp": datetime.utcnow().isoformat(),
                }

            if not database_url.startswith("postgresql"):
                return {"status": "failed", "error": "Restore supports PostgreSQL or SQLite only"}

            import urllib.parse
            parsed = urllib.parse.urlparse(database_url)
            pg_restore = "pg_restore"

            cmd = [
                pg_restore,
                "--clean",
                "--if-exists",
                "-h", parsed.hostname,
                "-p", str(parsed.port or 5432),
                "-U", parsed.username,
                "-d", parsed.path.lstrip("/"),
                str(backup_path),
            ]

            env = os.environ.copy()
            env["PGPASSWORD"] = parsed.password or ""

            import subprocess
            subprocess.run(cmd, env=env, check=True)

            return {
                "status": "completed",
                "restored_to": parsed.path.lstrip("/"),
                "backup": str(backup_path),
                "timestamp": datetime.utcnow().isoformat(),
            }

        except Exception as e:
            logger.error("Restore failed: %s", e)
            return {"status": "failed", "error": str(e)}

    def check_database_health(self) -> Dict:
        """Check database connectivity."""
        health = {
            "timestamp": datetime.utcnow().isoformat(),
            "checks": {},
            "status": "unknown",
        }

        try:
            from database.session import SessionLocal
            db = SessionLocal()
            db.execute("SELECT 1")
            db.close()
            health["checks"]["connection"] = {"healthy": True}
            health["status"] = "healthy"
        except Exception as e:
            health["checks"]["connection"] = {"healthy": False, "error": str(e)}
            health["status"] = "unhealthy"

        return health

    def run_maintenance_tasks(self) -> Dict:
        """Run database maintenance tasks."""
        results = {
            "timestamp": datetime.utcnow().isoformat(),
            "tasks": [],
        }

        try:
            from database.session import SessionLocal
            db = SessionLocal()
            db.execute("VACUUM ANALYZE")
            db.close()
            results["tasks"].append({"task": "vacuum_analyze", "status": "completed"})
        except Exception as e:
            results["tasks"].append({"task": "vacuum_analyze", "status": "failed", "error": str(e)})

        return results

    def get_database_metrics(self) -> Dict:
        """Return basic database metrics."""
        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
        }
        try:
            database_url = os.getenv("DATABASE_URL", "")
            if database_url.startswith("sqlite:///"):
                db_path = database_url.replace("sqlite:///", "")
                if db_path != ":memory:":
                    metrics["database_size_bytes"] = Path(db_path).stat().st_size
            elif database_url.startswith("postgresql"):
                from database.session import SessionLocal
                db = SessionLocal()
                result = db.execute(
                    "SELECT pg_database_size(current_database())"
                ).fetchone()
                db.close()
                metrics["database_size_bytes"] = int(result[0]) if result else None
        except Exception as e:
            metrics["error"] = str(e)
        return metrics

    def setup_geo_replication(self, replica_location: str, replica_name: Optional[str] = None) -> Dict:
        """Geo-replication is not supported in the local backup manager."""
        return {
            "status": "not_supported",
            "error": "Geo-replication must be configured separately for the database provider.",
        }

    def _resolve_backup_path(self, backup_name: str) -> Path:
        backup_dir = Path(os.getenv("BACKUP_ROOT", "backups")) / "database"
        backup_dir.mkdir(parents=True, exist_ok=True)
        if backup_name.endswith(".dump"):
            return backup_dir / backup_name
        return backup_dir / f"{backup_name}.dump"


def main():
    """CLI interface for backup manager"""
    import argparse

    parser = argparse.ArgumentParser(description="Database Backup & Maintenance Manager")
    parser.add_argument("command", choices=[
        "backup", "list-backups", "restore", "health-check",
        "maintenance", "metrics", "setup-replica"
    ])
    parser.add_argument("--backup-name", help="Backup name")
    parser.add_argument("--backup-file", help="Backup file path for restore")
    parser.add_argument("--target-database-url", help="Target DATABASE_URL for restore")
    parser.add_argument("--replica-location", help="Location for replica")

    args = parser.parse_args()

    manager = DatabaseBackupManager()

    if args.command == "backup":
        result = manager.create_manual_backup(args.backup_name)
        print(json.dumps(result, indent=2))

    elif args.command == "list-backups":
        backups = manager.list_backups()
        print(json.dumps(backups, indent=2))

    elif args.command == "restore":
        result = manager.restore_from_backup(
            backup_name=args.backup_name,
            backup_file=args.backup_file,
            target_database_url=args.target_database_url,
        )
        print(json.dumps(result, indent=2))

    elif args.command == "health-check":
        health = manager.check_database_health()
        print(json.dumps(health, indent=2))

    elif args.command == "maintenance":
        result = manager.run_maintenance_tasks()
        print(json.dumps(result, indent=2))

    elif args.command == "metrics":
        metrics = manager.get_database_metrics()
        print(json.dumps(metrics, indent=2))

    elif args.command == "setup-replica":
        if not args.replica_location:
            print("Error: --replica-location required")
            sys.exit(1)
        result = manager.setup_geo_replication(args.replica_location)
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
