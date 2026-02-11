# Monitoring and Compliance Implementation

## Monitoring

- Application logs to stdout (Docker/systemd)
- Basic health checks via `/api/health`
- Uptime checks via `services/uptime_monitor.py`

## Compliance

- Secrets via environment variables only
- Host hardening via `scripts/hetzner_bootstrap.sh`

## Next Steps (Optional)

- Add external uptime checks
- Ship logs to a central aggregator when approved
