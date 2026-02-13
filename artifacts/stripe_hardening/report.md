# Stripe Billing Center Hardening + Legal Pages

Date: 2026-02-13
Branch: `release/stripe-billing-center`

## A) Changes
- Removed all Stripe “demo billing” fallbacks. Stripe operations now require explicit Stripe configuration via env vars.
- Removed the now-unused `DEMO_BILLING` flag from `.env.example.backend`.
- Added checkout-session idempotency (double-submit protection) backed by a DB table, and wired it into:
  - `POST /api/payments/stripe/create-checkout-session`
  - `POST /api/billing/checkout-session`
- Added idempotency wrappers for subscription mutation endpoints:
  - `POST /api/billing/subscriptions`
  - `PUT /api/billing/subscriptions/{id}/upgrade`
  - `POST /api/billing/subscriptions/{id}/cancel`
  - `POST /api/billing/subscriptions/{id}/reactivate`
- Hardened Stripe webhook processing:
  - Strict signature requirement + strict secret requirement
  - Replay protection via a DB receipt table (`event_id` dedupe)
  - Replayed timestamp rejection via `STRIPE_WEBHOOK_TOLERANCE_SECONDS` (tested)
  - Correct subscription creation from webhook events when the DB record is missing
  - Customer/user mismatch safety checks (ignore mismatched events)
  - Plan upgrades/downgrades follow the Stripe Price ID mapping first (portal-safe)
  - Webhook failures return 5xx so Stripe retries (no silent 200-on-error)
- Website updates:
  - Removed the “Plan” nav concept from authenticated pages and replaced it with a Billing Center (`/billing`).
  - Added Billing Center page with Stripe Checkout + Stripe Portal actions; messaging reinforces “VPN runs in the app”.
  - Added read-only invoice history table on `/billing` (backed by `GET /api/billing/invoices`).
  - Diagnostics page now includes Account Diagnostics (backend reachability + subscription/billing status).
- Legal + policy pages:
  - Added `/data_retention` and `/acceptable_use` pages.
  - Added footer navigation links to all policy pages across the site.
  - Added CI guard `scripts/check_legal_placeholders.sh` and wired it into workflows to fail builds if placeholders remain.
- Logging hardening:
  - Extended log redaction to also mask Stripe secret keys (`sk_test_…`, `sk_live_…`) and webhook secrets (`whsec_…`).

## B) What Reused
- Existing CSRF middleware (`X-CSRF-Token` + cookie) and rate limiting in `main.py`.
- Existing subscription schema (`models/subscription.py`) and user model (`models/user.py`).
- Existing FastAPI error envelope (`api_error`) and typed exceptions (`utils/api_errors.py`).
- Existing Stripe integration plumbing in `services/stripe_service.py` (refactored to be runtime-config driven).

## C) Untouched
- Branding/colors/logos and the overall visual design system (`static/css/web_ui_v1.css`).
- VPN connection control remains in the apps; no web VPN on/off toggle was introduced.
- Hetzner-only assumptions remain unchanged (no Azure references added).
- The VPN API surface and tunnel behavior were not changed as part of billing hardening.

## D) Risks Introduced + Mitigations
- Risk: Misconfigured Stripe env vars (missing Price IDs / webhook secret) cause billing actions to fail.
  - Mitigation: Fail-fast typed errors (`stripe_not_configured`, `stripe_price_not_configured`, `stripe_webhook_not_configured`) and visible diagnostics on `/billing` and `/diagnostics`.
- Risk: Webhook ordering (session vs subscription events) could leave partial state temporarily.
  - Mitigation: Handle both `checkout.session.completed` and `customer.subscription.*` events; subscription records are created/updated idempotently, and replays are deduped.
- Risk: Any webhook handler exception previously returned 200 and prevented Stripe retries.
  - Mitigation: Processing errors now raise and return 5xx; receipts track attempts and last error.
- Risk: Users could accidentally create multiple Stripe Checkout sessions while already subscribed.
  - Mitigation: `POST /api/payments/stripe/create-checkout-session` now rejects when an active subscription exists; users are directed to the portal.

## E) Stripe Env Var Configuration (Test/Live)
Required for Stripe billing to function:
- `STRIPE_SECRET_KEY`
  - Test mode: starts with `sk_test_…`
  - Live mode: starts with `sk_live_…`
- `STRIPE_WEBHOOK_SECRET` (starts with `whsec_…`)
- Price IDs (must be real Stripe Price IDs):
  - `STRIPE_PRICE_BASIC_MONTHLY`, `STRIPE_PRICE_BASIC_YEARLY`
  - `STRIPE_PRICE_PREMIUM_MONTHLY`, `STRIPE_PRICE_PREMIUM_YEARLY` (if using premium)
  - `STRIPE_PRICE_ULTRA_MONTHLY`, `STRIPE_PRICE_ULTRA_YEARLY` (if using ultra)

Optional:
- `STRIPE_WEBHOOK_TOLERANCE_SECONDS` (default: `300`)
- `PAYMENT_IDEMPOTENCY_WINDOW_SECONDS` (default: `60`)
- `PAYMENT_IDEMPOTENCY_STALE_AFTER_SECONDS` (default: `30`)

## F) Local Test Commands + Results
Commands (repo root):
```bash
python3 -m compileall . -q
.venv/bin/pytest -q
.venv/bin/python sandbox/payment_sim/run_payment_sim.py
bash scripts/check_legal_placeholders.sh
.venv/bin/python scripts/generate_openapi.py
```

Notes:
- Running the web server locally:
```bash
.venv/bin/python -m uvicorn main:app --reload
```
Then open:
- `http://127.0.0.1:8000/billing`
- `http://127.0.0.1:8000/dashboard`
- `http://127.0.0.1:8000/vpn`
- `http://127.0.0.1:8000/diagnostics`

Results (in this sandbox on 2026-02-13):
- `python3 -m compileall . -q`: PASS
- `.venv/bin/pytest -q`: `319 passed, 3 skipped` (preview-stack tests skipped: sandbox forbids TCP sockets)
- `.venv/bin/python sandbox/payment_sim/run_payment_sim.py`: PASS; wrote:
  - `artifacts/payment_sim/report.json`
  - `artifacts/payment_sim/summary.csv`
- `bash scripts/check_legal_placeholders.sh`: PASS; wrote:
  - `artifacts/legal_pages/placeholder_free.md`
- `.venv/bin/python scripts/generate_openapi.py`: PASS; updated `docs/openapi/securewave-openapi.json`
- Uvicorn smoke test: NOT runnable in this sandbox (TCP sockets are blocked). Run the command above in a normal local environment.
