# Operations Runbook

## Daily Checks

- `curl http://localhost:8080/api/health` (run on the host)
- Review logs via Docker or systemd

## Backups

```bash
python3 infrastructure/database_backup_manager.py backup
python3 infrastructure/database_backup_manager.py list-backups
```

## Maintenance

```bash
python3 infrastructure/database_backup_manager.py maintenance
```

## Reprovision Host

1. Run Terraform in `infrastructure/hetzner/`.
2. Bootstrap with `scripts/hetzner_bootstrap.sh`.
3. Restore database and redeploy services.

## Firewall

Default firewall allows SSH and WireGuard only. To allow HTTP/HTTPS, set `allow_http_https = true` and re-apply Terraform.
