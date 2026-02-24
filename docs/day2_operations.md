# SecureWave Day-2 Operations

This runbook is for operators running SecureWave on Hetzner (single-server default). It assumes secrets are configured via environment variables.

## Service Endpoints (Operator)

Health:
- `GET /api/health`
- `GET /api/ready`

Metrics:
- `GET /metrics` (Prometheus plaintext)
- `GET /api/metrics/system` (auth)
- `GET /api/metrics/vpn` (auth)
- `GET /api/vpn/metrics/vpn` (auth; includes handshake staleness + IP pool stats)

## Log Locations

Common locations depend on how you run the backend:

Preview runner (`start_site.sh`):
- PID: `.preview/pids/preview_site.pid`
- Logs: `.preview/logs/preview_site.log`

Systemd (recommended for production):
- Logs: `journalctl -u <unit-name> -n 200 --no-pager`

Nginx:
- Access: `/var/log/nginx/access.log`
- Error: `/var/log/nginx/error.log`

## Common Alerts And Remediation

Handshake failures / stale handshakes rising:
1. Confirm UDP reachability (51820/udp) from the internet.
2. Confirm the VPN server registry is correct:
   - endpoint: `<public_ip>:51820`
   - server public key matches `/etc/wireguard/keys/server_public.key` on the node.
3. Validate the node itself:
   - `sudo wg show`
   - confirm interface is up and listening.

IP pool utilization high:
1. Check `/api/vpn/metrics/vpn` `ip_pool.utilization_pct`.
2. If approaching exhaustion:
   - increase `WG_IP_POOL_MAX_BLOCKS` (policy permitting) or reduce reserved hosts.
   - revoke stale peers where appropriate (don’t mass-revoke legitimate sessions).

CPU/memory high:
1. Confirm `/api/metrics/system` `runtime.system`.
2. If persistent:
   - restart backend with a graceful strategy (blue/green cutover preferred).
   - review recent changes; run benchmark suite to confirm regression.

Stripe webhook failures:
1. Verify `STRIPE_WEBHOOK_SECRET` is set and matches the configured Stripe endpoint.
2. Check webhook receipts table for duplicates/failures (`webhook_event_receipt`).
3. Validate signature tolerance window (`STRIPE_WEBHOOK_TOLERANCE_SECONDS`).

## WireGuard Key Rotation

Peer key rotation (control plane):
- Use the peer manager rotation path (see `services/vpn_peer_manager.py`).
- For server key lifecycle, see `docs/server_key_lifecycle.md`.

Server key changes require re-registering the node public key in the control-plane DB.

## Database Backup And Restore

Backup:
```bash
python3 infrastructure/database_backup_manager.py backup
python3 infrastructure/database_backup_manager.py list-backups
```

Maintenance:
```bash
python3 infrastructure/database_backup_manager.py maintenance
```

Restore drill:
- Follow `infrastructure/disaster_recovery.py` and validate:
  - `/api/ready` returns 200
  - login works
  - `/api/vpn/profile` issues profiles

## ISO/Compliance Checklist (Operational)

Access control:
- SSH keys only (password auth disabled), least privilege for operators.
- Secrets managed outside git (env vars or host secret store).

Auditability:
- Preserve deployment logs and canary reports.
- Record incident timelines and remediation steps.

Data handling:
- Verify data retention policy pages are correct (placeholder guard passes).
- Confirm backups are encrypted and access-controlled.

Change management:
- Deploy from versioned tags.
- Run release preflight and keep artifacts for each deployment.

