# Live Hetzner Validation (Real WireGuard, No Simulation)

This directory contains operator-run scripts to validate SecureWave against a real Hetzner deployment:

- Bring up a real WireGuard tunnel (Linux + Windows).
- Validate handshake, public IP rotation through the tunnel, and basic DNS leak prevention.
- Preserve the SecureWave API control-plane route while the tunnel is active.
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
   - Optional stability loop against an existing profile:
     `sudo bash scripts/vpn_stability_test.sh --api-base-url https://<host>/api --profile /path/to/profile.conf --split-tunnel`

## Quick Start (Windows)

1. Ensure WireGuard for Windows is installed (`wireguard.exe`, `wg.exe` available in PATH).
2. Set:
   - `$env:LIVE_API_BASE_URL="https://..."` (backend URL)
   - `$env:HETZNER_IP="..."` (optional, for IP-based smoke curls)
3. Run:
   - `powershell -NoProfile -ExecutionPolicy Bypass -File sandbox/live_hetzner/run_live_hetzner_validation_windows.ps1`
4. Optional profile rendering for WireGuard Desktop / import-based checks:
   - `python dev_tools/sandbox/live_validation/render_test_wireguard_config.py --input <profile.conf> --output <temp.conf> --api-base-url https://<host> --split-tunnel`

## Quick Start (macOS)

1. Render a temporary validation profile:
   - `python3 dev_tools/sandbox/live_validation/render_test_wireguard_config.py --input <profile.conf> --output /tmp/securewave-test.conf --api-base-url https://<host> --split-tunnel`
2. Import `/tmp/securewave-test.conf` into WireGuard Desktop.
3. Validate handshake, DNS, and API reachability while the tunnel is active.

## Environment Variables

Common:
- `LIVE_API_BASE_URL` (required): backend base URL.
- `HETZNER_IP` (optional): public IPv4 for `curl http(s)://<ip>`.
- `LIVE_VALIDATION_USERS` (default `3`): number of tunnel bring-up attempts.
- `LIVE_ALLOWED_DNS` (default `94.140.14.14,94.140.15.15,1.1.1.1`): allowed resolvers (nameserver list).
- `LIVE_VALIDATION_SERVER_ID` (optional): request a specific VPN server id for `/api/vpn/profile`.
- `LIVE_TEST_SPLIT_TUNNEL` (optional): set `true` to replace full-tunnel `AllowedIPs` in the temporary validation profile.
- `LIVE_TEST_ALLOWED_IPS` (optional): comma-separated split-tunnel CIDRs; default `10.0.0.0/8,172.16.0.0/12`.

Stripe:
- `STRIPE_SMOKE_MODE` (default `test`): `test` or `live`.
- `ALLOW_LIVE_STRIPE_ACTIONS` (default `false`): must be `true` to do any *live* mutations.
- `STRIPE_WEBHOOK_SECRET` (optional): if set, the smoke script can send a locally-signed webhook event to
  `POST /api/billing/webhooks/stripe` to validate signature verification and handler execution.

## Notes / Safety

- Linux tunnel up/down uses `wg-quick`. You will usually need to run the script with sudo, or configure passwordless sudo
  for `wg-quick`.
- Linux live validation rewrites only the temporary test profile. Backend-issued production configs are not modified.
- The webhook smoke check is **disabled for live mode** unless `ALLOW_LIVE_STRIPE_ACTIONS=true`.
- If the backend is configured for live Stripe keys, the script will refuse to create checkout sessions by default.

## HTTPS Setup (On Hetzner Host)

- Wrapper around the production TLS script:
  - `sudo bash sandbox/live_hetzner/https/setup_nginx_https.sh --domain securewave.app --domain www.securewave.app --email ops@example.com`

## Alerting Checks

- Live alert probe + optional notifications:
  - `bash sandbox/live_hetzner/alerting/run_alert_checks.sh`
  - Configure auth: `ALERT_API_TOKEN` or `ALERT_API_EMAIL`/`ALERT_API_PASSWORD`
  - Configure email: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`, `ALERT_EMAIL_TO`
  - Configure webhook: `NOTIFY_WEBHOOK_URL`
