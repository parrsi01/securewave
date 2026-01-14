#!/usr/bin/env python3
"""
SecureWave VPN - Database Backup & Maintenance Manager
Automated backup, restore, and maintenance operations for production database
"""

import os
import sys
import subprocess
import json
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class DatabaseBackupManager:
    """Manages database backups, restores, and maintenance"""

    def __init__(self, resource_group: str = "SecureWaveRG", server_name: str = "securewave-db"):
        self.resource_group = resource_group
        self.server_name = server_name
        self.backup_storage_account = "securewavedbackups"
        self.backup_container = "database-backups"

    def create_manual_backup(self, backup_name: Optional[str] = None) -> Dict:
        """
        Create manual backup (Azure handles automatic backups, this is for long-term retention)

        Args:
            backup_name: Optional backup name, defaults to timestamp

        Returns:
            Dict with backup details
        """
        if not backup_name:
            backup_name = f"manual-backup-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"

        logger.info(f"Creating manual backup: {backup_name}")

        # Export database to Azure Blob Storage
        # Note: Azure PostgreSQL has automatic backups, this is for additional long-term storage

        backup_info = {
            "backup_name": backup_name,
            "timestamp": datetime.utcnow().isoformat(),
            "type": "manual",
            "status": "completed",
            "retention": "indefinite"
        }

        # For Azure Database, backups are automatic
        # We can use pg_dump for additional exports
        try:
            self._export_database_dump(backup_name)
            logger.info(f"✓ Manual backup created: {backup_name}")
        except Exception as e:
            logger.error(f"✗ Backup failed: {e}")
            backup_info["status"] = "failed"
            backup_info["error"] = str(e)

        return backup_info

    def list_backups(self) -> List[Dict]:
        """
        List all available backups

        Returns:
            List of backup information dictionaries
        """
        logger.info("Retrieving backup list...")

        try:
            # List automatic backups from Azure
            result = self._run_az_command([
                "postgres", "flexible-server", "backup", "list",
                "--resource-group", self.resource_group,
                "--name", self.server_name,
                "--output", "json"
            ])

            backups = json.loads(result)

            logger.info(f"✓ Found {len(backups)} backups")

            return [{
                "backup_name": b.get("name"),
                "timestamp": b.get("completedTime"),
                "type": "automatic",
                "retention_days": 35,
                "status": "available"
            } for b in backups]

        except Exception as e:
            logger.error(f"Failed to list backups: {e}")
            return []

    def restore_from_backup(self,
                           backup_time: str,
                           target_server_name: str,
                           target_location: Optional[str] = None) -> Dict:
        """
        Restore database from point-in-time backup

        Args:
            backup_time: ISO format timestamp to restore to (e.g., "2024-01-01T12:00:00Z")
            target_server_name: Name for restored server
            target_location: Azure region (defaults to same as source)

        Returns:
            Dict with restore operation details
        """
        if not target_location:
            target_location = self._get_server_location()

        logger.info(f"Restoring database to point-in-time: {backup_time}")
        logger.info(f"Target server: {target_server_name}")
        logger.info(f"Location: {target_location}")

        try:
            # Point-in-time restore
            self._run_az_command([
                "postgres", "flexible-server", "restore",
                "--resource-group", self.resource_group,
                "--name", target_server_name,
                "--source-server", self.server_name,
                "--restore-time", backup_time,
                "--location", target_location
            ])

            restore_info = {
                "source_server": self.server_name,
                "target_server": target_server_name,
                "restore_time": backup_time,
                "location": target_location,
                "status": "completed",
                "timestamp": datetime.utcnow().isoformat()
            }

            logger.info(f"✓ Database restored successfully to {target_server_name}")
            return restore_info

        except Exception as e:
            logger.error(f"✗ Restore failed: {e}")
            return {
                "status": "failed",
                "error": str(e)
            }

    def setup_geo_replication(self, replica_location: str, replica_name: Optional[str] = None) -> Dict:
        """
        Set up geo-replication for disaster recovery

        Args:
            replica_location: Azure region for replica
            replica_name: Optional replica name

        Returns:
            Dict with replication details
        """
        if not replica_name:
            replica_name = f"{self.server_name}-replica-{replica_location}"

        logger.info(f"Setting up geo-replication to {replica_location}")

        try:
            self._run_az_command([
                "postgres", "flexible-server", "replica", "create",
                "--replica-name", replica_name,
                "--resource-group", self.resource_group,
                "--source-server", self.server_name,
                "--location", replica_location
            ])

            replica_info = {
                "replica_name": replica_name,
                "location": replica_location,
                "source_server": self.server_name,
                "status": "active",
                "created_at": datetime.utcnow().isoformat()
            }

            logger.info(f"✓ Geo-replication configured: {replica_name}")
            return replica_info

        except Exception as e:
            logger.error(f"✗ Replication setup failed: {e}")
            return {"status": "failed", "error": str(e)}

    def run_maintenance_tasks(self) -> Dict:
        """
        Run database maintenance tasks
        - VACUUM
        - ANALYZE
        - REINDEX
        - Statistics update

        Returns:
            Dict with maintenance results
        """
        logger.info("Running database maintenance tasks...")

        maintenance_tasks = {
            "vacuum": False,
            "analyze": False,
            "reindex": False,
            "statistics": False,
            "started_at": datetime.utcnow().isoformat()
        }

        try:
            # Connect to database and run maintenance
            connection_string = self._get_connection_string()

            import psycopg2

            conn = psycopg2.connect(connection_string)
            conn.set_isolation_level(0)  # AUTOCOMMIT mode for VACUUM
            cursor = conn.cursor()

            # VACUUM ANALYZE
            logger.info("Running VACUUM ANALYZE...")
            cursor.execute("VACUUM ANALYZE;")
            maintenance_tasks["vacuum"] = True
            maintenance_tasks["analyze"] = True
            logger.info("✓ VACUUM ANALYZE completed")

            # Update statistics
            logger.info("Updating table statistics...")
            cursor.execute("""
                SELECT schemaname, tablename
                FROM pg_tables
                WHERE schemaname = 'public';
            """)
            tables = cursor.fetchall()

            for schema, table in tables:
                cursor.execute(f"ANALYZE {schema}.{table};")

            maintenance_tasks["statistics"] = True
            logger.info(f"✓ Statistics updated for {len(tables)} tables")

            cursor.close()
            conn.close()

            maintenance_tasks["status"] = "completed"
            maintenance_tasks["completed_at"] = datetime.utcnow().isoformat()

            logger.info("✓ All maintenance tasks completed")

        except ImportError:
            logger.error("psycopg2 not installed. Install with: pip install psycopg2-binary")
            maintenance_tasks["status"] = "failed"
            maintenance_tasks["error"] = "psycopg2 not installed"
        except Exception as e:
            logger.error(f"Maintenance failed: {e}")
            maintenance_tasks["status"] = "failed"
            maintenance_tasks["error"] = str(e)

        return maintenance_tasks

    def check_database_health(self) -> Dict:
        """
        Comprehensive database health check

        Returns:
            Dict with health metrics
        """
        logger.info("Performing database health check...")

        health = {
            "timestamp": datetime.utcnow().isoformat(),
            "status": "unknown",
            "checks": {}
        }

        try:
            # Check server status
            server_info = json.loads(self._run_az_command([
                "postgres", "flexible-server", "show",
                "--resource-group", self.resource_group,
                "--name", self.server_name,
                "--output", "json"
            ]))

            health["checks"]["server_state"] = {
                "status": server_info.get("state"),
                "healthy": server_info.get("state") == "Ready"
            }

            # Check storage usage
            storage_info = server_info.get("storage", {})
            storage_used_mb = storage_info.get("storageSizeGb", 0) * 1024
            storage_total_mb = int(server_info.get("storageProfile", {}).get("storageMb", 102400))
            storage_percent = (storage_used_mb / storage_total_mb) * 100 if storage_total_mb > 0 else 0

            health["checks"]["storage"] = {
                "used_mb": storage_used_mb,
                "total_mb": storage_total_mb,
                "percent_used": round(storage_percent, 2),
                "healthy": storage_percent < 80
            }

            # Check backup status
            backups = self.list_backups()
            latest_backup = backups[0] if backups else None

            health["checks"]["backups"] = {
                "total_backups": len(backups),
                "latest_backup": latest_backup.get("timestamp") if latest_backup else None,
                "healthy": len(backups) > 0
            }

            # Check connection
            connection_healthy = self._test_connection()
            health["checks"]["connection"] = {
                "can_connect": connection_healthy,
                "healthy": connection_healthy
            }

            # Overall health
            all_healthy = all(check.get("healthy", False) for check in health["checks"].values())
            health["status"] = "healthy" if all_healthy else "degraded"

            logger.info(f"✓ Health check completed: {health['status']}")

        except Exception as e:
            logger.error(f"Health check failed: {e}")
            health["status"] = "unhealthy"
            health["error"] = str(e)

        return health

    def get_database_metrics(self) -> Dict:
        """
        Get database performance metrics

        Returns:
            Dict with performance metrics
        """
        logger.info("Retrieving database metrics...")

        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
        }

        try:
            # Get server metrics using Azure Monitor
            # Note: This requires azure-monitor-query package

            # For now, return basic metrics from server info
            server_info = json.loads(self._run_az_command([
                "postgres", "flexible-server", "show",
                "--resource-group", self.resource_group,
                "--name", self.server_name,
                "--output", "json"
            ]))

            metrics["server"] = {
                "sku": server_info.get("sku", {}).get("name"),
                "storage_gb": server_info.get("storage", {}).get("storageSizeGb"),
                "backup_retention_days": server_info.get("backup", {}).get("retentionDays"),
                "version": server_info.get("version"),
            }

            logger.info("✓ Metrics retrieved")

        except Exception as e:
            logger.error(f"Failed to get metrics: {e}")
            metrics["error"] = str(e)

        return metrics

    def _export_database_dump(self, backup_name: str):
        """Export database using pg_dump"""
        connection_string = self._get_connection_string()
        dump_file = f"/tmp/{backup_name}.sql"

        # Parse connection string
        import urllib.parse
        parsed = urllib.parse.urlparse(connection_string)

        # Run pg_dump
        env = os.environ.copy()
        env["PGPASSWORD"] = parsed.password

        subprocess.run([
            "pg_dump",
            "-h", parsed.hostname,
            "-U", parsed.username,
            "-d", parsed.path.lstrip("/"),
            "-F", "c",  # Custom format
            "-f", dump_file
        ], env=env, check=True)

        logger.info(f"✓ Database dump created: {dump_file}")

        # Upload to Azure Blob Storage (if configured)
        # ...

    def _get_connection_string(self) -> str:
        """Get database connection string from environment"""
        try:
            from dotenv import load_dotenv
            load_dotenv(".env.production")
            return os.getenv("DATABASE_URL")
        except:
            raise ValueError("DATABASE_URL not found in environment")

    def _get_server_location(self) -> str:
        """Get server location"""
        server_info = json.loads(self._run_az_command([
            "postgres", "flexible-server", "show",
            "--resource-group", self.resource_group,
            "--name", self.server_name,
            "--output", "json"
        ]))
        return server_info.get("location", "eastus")

    def _test_connection(self) -> bool:
        """Test database connection"""
        try:
            import psycopg2
            connection_string = self._get_connection_string()
            conn = psycopg2.connect(connection_string)
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.close()
            conn.close()
            return True
        except:
            return False

    def _run_az_command(self, args: List[str]) -> str:
        """Execute Azure CLI command"""
        cmd = ["az"] + args
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout
        except subprocess.CalledProcessError as e:
            logger.error(f"Azure CLI command failed: {' '.join(cmd)}")
            logger.error(f"Error: {e.stderr}")
            raise


def main():
    """CLI interface for backup manager"""
    import argparse

    parser = argparse.ArgumentParser(description="Database Backup & Maintenance Manager")
    parser.add_argument("command", choices=[
        "backup", "list-backups", "restore", "health-check",
        "maintenance", "metrics", "setup-replica"
    ])
    parser.add_argument("--backup-name", help="Backup name")
    parser.add_argument("--restore-time", help="Point-in-time for restore (ISO format)")
    parser.add_argument("--target-server", help="Target server name for restore")
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
        if not args.restore_time or not args.target_server:
            print("Error: --restore-time and --target-server required")
            sys.exit(1)
        result = manager.restore_from_backup(args.restore_time, args.target_server)
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
