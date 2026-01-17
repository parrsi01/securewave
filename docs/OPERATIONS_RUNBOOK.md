## Operations Runbook

### Daily Checks
1. Health endpoint: `/api/health`
2. Ready endpoint: `/api/ready`
3. Admin server health check: `/api/admin/servers/{server_id}/health-check`

### Common Maintenance
1. Reseed production server after restart:
   - `infrastructure/init_production_server.py` or `/api/admin/servers`
2. Rotate secrets:
   - `ACCESS_TOKEN_SECRET`, `REFRESH_TOKEN_SECRET`, `WG_ENCRYPTION_KEY`
3. Update App Service settings:
   - `WG_MOCK_MODE=false`, `DEMO_MODE=false`, `WG_AUTO_REGISTER_PEERS=true`

### Incident Triage
1. App boot issues:
   - Check App Service logs for missing dependencies.
2. VPN allocation errors:
   - Verify server is registered and health check is green.
3. Peer registration failures:
   - Confirm SSH key path and VM connectivity.

### Data Persistence
1. Move DATABASE_URL to managed DB before production.
2. Backups should be daily with weekly retention.

