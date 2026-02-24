# SecureWave Beta User Onboarding

This guide is for onboarding beta users while collecting actionable posture signals without exposing secrets.

## Beta Goals

- Validate real-world network behavior across ISPs and device types.
- Identify onboarding friction (login, profile provisioning, tunnel setup).
- Confirm DNS leak posture and expected IP rotation through the tunnel.
- Validate premium/free tier isolation and server selection behavior.

## Beta User Checklist

Account and device:
- [ ] Create account and verify login works.
- [ ] Create a device profile (`/api/vpn/profile`) via the app.
- [ ] Confirm tunnel connects and remains stable across WiFi/cellular changes (mobile).

Privacy / posture:
- [ ] Confirm public IP changes when tunnel is up.
- [ ] Run a DNS leak check (expect only secure resolvers from the profile).

Supportability:
- [ ] Capture and share the following when reporting issues:
  - timestamp (UTC)
  - device type + OS version
  - approximate location/region
  - whether the failure is repeatable
  - sanitized logs (no private keys)

## Posture Signals (What We Track)

Control plane:
- Profile issuance latency distribution (P50/P95).
- Auth failure rate and rate-limit hits.
- Peer churn rate (connect/disconnect events).

Network:
- Handshake completion success rate.
- DNS leak rate (expected: 0).
- Throughput and ping baselines by region.

Billing:
- Subscription state transitions driven by webhooks.
- Webhook dedupe and replay protection integrity.

## Triage Categories (Suggested)

- `beta-onboarding`: can’t sign up/login, confusing flow, missing instructions
- `tunnel-connect`: handshake fails, tunnel won’t come up
- `dns-leak`: DNS servers outside allowlist observed
- `performance`: high latency, low throughput, unstable reconnect behavior
- `tier-isolation`: free user can reach premium server or premium UX mismatch
- `billing`: checkout issues, subscription state incorrect, portal issues

## Operator Tools

Live network validation (Linux runner):
- `dev_tools/sandbox/live_validation/run_live_validation.sh`

Hetzner live smoke bundle:
- `sandbox/live_hetzner/run_live_hetzner_validation_linux.sh`

Alert probe:
- `sandbox/live_hetzner/alerting/check_alerts.py`

