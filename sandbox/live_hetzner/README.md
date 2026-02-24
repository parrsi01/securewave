# Live Hetzner Validation (Real WireGuard, No Simulation)

This directory contains operator-run scripts to validate SecureWave against a real Hetzner deployment:

- Bring up a real WireGuard tunnel (Linux + Windows).
- Validate handshake, public IP rotation through the tunnel, and basic DNS leak prevention.
- Record latency (ping) + throughput (bounded download) while the tunnel is up.
- Run basic HTTP/HTTPS smoke checks (IP-based), including SSL certificate probing.
- Validate backend control-plane endpoints: `POST /api/vpn/profile` (via live validation harness) and `/metrics`.
- Run a Stripe activation sanity check without charging real cards by default.
- Generate `artifacts/live_hetzner_smoke_report.md`.

These scripts intentionally do **not** change backend core logic or UI. They assume you have credentials, network access,
and (for tunnel up/down) administrative privileges on the runner machine.

## Quick Start (Linux)

1. Export required env:
   - `LIVE_API_BASE_URL` (example: `https://X.X.X.X` or `https://api.example.com`)
   - Optional for IP-based curls: `HETZNER_IP` (public IPv4)
2. Run:
   - `bash sandbox/live_hetzner/run_live_hetzner_validation_linux.sh`

## Quick Start (Windows)

1. Ensure WireGuard for Windows is installed (`wireguard.exe`, `wg.exe` available in PATH).
2. Set:
   - `$env:LIVE_API_BASE_URL="https://..."` (backend URL)
   - `$env:HETZNER_IP="..."` (optional, for IP-based smoke curls)
3. Run:
   - `powershell -NoProfile -ExecutionPolicy Bypass -File sandbox/live_hetzner/run_live_hetzner_validation_windows.ps1`

## Environment Variables

Common:
- `LIVE_API_BASE_URL` (required): backend base URL.
- `HETZNER_IP` (optional): public IPv4 for `curl http(s)://<ip>`.
- `LIVE_VALIDATION_USERS` (default `3`): number of tunnel bring-up attempts.
- `LIVE_ALLOWED_DNS` (default `94.140.14.14,94.140.15.15,1.1.1.1`): allowed resolvers (nameserver list).
- `LIVE_VALIDATION_SERVER_ID` (optional): request a specific VPN server id for `/api/vpn/profile`.

Stripe:
- `STRIPE_SMOKE_MODE` (default `test`): `test` or `live`.
- `ALLOW_LIVE_STRIPE_ACTIONS` (default `false`): must be `true` to do any *live* mutations.
- `STRIPE_WEBHOOK_SECRET` (optional): if set, the smoke script can send a locally-signed webhook event to
  `POST /api/billing/webhooks/stripe` to validate signature verification and handler execution.

## Notes / Safety

- Linux tunnel up/down uses `wg-quick`. You will usually need to run the script with sudo, or configure passwordless sudo
  for `wg-quick`.
- The webhook smoke check is **disabled for live mode** unless `ALLOW_LIVE_STRIPE_ACTIONS=true`.
- If the backend is configured for live Stripe keys, the script will refuse to create checkout sessions by default.

## HTTPS Setup (On Hetzner Host)

- Wrapper around `setup_preview.sh`:
  - `sudo bash sandbox/live_hetzner/https/setup_nginx_https.sh --host api.example.com --email ops@example.com --ssl-mode letsencrypt`
  - `sudo bash sandbox/live_hetzner/https/setup_nginx_https.sh --ssl-mode selfsigned`

## Alerting Checks

- Live alert probe + optional notifications:
  - `bash sandbox/live_hetzner/alerting/run_alert_checks.sh`
  - Configure auth: `ALERT_API_TOKEN` or `ALERT_API_EMAIL`/`ALERT_API_PASSWORD`
  - Configure email: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `ALERT_EMAIL_TO`
  - Configure webhook: `NOTIFY_WEBHOOK_URL`
