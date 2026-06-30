# Billing Production Readiness Report - 2026-06-30

## Final status

SecureWave billing is now code-ready for Stripe subscription production flow,
but not live-payment-proven on this workstation. The code path is aligned to
Stripe Billing with hosted Checkout for subscription signup, Customer Portal for
self-service billing management, and verified webhooks for local subscription
state changes.

## What is proven

- Production mode no longer falls back to demo subscriptions when Stripe is
  missing or incomplete. It returns a clear `503` instead.
- `/api/billing/subscriptions` returns a Stripe Checkout Session URL in real
  Stripe mode instead of marking a subscription active before payment.
- Checkout Sessions include SecureWave user, plan, and billing-cycle metadata,
  and local subscription rows are created/synced only from verified Stripe
  webhook events.
- `checkout.session.completed` and `customer.subscription.created` webhook paths
  can create or update local subscription state from Stripe subscription data.
- Stripe config is read from the current environment, including
  `STRIPE_SECRET_KEY` with legacy `STRIPE_SECRET` fallback and all Stripe Price
  IDs.
- Billing release validation now checks live-mode Stripe secret/publishable
  keys, webhook signing secret, all paid plan Price IDs, `PAYMENTS_MOCK=false`,
  `DEMO_BILLING=false`, and `STRIPE_PORTAL_CONFIG_ID`.
- `scripts/billing_release_gate.sh` validates an ignored private billing env
  file without committing secrets.
- `scripts/stripe_billing_provision.py` can create or reuse live Stripe
  Products, recurring Prices, the webhook endpoint, and Customer Portal
  configuration, then write `securewave_private/billing_release.env` without
  committing secrets.

## Externally blocked

Live payment proof is blocked until production Stripe resources are created and
configured:

- live Stripe secret key
- live publishable key
- webhook signing secret for the deployed webhook endpoint
- live recurring Prices for Basic, Premium, and Ultra monthly/yearly plans
- Stripe Customer Portal configuration ID (`bpc_...`)
- webhook signing secret copied manually if the webhook endpoint already
  existed, because Stripe only returns that secret when the endpoint is created

No fake live Stripe call or fake successful charge was added.

## Required env vars

```bash
PAYMENTS_MOCK=false
DEMO_BILLING=false
PAYMENT_PROVIDER=stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_API_VERSION=2026-02-25.clover
STRIPE_PRICE_BASIC_MONTHLY=price_...
STRIPE_PRICE_BASIC_YEARLY=price_...
STRIPE_PRICE_PREMIUM_MONTHLY=price_...
STRIPE_PRICE_PREMIUM_YEARLY=price_...
STRIPE_PRICE_ULTRA_MONTHLY=price_...
STRIPE_PRICE_ULTRA_YEARLY=price_...
STRIPE_PORTAL_CONFIG_ID=bpc_...
STRIPE_AUTOMATIC_TAX=false
```

Use:

```bash
export STRIPE_SECRET_KEY="sk_live_..."
export STRIPE_PUBLISHABLE_KEY="pk_live_..."
export APP_URL="https://securewaveapp.com"
python scripts/stripe_billing_provision.py --confirm-live
bash scripts/billing_release_gate.sh --env-file securewave_private/billing_release.env
```

If the webhook already exists and the provisioner warns that
`STRIPE_WEBHOOK_SECRET` cannot be read, copy the endpoint signing secret from
Stripe Dashboard into `securewave_private/billing_release.env`, then rerun the
gate.

For the full release gate, combine this env with the SMTP/Fernet release env and
run:

```bash
bash scripts/billing_release_gate.sh \
  --env-file securewave_private/billing_release.env \
  --release-preflight \
  --dry-run-tag
```

## Validation performed

- `.venv/bin/python -m pytest tests/unit/test_stripe_billing_provisioning.py tests/unit/test_billing_production_readiness.py tests/unit/test_env_validation.py tests/unit/test_release_preflight_email.py tests/unit/test_devops_contract.py -q`
  - `54 passed`
- `.venv/bin/python -m pytest -q`
  - `356 passed`
- `python3 -m py_compile services/stripe_provisioning.py services/stripe_service.py utils/env_validation.py scripts/stripe_billing_provision.py`
  - passed
- `bash scripts/billing_release_gate.sh --env-file <temporary-complete-env>`
  - passed with `stripe missing: none` and `release missing: none`
- `git diff --check`
  - passed

## Remaining release risk

- Stripe live objects and webhook endpoint must be configured in Stripe before
  live payment proof. The new provisioner automates creation/reuse, but it still
  needs live Stripe keys.
- Customer Portal settings are now explicit through `STRIPE_PORTAL_CONFIG_ID`.
- Taxes are not forced on by code. Set `STRIPE_AUTOMATIC_TAX=true` only after
  Stripe Tax/automatic tax is configured for the account.
- A live proof should create a real Checkout Session, complete payment with a
  controlled account/card, receive verified Stripe webhooks, confirm local
  subscription activation, open Customer Portal, then cancel/refund according to
  the release test plan.
