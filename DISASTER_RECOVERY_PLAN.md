# Disaster Recovery Plan

This project uses a single-server deployment. Disaster recovery focuses on rapid reprovisioning and backup restore.

## Objectives

- **RTO:** 2 hours
- **RPO:** 24 hours

## Procedures

### Host Failure

1. Provision a replacement server via Terraform (`infrastructure/hetzner/`).
2. Run `scripts/hetzner_bootstrap.sh` on the new host.
3. Restore the database using `infrastructure/database_backup_manager.py`.
4. Redeploy application and WireGuard services.
5. Update DNS to the new IP.

### Data Corruption

1. Identify the last known good backup.
2. Restore the database from backup.
3. Verify application health.

## Tools

- `infrastructure/disaster_recovery.py`
- `infrastructure/database_backup_manager.py`

## Contacts

- oncall@securewave.app
- infra@securewave.app
- admin@securewave.app
