# SecureWave 30-Day Launch Plan

This plan assumes:
- Infrastructure is Hetzner (single-server default per policy).
- WireGuard node(s) are provisioned and registered in the control plane DB.
- Secrets are provided via environment variables (no secrets in git).

## Goals

- Ship a stable, observable VPN service with clear rollback paths.
- Validate real network behavior (WireGuard tunnel, DNS leak posture, latency/throughput).
- Enable billing in Stripe live mode with replay protection and idempotent writes.
- Establish day-2 operations and incident response muscle memory.

## Pre-Launch Checklist (Must Pass Before Day 1)

Infrastructure and access:
- [ ] Hetzner host provisioned via Terraform (`scripts/release_hetzner.sh apply`)
- [ ] Host bootstrap complete (`scripts/hetzner_bootstrap.sh`)
- [ ] WireGuard installed and enabled (`infrastructure/wireguard_vm_setup.sh`)
- [ ] Firewall rules verified (22/tcp, 51820/udp; 80/443 only when intended)
- [ ] Admin SSH access verified for `securewave@<host>`

Backend essentials:
- [ ] `ENVIRONMENT=production`
- [ ] `TESTING` is not enabled
- [ ] `DATABASE_URL` points to production PostgreSQL (not SQLite)
- [ ] Alembic migrations applied (`alembic upgrade head`)
- [ ] `/api/ready` returns 200 on the host
- [ ] `/metrics` returns Prometheus plaintext

WireGuard control-plane integration:
- [ ] VPN servers registered in DB (`infrastructure/hetzner/sync_vpn_servers.py --fetch-wg-public-key`)
- [ ] `WG_AUTO_REGISTER_PEERS=true` set only when SSH/API management is configured

Stripe go-live:
- [ ] Live products/prices created; all `STRIPE_PRICE_*` values are live-mode price ids
- [ ] `STRIPE_SECRET_KEY=sk_live_...`
- [ ] Live webhook endpoint configured; `STRIPE_WEBHOOK_SECRET=whsec_...`
- [ ] Webhook replay protection and idempotency tests pass (`tests/integration/test_stripe_hardening.py`)

## Live Traffic Forecast (30 Days)

Assumptions (adjust to reality):
- Week 1: 50-200 beta users
- Week 2: 200-800 users
- Week 3: 800-2,000 users
- Week 4: 2,000-5,000 users

Expected load drivers:
- Login bursts after announcements
- Profile fetch spikes after app updates
- Periodic tunnel reconnects (mobile backgrounding, WiFi/cellular transitions)

## Expected KPIs (What “Good” Looks Like)

Availability:
- `/api/health` >= 99.9%
- `/api/ready` >= 99.9%

Latency:
- `/api/vpn/profile` P95 under 4s (baseline depends on DB and peer registration path)
- Handshake latency P95 under 2.5s in live validation suite

Network posture:
- DNS leak rate: 0 in live validation checks (allowlist enforced)
- Kill-switch behavior validated in leak suite

Billing:
- Webhook success rate: ~100% (reject invalid signatures; process valid)
- No duplicate subscriptions from replayed events (dedupe receipts)

## Hazard Signals And Mitigations

Handshake failures increase:
- Signal:
  - Live validation fails handshake or stale handshakes percent rises
- Mitigation:
  - Validate WireGuard UDP reachability (51820/udp)
  - Verify server key + endpoint match DB registry
  - Check MTU and routing rules; re-run leak suite

Profile issuance latency spikes:
- Signal:
  - `securewave_profile_issue_latency_p95_ms` increases
- Mitigation:
  - Check DB connection health and slow queries
  - Verify peer registration method (SSH/API) is responsive

Memory/FD growth:
- Signal:
  - `/api/metrics/system` shows growing `process_memory_mb` or `process_open_fds`
- Mitigation:
  - Restart backend with graceful strategy; capture metrics before/after
  - Run leak suite and compare artifacts

Stripe webhook failures:
- Signal:
  - Webhook 400 spikes or receipts show failures
- Mitigation:
  - Verify `STRIPE_WEBHOOK_SECRET` and Stripe endpoint URL
  - Inspect duplicate receipts and signature tolerance settings

## Rollout Plan (Week By Week)

Days 1-3 (Staging hardening):
- Run full local validation: tests + benchmark + leak + chaos suites
- Provision Hetzner host and register VPN server(s)
- Configure HTTPS (nip.io/sslip.io preview or real domain)

Days 4-7 (Beta canary):
- Run real live WireGuard validation on Linux runner (`dev_tools/sandbox/live_validation/run_live_validation.sh`)
- Run alert checks against the deployed backend (`sandbox/live_hetzner/alerting/check_alerts.py`)
- Enable small beta cohort and watch metrics

Days 8-14 (Scale readiness):
- Increase worker counts and validate resource envelope
- Establish regular backups and restore drills
- Validate Stripe flows end-to-end (test mode + live mode in controlled window)

Days 15-21 (Operational maturity):
- Document and rehearse incident response
- Validate key rotation and server registry sync procedures
- Tighten thresholds/gates only after stable baselines

Days 22-30 (Launch):
- Run final preflight (`scripts/release_preflight.sh`)
- Execute canary deploy procedure (see `scripts/ops/canary_deploy.sh`)
- Monitor closely for 72 hours; keep rollback artifacts

## Stakeholder Readiness

- Engineering: on-call rota and escalation paths defined
- Support: beta onboarding guide + issue triage tags
- Legal/Compliance: privacy/terms/data-retention pages verified (placeholder guard passes)
- Finance: Stripe live mode configured and reconciliation process defined

