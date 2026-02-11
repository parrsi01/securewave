# Database Operations Guide

## Backups

```bash
python3 infrastructure/database_backup_manager.py backup
python3 infrastructure/database_backup_manager.py list-backups
```

Backups are stored locally under `BACKUP_ROOT` (default: `backups/`).

## Restore

```bash
python3 infrastructure/database_backup_manager.py restore --backup-name <backup-name>
```

## Health Check

```bash
python3 infrastructure/database_backup_manager.py health-check
```

## Metrics

```bash
python3 infrastructure/database_backup_manager.py metrics
```

## Maintenance

```bash
python3 infrastructure/database_backup_manager.py maintenance
```
