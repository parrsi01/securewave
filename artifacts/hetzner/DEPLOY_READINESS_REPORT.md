# Deploy Readiness Report (Hetzner)

Date: 2026-02-11

## Provider Policy

- Supported provider: **Hetzner Cloud only**
- Azure: **forbidden / removed**
- Default provisioning policy:
  - `cx33` only
  - single server unless explicitly overridden
  - Ubuntu LTS images only

## Current Status

### Control Plane (Backend)

- Issues WireGuard profiles via `POST /api/vpn/profile`.
- Demo/mock modes are enforced by env flags; production requires explicit `DEMO_MODE=false` and `WG_MOCK_MODE=false`.
- Peer auto-registration is supported (SSH or HTTP API), and can be disabled via `WG_AUTO_REGISTER_PEERS=false`.

### Server Registry (vpn_servers)

- Backend selects servers from DB; demo servers are excluded in non-demo/non-mock environments.
- New sync tool to register Hetzner servers from Terraform outputs:
  - `infrastructure/hetzner/sync_vpn_servers.py`

### Infra (Hetzner)

- Terraform module: `infrastructure/hetzner/`
  - Validates `cx33` and scaling guardrails.
- Host bootstrap/hardening:
  - `scripts/hetzner_bootstrap.sh`
- WireGuard server setup:
  - `infrastructure/wireguard_vm_setup.sh`

## Verification Performed (Local, Non-Cloud)

- Full local simulation suite:
  - `sandbox/realism/run_full_simulation.sh`
  - Stores output under `artifacts/sim_tests/<ts>/`
- Real-mode structure validation (no live traffic):
  - `pytest -q tests_real`

## Remaining Steps Before Go-Live

1. Provision the Hetzner server (Terraform apply) and harden it (bootstrap script).
2. Install/configure WireGuard on the server and retrieve the server public key.
3. Register the server in the SecureWave DB via:
   - `python3 infrastructure/hetzner/sync_vpn_servers.py --fetch-wg-public-key`
4. Configure production environment explicitly:
   - `ENVIRONMENT=production`
   - `DEMO_MODE=false`
   - `WG_MOCK_MODE=false`
   - Set encryption + JWT secrets (`AUTH_ENCRYPTION_KEY`, `WG_ENCRYPTION_KEY`, `ACCESS_TOKEN_SECRET`, `REFRESH_TOKEN_SECRET`)
5. Decide whether to enable peer auto-registration:
   - If enabled: configure SSH or management API credentials intentionally.
   - If disabled: keep `WG_AUTO_REGISTER_PEERS=false` and manage peers operationally.

## Stop Condition

Real VPN path is validated (profile structure, server registry wiring, demo/mock gating), but live traffic enablement is intentionally a manual operational step.

