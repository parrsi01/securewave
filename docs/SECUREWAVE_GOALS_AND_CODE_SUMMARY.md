# SecureWave Goals And Code Summary

## What SecureWave Is

SecureWave is a VPN platform with a Python business backend and a Go privileged networking daemon. The Python side manages authentication, subscriptions, server selection, diagnostics, traffic control, and VPN orchestration. The Go side owns privileged Linux networking mutations over a Unix domain socket boundary. The current project docs describe a Hetzner-first, single-server deployment model with WireGuard-focused firewall defaults and an API served by FastAPI.

Primary entrypoint:
- `main.py` starts the FastAPI app, configures middleware, security headers, rate limiting, startup checks, route registration, and operational bootstrap.

## Core Product Goals

1. Provide a secure VPN service with strong runtime safeguards.
   The code emphasizes secret redaction, strict security headers, token revocation, CSRF protection, environment validation, and permission-policy checks.
2. Support real VPN operations across multiple protocols.
   The backend contains protocol-specific services for WireGuard, OpenVPN, and IKEv2, plus routing, firewall, and traffic-shaping helpers.
3. Manage user identity, device access, and subscriptions.
   The app includes authentication flows, refresh-token handling, user/device routes, subscription services, Stripe and PayPal integrations, and invoice/payment tracking models.
4. Measure VPN quality and optimize server choice.
   The code tracks connections, RTT samples, VPN metrics, health signals, optimizer logic, and recommendation/ranking services.
5. Support operations, monitoring, and diagnostics.
   The project includes runtime metrics, health monitoring, uptime checks, security monitoring, diagnostics routes, and extensive deployment or verification scripts.

## Backend Architecture

The backend is organized in layers:

- `main.py`
  Application bootstrap, middleware, startup and shutdown behavior, and API assembly.
- `routes/` and `routers/`
  FastAPI endpoints for auth, billing, devices, VPN actions, diagnostics, dashboards, payments, admin, and security.
- `services/`
  Core business logic such as JWT handling, subscription control, VPN credential lifecycle, server ranking, monitoring, optimizer logic, and provider integrations.
- `backend/services/`
  Lower-level VPN stack management for WireGuard, OpenVPN, IKEv2, firewall rules, routing, traffic management, and shaping.
- `netopsd/`
  Go privileged daemon that listens on a Unix socket and executes allowlisted networking operations such as WireGuard interface lifecycle, route changes, NAT setup, and VPN-owned cleanup.
- `models/`
  SQLAlchemy models for users, subscriptions, VPN servers, credentials, connections, metrics, tokens, audit trails, invoices, and webhook receipts.
- `auth/`
  Token creation, token revocation, and refresh-token workflows.
- `config/`
  Security configuration and app settings.
- `database/`
  Base metadata and database session wiring.
- `utils/`
  Shared helpers for errors, structured logging, environment validation, time handling, input safety, and password policy.

## Package Inventory

App-owned backend Python scope documented so far:

- `main.py`: 1 entrypoint file
- `auth/`: 4 files
- `config/`: 3 files
- `database/`: 3 files
- `models/`: 20 files
- `routers/`: 8 files
- `routes/`: 12 files
- `services/`: 44 files
- `backend/services/`: 8 files

Total documented backend Python files: 103

## Major Code Areas

### Security And Access Control

- Request hardening in `main.py` includes gzip, rate limiting, CSP, HSTS, frame blocking, request IDs, revoked-token enforcement, and CSRF enforcement.
- `auth/` and `services/jwt_service.py` handle token issuance, validation, refresh flows, and blacklist or revocation support.
- `config/security_config.py`, `utils/env_validation.py`, and `utils/structured_logging.py` enforce secure defaults, required secrets, and redacted logs.
- Models such as `jwt_blacklist_token`, `auth_refresh_token`, `used_totp_code`, and `audit_log` support security state and traceability.

### VPN Operation

- `routes/vpn.py`, `routes/servers.py`, `routes/vpn_metrics.py`, and `routes/vpn_tests.py` expose the user-facing VPN APIs.
- `services/vpn_credential_service.py`, `services/vpn_peer_manager.py`, `services/vpn_server_service.py`, `services/vpn_server_key_lifecycle.py`, and `services/tunnel_runtime.py` manage credentials, peers, and tunnel runtime rules.
- `backend/services/wireguard_service.py`, `backend/services/openvpn_service.py`, and `backend/services/ikev2_service.py` implement protocol-specific behavior.
- `backend/services/privileged_network_service.py` and `services/privileged_netops_client.py` provide the Python-to-Go boundary for privileged operations.
- `backend/services/firewall_manager.py`, `backend/services/routing_manager.py`, `backend/services/traffic_manager.py`, and `backend/services/traffic_shaper.py` manage packet flow and shaping.

### Billing And Product Access

- `routes/billing.py`, `routers/payment_stripe.py`, and `routers/payment_paypal.py` expose billing APIs.
- `services/stripe_service.py`, `services/paypal_service.py`, `services/payment_webhooks.py`, `services/payment_idempotency.py`, and `services/subscription_service.py` coordinate checkout, webhook processing, subscription state, and access control.
- `models/subscription.py`, `models/invoice.py`, `models/payment_idempotency_key.py`, and `models/webhook_event_receipt.py` persist billing state safely.

### Monitoring, Metrics, And Optimization

- `services/runtime_metrics.py`, `services/performance_monitor.py`, `services/uptime_monitor.py`, `services/vpn_health_monitor.py`, and `services/security_monitor.py` track system health.
- `models/vpn_metric.py`, `models/vpn_server_rtt_sample.py`, and `models/vpn_connection.py` store performance and connection telemetry.
- `services/server_ranker.py`, `services/latency_optimizer.py`, `services/geo_recommendation.py`, `services/vpn_optimizer.py`, `services/xgb_qos.py`, and `services/xgb_risk.py` support server selection and quality scoring.

### User, Device, And Support Features

- `routes/auth.py`, `routes/user.py`, and `routes/devices.py` manage account and device workflows.
- `models/user.py`, `models/vpn_credential.py`, and `models/wireguard_peer.py` hold identity-to-device-to-tunnel relationships.
- `routers/contact.py`, `models/support_ticket.py`, and email services provide contact and notification support.

## Data Model Summary

The database layer centers on these entity groups:

- Identity: users, refresh tokens, blacklisted JWTs, used TOTP codes
- Commercial state: subscriptions, invoices, payment idempotency keys, webhook receipts
- VPN infrastructure: VPN servers, WireGuard peers, VPN credentials
- Telemetry: VPN connections, RTT samples, metrics, usage analytics
- Compliance and auditability: audit logs, GDPR requests, email logs, support tickets

## Deployment And Operations Summary

- Local development is started through `deploy.sh local` according to `QUICK_START.md`.
- The status docs describe a Hetzner-only single-server deployment with SSH and WireGuard firewall defaults.
- The repository also contains extensive operational scripts under `scripts/`, infrastructure code under `infrastructure/` and `infra/`, and monitoring or validation assets for production readiness.

## Where To Read More

- File-by-file backend walkthroughs: `docs/code-explanations/README.md`
- Example detailed entrypoint walkthrough: `docs/code-explanations/main.md`
- Quick start: `QUICK_START.md`
- Current deployment status summary: `PROJECT_STATUS_2026-02-03.md`

## Scope Note

This summary focuses on the app-owned Python backend because that is the currently documented code path. The repository also includes frontend, static, mobile, infrastructure, testing, and operational assets that can be summarized in a second pass if needed.
