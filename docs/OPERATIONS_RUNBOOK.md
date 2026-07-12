## Operations Runbook

### Daily Checks
1. Health endpoint: `/api/health`
2. Ready endpoint: `/api/ready`
3. Admin server health check: `/api/admin/servers/{server_id}/health-check`
4. Background workers: watch logs for "VPN Health Monitor started" and "Policy Engine Worker started"

### Common Maintenance
1. Reseed production server after restart:
   - `infrastructure/init_production_server.py` or `/api/admin/servers`
2. Rotate secrets:
   - `ACCESS_TOKEN_SECRET`, `REFRESH_TOKEN_SECRET`, `WG_ENCRYPTION_KEY`
3. Update runtime environment settings:
   - `WG_MOCK_MODE=false`, `DEMO_MODE=false`, `WG_AUTO_REGISTER_PEERS=true`
   - Omitted demo/mock flags default to real control-plane behavior; set them
     to `true` only in explicitly isolated tests.
4. Database storage:
   - Set `DATABASE_URL` to managed Postgres before production traffic.
   - If using SQLite in demo: use an explicitly configured persistent path.

### Incident Triage
1. App boot issues:
   - Check process and container logs for missing dependencies.
2. VPN allocation errors:
   - Verify server is registered and health check is green.
3. Peer registration failures:
   - Confirm SSH key path and VM connectivity.

### Data Persistence
1. Move DATABASE_URL to managed DB before production.
2. SQLite backup (demo only):
   - Copy `/home/site/securewave.db` to a safe location.
3. Postgres backup (production):
   - Use `pg_dump` with daily backups and weekly retention.
4. Restore test:
   - Restore a backup to a staging app monthly.

### Deploy and Rollback
1. Deploy: follow `docs/HETZNER_RUNBOOK.md`.
2. Rollback (fast): redeploy the previous known-good container or service revision.
3. Rollback (safe): restore the previous host/application snapshot and database backup.

### Monitoring
1. Stream application and systemd/container logs during deploys.
2. Alert on:
   - HTTP 5xx rate spikes
   - /health failures
   - VPN allocation errors
