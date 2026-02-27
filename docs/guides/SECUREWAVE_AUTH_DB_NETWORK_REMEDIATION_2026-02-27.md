# SecureWave Auth/DB + Network Remediation Report (2026-02-27)

## Scope executed
- Fixed sign-in UI auth-state handling and backend error parsing.
- Created/verified test accounts for deterministic app login testing.
- Added one-click dev account autofill in login screen (from `.env`).
- Added transient network retry on auth login/register requests.
- Validated backend DB/auth flow and server port/runtime health.

## Backend + DB verification

### Service + DB wiring
- `securewave.service`: active
- Environment on server:
  - `ENVIRONMENT=development`
  - `DATABASE_URL=postgresql+psycopg2://postgres:postgres@127.0.0.1:5432/securewave`

### End-to-end auth checks (server-local API)
Executed against `http://127.0.0.1/api` on Hetzner host:
- `POST /api/auth/login` -> 200
- `GET /api/auth/me` -> 200
- `POST /api/auth/logout` -> 200

Validated accounts:
- `simonparris2@gmail.com`
- `qa_free_1@example.com`
- `qa_premium_1@example.com`
- `qa_admin_1@example.com`

Password used for test accounts:
- `SecureWave123`

## Network/ports verification (Hetzner host)

### Forwarding + NAT
- `net.ipv4.ip_forward = 1`
- NAT rules present:
  - `-A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE`
  - `-A POSTROUTING -s 10.9.0.0/24 -o eth0 -j MASQUERADE`
  - `-A POSTROUTING -s 10.10.0.0/24 -o eth0 -j MASQUERADE`

### Listening services/ports observed
- TCP:
  - `:80` (nginx)
  - `127.0.0.1:8080` (gunicorn)
  - `127.0.0.1:5432` (postgres)
- UDP:
  - `:51820` (WireGuard)
  - `:1194` (OpenVPN)
  - `:500`, `:4500` (strongSwan/IKEv2)

## Client-side changes applied

### Sign-in reliability + UX
- Login now redirects only when session is authenticated.
- Auth error banners now parse backend wrapped errors (`error.message`) and validation lists.
- Auth requests (`/auth/login`, `/auth/register`) retry transient network failures (bounded retry/backoff).

### One-click autofill/test sign-in
- Added dev account parsing from `.env`.
- Login screen now shows **Quick test accounts** chips.
- Clicking a chip fills credentials and submits sign-in.

Configured in `securewave_app/.env`:
- `SECUREWAVE_ENABLE_DEV_LOGIN_ACCOUNTS=true`
- `SECUREWAVE_DEV_LOGIN_*` (4 test accounts configured)

## Files changed for this remediation pass
- `securewave_app/lib/core/config/app_config.dart`
- `securewave_app/lib/features/auth/login_page.dart`
- `securewave_app/lib/services/api_client.dart`
- `securewave_app/lib/core/utils/api_error.dart`
- `securewave_app/lib/features/auth/auth_controller.dart`
- `securewave_app/test/api_error_test.dart`
- `securewave_app/test/auth_controller_test.dart`
- `securewave_app/test/state_machine/state_machine_test_harness.dart`
- `securewave_app/test/api_client_fallback_test.dart`
- `securewave_app/test/widget_test.dart`
- `securewave_app/test/performance/multiprotocol_performance_profile_test.dart`
- `securewave_app/test/vpn_service_provider_test.dart`
- `securewave_app/.env`

## Validation commands run
- `flutter test test/auth_controller_test.dart`
- `flutter test test/api_error_test.dart`
- `flutter test test/api_client_fallback_test.dart test/api_error_test.dart test/auth_controller_test.dart test/vpn_service_provider_test.dart test/widget_test.dart`
- `flutter analyze lib/services/api_client.dart lib/features/auth/login_page.dart lib/core/config/app_config.dart`
- Backend auth verification script over SSH (login/me/logout for all 4 accounts)
- Server runtime checks: `sysctl`, `iptables -t nat -S`, `ss -lntup`, `ss -lun`

## Noted exception during ops validation script
- `scripts/ops/validate_vpn_node_baseline.sh` could not complete from this client sandbox due DNS/network restrictions in the local execution environment (`httpx.ConnectError` on Hetzner API resolution).
- Manual server-side baseline checks above were completed and passed for routing/NAT/port bindings.
