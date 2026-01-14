#!/usr/bin/env python3
"""
SecureWave VPN - Database Monitoring Setup
Configure Azure Monitor, alerts, and diagnostic logging for production database
"""

import os
import sys
import json
import subprocess
import logging
from typing import Dict, List
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class DatabaseMonitoringSetup:
    """Configure comprehensive monitoring for Azure PostgreSQL database"""

    def __init__(self, resource_group: str = "SecureWaveRG", server_name: str = "securewave-db"):
        self.resource_group = resource_group
        self.server_name = server_name
        self.workspace_name = "securewave-db-logs"
        self.alert_email = os.getenv("ALERT_EMAIL", "admin@securewave.app")

    def create_log_analytics_workspace(self) -> Dict:
        """Create Azure Monitor Log Analytics workspace"""
        logger.info("Creating Log Analytics workspace...")

        try:
            # Check if workspace exists
            result = subprocess.run(
                [
                    "az", "monitor", "log-analytics", "workspace", "show",
                    "--resource-group", self.resource_group,
                    "--workspace-name", self.workspace_name,
                    "--output", "json"
                ],
                capture_output=True,
                text=True
            )

            if result.returncode == 0:
                workspace = json.loads(result.stdout)
                logger.info(f"✓ Workspace already exists: {workspace['id']}")
                return workspace

            # Create workspace
            logger.info("Creating new workspace...")
            result = subprocess.run(
                [
                    "az", "monitor", "log-analytics", "workspace", "create",
                    "--resource-group", self.resource_group,
                    "--workspace-name", self.workspace_name,
                    "--location", "eastus",
                    "--output", "json"
                ],
                capture_output=True,
                text=True,
                check=True
            )

            workspace = json.loads(result.stdout)
            logger.info(f"✓ Created Log Analytics workspace: {workspace['id']}")

            return workspace

        except subprocess.CalledProcessError as e:
            logger.error(f"✗ Failed to create workspace: {e.stderr}")
            raise
        except Exception as e:
            logger.error(f"✗ Unexpected error: {e}")
            raise

    def enable_diagnostic_logging(self, workspace_id: str) -> bool:
        """Enable diagnostic logging for database"""
        logger.info("Enabling diagnostic logging...")

        try:
            # Get database resource ID
            db_result = subprocess.run(
                [
                    "az", "postgres", "flexible-server", "show",
                    "--resource-group", self.resource_group,
                    "--name", self.server_name,
                    "--query", "id",
                    "-o", "tsv"
                ],
                capture_output=True,
                text=True,
                check=True
            )

            db_resource_id = db_result.stdout.strip()

            # Check if diagnostic settings exist
            diag_list = subprocess.run(
                [
                    "az", "monitor", "diagnostic-settings", "list",
                    "--resource", db_resource_id,
                    "--output", "json"
                ],
                capture_output=True,
                text=True
            )

            if diag_list.returncode == 0:
                existing = json.loads(diag_list.stdout)
                if existing.get("value"):
                    logger.info("✓ Diagnostic settings already configured")
                    return True

            # Create diagnostic settings
            logger.info("Creating diagnostic settings...")

            # Prepare logs configuration
            logs_config = json.dumps([
                {"category": "PostgreSQLLogs", "enabled": True, "retentionPolicy": {"days": 30, "enabled": True}},
                {"category": "PostgreSQLFlexDatabaseXacts", "enabled": True, "retentionPolicy": {"days": 30, "enabled": True}},
                {"category": "PostgreSQLFlexQueryStoreRuntime", "enabled": True, "retentionPolicy": {"days": 30, "enabled": True}},
                {"category": "PostgreSQLFlexQueryStoreWaitStats", "enabled": True, "retentionPolicy": {"days": 30, "enabled": True}},
                {"category": "PostgreSQLFlexSessions", "enabled": True, "retentionPolicy": {"days": 30, "enabled": True}},
                {"category": "PostgreSQLFlexTableStats", "enabled": True, "retentionPolicy": {"days": 30, "enabled": True}},
            ])

            metrics_config = json.dumps([
                {"category": "AllMetrics", "enabled": True, "retentionPolicy": {"days": 30, "enabled": True}}
            ])

            subprocess.run(
                [
                    "az", "monitor", "diagnostic-settings", "create",
                    "--name", "db-diagnostics",
                    "--resource", db_resource_id,
                    "--workspace", workspace_id,
                    "--logs", logs_config,
                    "--metrics", metrics_config
                ],
                check=True
            )

            logger.info("✓ Diagnostic logging enabled")
            return True

        except subprocess.CalledProcessError as e:
            logger.error(f"✗ Failed to enable diagnostic logging: {e.stderr if hasattr(e, 'stderr') else str(e)}")
            return False
        except Exception as e:
            logger.error(f"✗ Unexpected error: {e}")
            return False

    def create_alert_rules(self) -> bool:
        """Create metric alert rules"""
        logger.info("Creating alert rules...")

        try:
            # Get database resource ID
            db_result = subprocess.run(
                [
                    "az", "postgres", "flexible-server", "show",
                    "--resource-group", self.resource_group,
                    "--name", self.server_name,
                    "--query", "id",
                    "-o", "tsv"
                ],
                capture_output=True,
                text=True,
                check=True
            )

            db_resource_id = db_result.stdout.strip()

            # Define alert rules
            alert_rules = [
                {
                    "name": "DB-High-CPU",
                    "description": "CPU usage above 80%",
                    "condition": "avg cpu_percent > 80",
                    "severity": 2,
                },
                {
                    "name": "DB-High-Memory",
                    "description": "Memory usage above 85%",
                    "condition": "avg memory_percent > 85",
                    "severity": 2,
                },
                {
                    "name": "DB-Storage-Critical",
                    "description": "Storage usage above 80%",
                    "condition": "avg storage_percent > 80",
                    "severity": 1,
                },
                {
                    "name": "DB-Connection-Failures",
                    "description": "High connection failure rate",
                    "condition": "total failed_connections > 50",
                    "severity": 2,
                },
                {
                    "name": "DB-Deadlocks",
                    "description": "Database deadlocks detected",
                    "condition": "total deadlock_count > 5",
                    "severity": 2,
                },
                {
                    "name": "DB-Replication-Lag",
                    "description": "Replication lag exceeds threshold",
                    "condition": "avg replication_lag > 300",  # 5 minutes
                    "severity": 2,
                },
            ]

            created_count = 0

            for rule in alert_rules:
                try:
                    # Check if alert exists
                    check_result = subprocess.run(
                        [
                            "az", "monitor", "metrics", "alert", "show",
                            "--name", rule["name"],
                            "--resource-group", self.resource_group
                        ],
                        capture_output=True,
                        text=True
                    )

                    if check_result.returncode == 0:
                        logger.info(f"✓ Alert '{rule['name']}' already exists")
                        created_count += 1
                        continue

                    # Create alert
                    logger.info(f"Creating alert: {rule['name']}...")

                    subprocess.run(
                        [
                            "az", "monitor", "metrics", "alert", "create",
                            "--name", rule["name"],
                            "--resource-group", self.resource_group,
                            "--scopes", db_resource_id,
                            "--condition", rule["condition"],
                            "--description", rule["description"],
                            "--severity", str(rule["severity"]),
                            "--window-size", "5m",
                            "--evaluation-frequency", "1m",
                        ],
                        check=True
                    )

                    logger.info(f"✓ Created alert: {rule['name']}")
                    created_count += 1

                except subprocess.CalledProcessError as e:
                    logger.warning(f"Could not create alert {rule['name']}: {e.stderr if hasattr(e, 'stderr') else str(e)}")
                    continue

            logger.info(f"✓ Configured {created_count}/{len(alert_rules)} alert rules")
            return created_count > 0

        except Exception as e:
            logger.error(f"✗ Failed to create alert rules: {e}")
            return False

    def create_action_group(self) -> bool:
        """Create action group for alert notifications"""
        logger.info("Creating action group for notifications...")

        try:
            # Check if action group exists
            check_result = subprocess.run(
                [
                    "az", "monitor", "action-group", "show",
                    "--name", "db-alerts",
                    "--resource-group", self.resource_group
                ],
                capture_output=True,
                text=True
            )

            if check_result.returncode == 0:
                logger.info("✓ Action group already exists")
                return True

            # Create action group
            subprocess.run(
                [
                    "az", "monitor", "action-group", "create",
                    "--name", "db-alerts",
                    "--resource-group", self.resource_group,
                    "--short-name", "db-alerts",
                    "--email-receiver", "admin", self.alert_email
                ],
                check=True
            )

            logger.info(f"✓ Created action group (email: {self.alert_email})")
            return True

        except subprocess.CalledProcessError as e:
            logger.error(f"✗ Failed to create action group: {e.stderr if hasattr(e, 'stderr') else str(e)}")
            return False
        except Exception as e:
            logger.error(f"✗ Unexpected error: {e}")
            return False

    def verify_monitoring_setup(self) -> Dict:
        """Verify monitoring configuration"""
        logger.info("Verifying monitoring setup...")

        status = {
            "workspace": False,
            "diagnostic_logging": False,
            "alerts": False,
            "action_group": False,
        }

        try:
            # Check workspace
            result = subprocess.run(
                [
                    "az", "monitor", "log-analytics", "workspace", "show",
                    "--resource-group", self.resource_group,
                    "--workspace-name", self.workspace_name
                ],
                capture_output=True,
                text=True
            )
            status["workspace"] = result.returncode == 0

            # Check action group
            result = subprocess.run(
                [
                    "az", "monitor", "action-group", "show",
                    "--name", "db-alerts",
                    "--resource-group", self.resource_group
                ],
                capture_output=True,
                text=True
            )
            status["action_group"] = result.returncode == 0

            # Check alerts (at least one exists)
            result = subprocess.run(
                [
                    "az", "monitor", "metrics", "alert", "list",
                    "--resource-group", self.resource_group,
                    "--output", "json"
                ],
                capture_output=True,
                text=True
            )

            if result.returncode == 0:
                alerts = json.loads(result.stdout)
                db_alerts = [a for a in alerts if "DB-" in a.get("name", "")]
                status["alerts"] = len(db_alerts) > 0

            # Overall status
            all_configured = all(status.values())
            logger.info(f"✓ Workspace: {status['workspace']}")
            logger.info(f"✓ Diagnostic Logging: {status['diagnostic_logging']}")
            logger.info(f"✓ Alerts: {status['alerts']}")
            logger.info(f"✓ Action Group: {status['action_group']}")

            if all_configured:
                logger.info("✓ All monitoring components configured")
            else:
                logger.warning("⚠ Some monitoring components missing")

            return status

        except Exception as e:
            logger.error(f"✗ Verification failed: {e}")
            return status

    def run_full_setup(self) -> bool:
        """Run complete monitoring setup"""
        logger.info("="*70)
        logger.info("SecureWave VPN - Database Monitoring Setup")
        logger.info("="*70)
        logger.info(f"Resource Group: {self.resource_group}")
        logger.info(f"Database Server: {self.server_name}")
        logger.info(f"Alert Email: {self.alert_email}")
        logger.info("")

        try:
            # Step 1: Create Log Analytics workspace
            workspace = self.create_log_analytics_workspace()

            # Step 2: Enable diagnostic logging
            self.enable_diagnostic_logging(workspace["id"])

            # Step 3: Create action group
            self.create_action_group()

            # Step 4: Create alert rules
            self.create_alert_rules()

            # Step 5: Verify setup
            logger.info("\nVerifying configuration...")
            status = self.verify_monitoring_setup()

            logger.info("\n" + "="*70)
            logger.info("✅ Database Monitoring Setup Complete!")
            logger.info("="*70)
            logger.info("\nConfigured components:")
            logger.info(f"  - Log Analytics Workspace: {self.workspace_name}")
            logger.info(f"  - Diagnostic Logging: Enabled")
            logger.info(f"  - Alert Rules: Configured")
            logger.info(f"  - Email Notifications: {self.alert_email}")
            logger.info("\nNext steps:")
            logger.info("1. View logs: Azure Portal > Monitor > Log Analytics")
            logger.info("2. View alerts: Azure Portal > Monitor > Alerts")
            logger.info("3. Test alerts: Simulate high CPU/memory usage")
            logger.info("")

            return all(status.values())

        except Exception as e:
            logger.error(f"\n✗ Monitoring setup failed: {e}")
            return False


def main():
    """CLI interface for monitoring setup"""
    import argparse

    parser = argparse.ArgumentParser(description="Setup Database Monitoring")
    parser.add_argument(
        "--resource-group",
        default="SecureWaveRG",
        help="Azure resource group name"
    )
    parser.add_argument(
        "--server-name",
        default="securewave-db",
        help="PostgreSQL server name"
    )
    parser.add_argument(
        "--alert-email",
        default=os.getenv("ALERT_EMAIL", "admin@securewave.app"),
        help="Email for alert notifications"
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Only verify existing setup without making changes"
    )

    args = parser.parse_args()

    setup = DatabaseMonitoringSetup(
        resource_group=args.resource_group,
        server_name=args.server_name
    )
    setup.alert_email = args.alert_email

    if args.verify_only:
        status = setup.verify_monitoring_setup()
        sys.exit(0 if all(status.values()) else 1)
    else:
        success = setup.run_full_setup()
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
