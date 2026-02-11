#!/usr/bin/env python3
"""
SecureWave VPN - Disaster Recovery Manager
Focused on single-server recovery using local backups and Terraform reprovisioning.
"""

import os
import sys
import json
import logging
from typing import Dict
from datetime import datetime

from infrastructure.database_backup_manager import DatabaseBackupManager

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class DisasterRecoveryManager:
    """Manages disaster recovery operations for the single-server deployment."""

    def __init__(self):
        self.primary_location = os.getenv("HCLOUD_LOCATION", "ash")
        self.rto = "2 hours"
        self.rpo = "24 hours"

    def create_disaster_recovery_plan(self) -> Dict:
        logger.info("Creating Disaster Recovery Plan")

        dr_plan = {
            "created_at": datetime.utcnow().isoformat(),
            "primary_location": self.primary_location,
            "rto": self.rto,
            "rpo": self.rpo,
            "architecture": "single-server",
            "components": {
                "database": {
                    "backup_strategy": "local backups via infrastructure/database_backup_manager.py",
                    "recovery_method": "restore from latest backup file",
                },
                "vpn_infrastructure": {
                    "servers": "single WireGuard node",
                    "recovery_method": "reprovision via Terraform and reapply bootstrap",
                },
                "web_application": {
                    "deployment": "same host as VPN",
                    "recovery_method": "redeploy containers or systemd services",
                },
            },
            "procedures": {
                "host_failure": [
                    "1. Provision replacement server with Terraform",
                    "2. Run scripts/hetzner_bootstrap.sh on the new host",
                    "3. Restore database from latest backup file",
                    "4. Redeploy application and WireGuard services",
                    "5. Update DNS to new IP",
                ],
                "data_corruption": [
                    "1. Identify last known good backup",
                    "2. Restore database to a fresh instance",
                    "3. Validate application behavior",
                    "4. Promote restored database",
                ],
            },
            "contacts": {
                "incident_commander": "oncall@securewave.app",
                "infrastructure_lead": "infra@securewave.app",
                "database_admin": "admin@securewave.app",
            },
        }

        with open("disaster_recovery_plan.json", "w") as f:
            json.dump(dr_plan, f, indent=2)

        logger.info("✓ Disaster recovery plan created")
        return dr_plan

    def test_backup_restore(self) -> bool:
        """Validate that backups exist and are readable (non-destructive)."""
        logger.info("Validating backup availability")
        manager = DatabaseBackupManager()
        backups = manager.list_backups()
        if not backups:
            logger.warning("No backups found. Create a backup before running DR tests.")
            return False
        logger.info("Found %s backup(s). Latest: %s", len(backups), backups[-1].get("name"))
        return True

    def activate_disaster_recovery(self, incident_type: str) -> None:
        """Print recovery steps for operators."""
        logger.info("DR activation requested for incident type: %s", incident_type)
        logger.info("See docs/HETZNER_RUNBOOK.md and disaster_recovery_plan.json for steps.")

    def create_runbook(self) -> str:
        """Generate a short DR runbook."""
        runbook = f"""# Disaster Recovery Runbook

**Architecture:** single-server
**Primary Location:** {self.primary_location}
**RTO:** {self.rto}
**RPO:** {self.rpo}

## 1. Host Failure

```bash
# Provision replacement host
cd infrastructure/hetzner
terraform apply

# Bootstrap server
ssh root@<new-ip> 'bash -s' < scripts/hetzner_bootstrap.sh

# Restore database
python3 infrastructure/database_backup_manager.py restore --backup-name <latest-backup>

# Redeploy services
# (see docs/HETZNER_RUNBOOK.md)
```

## 2. Data Corruption

```bash
# Restore from last known good backup
python3 infrastructure/database_backup_manager.py restore --backup-name <backup-name>
```

## 3. Verification

```bash
curl http://<server-ip>/api/health
```

**Contacts:** oncall@securewave.app, infra@securewave.app
"""

        with open("DISASTER_RECOVERY_RUNBOOK.md", "w") as f:
            f.write(runbook)

        logger.info("✓ Runbook saved to DISASTER_RECOVERY_RUNBOOK.md")
        return runbook


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Disaster Recovery Manager")
    parser.add_argument(
        "command",
        choices=["create-plan", "test-restore", "activate", "create-runbook"],
        help="DR command to execute",
    )
    parser.add_argument(
        "--incident-type",
        choices=["host_failure", "data_corruption"],
        default="host_failure",
        help="Type of incident (for activate command)",
    )

    args = parser.parse_args()

    manager = DisasterRecoveryManager()

    if args.command == "create-plan":
        manager.create_disaster_recovery_plan()
    elif args.command == "test-restore":
        success = manager.test_backup_restore()
        sys.exit(0 if success else 1)
    elif args.command == "activate":
        manager.activate_disaster_recovery(incident_type=args.incident_type)
    elif args.command == "create-runbook":
        manager.create_runbook()


if __name__ == "__main__":
    main()
