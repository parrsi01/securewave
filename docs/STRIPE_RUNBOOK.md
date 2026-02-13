# Stripe Integration Runbook

## Overview

SecureWave uses Stripe for subscription billing. The integration supports:
- Checkout Sessions (hosted payment page — recommended)
- Direct subscription creation (for mobile/embedded flows)
- Customer billing portal (self-service)
- Webhook event processing

## Architecture

```
User -> POST /api/billing/checkout-session -> Stripe Checkout URL
         |
         v
Stripe hosted page -> payment -> webhook -> POST /api/billing/webhooks/stripe
                                              |
                                              v
                                    PaymentWebhookHandler -> DB update
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `STRIPE_SECRET_KEY` | Yes | `sk_test_...` or `sk_live_...` |
| `STRIPE_PUBLISHABLE_KEY` | Yes | `pk_test_...` or `pk_live_...` |
| `STRIPE_WEBHOOK_SECRET` | Yes | `whsec_...` from Stripe Dashboard |
| `STRIPE_PRICE_BASIC_MONTHLY` | Yes | Price ID for Basic monthly |
| `STRIPE_PRICE_BASIC_YEARLY` | Yes | Price ID for Basic yearly |
| `STRIPE_PRICE_PREMIUM_MONTHLY` | Yes | Price ID for Premium monthly |
| `STRIPE_PRICE_PREMIUM_YEARLY` | Yes | Price ID for Premium yearly |
| `STRIPE_PRICE_ULTRA_MONTHLY` | Yes | Price ID for Ultra monthly |
| `STRIPE_PRICE_ULTRA_YEARLY` | Yes | Price ID for Ultra yearly |

## Setup Steps

### 1. Create Stripe Account
- Sign up at https://dashboard.stripe.com
- Complete business verification for live mode

### 2. Create Products & Prices

In Stripe Dashboard > Products, create:

| Product | Monthly Price | Yearly Price |
|---------|--------------|--------------|
| Basic Plan | $9.99/mo | $99.99/yr |
| Premium Plan | $9.99/mo | $99.99/yr |
| Ultra Plan | $24.99/mo | $249.99/yr |

Copy each Price ID (`price_...`) to your `.env` file.

### 3. Configure Webhooks

In Stripe Dashboard > Developers > Webhooks:

- **Endpoint URL**: `https://your-domain.com/api/billing/webhooks/stripe`
- **Events to listen for**:
  - `checkout.session.completed`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `customer.subscription.trial_will_end`
  - `invoice.payment_succeeded`
  - `invoice.payment_failed`
  - `invoice.upcoming`
  - `customer.created`
  - `customer.updated`

Copy the webhook signing secret (`whsec_...`) to `STRIPE_WEBHOOK_SECRET`.

### 4. Configure Billing Portal

In Stripe Dashboard > Settings > Billing > Customer portal:
- Enable invoice history
- Enable subscription cancellation
- Enable plan switching
- Set return URL to your app

## Testing

### Local Testing with Stripe CLI

```bash
# Install Stripe CLI
# https://stripe.com/docs/stripe-cli

# Login
stripe login

# Forward webhooks to local backend
stripe listen --forward-to localhost:8000/api/billing/webhooks/stripe

# Trigger test events
stripe trigger checkout.session.completed
stripe trigger invoice.payment_succeeded
stripe trigger customer.subscription.deleted
```

### Test Harness

```bash
# Start backend with test keys
STRIPE_SECRET_KEY=sk_test_... uvicorn main:app --port 8000

# Run test harness
python dev_tools/sandbox/payments/test_stripe_flow.py
```

### Key Test Scenarios

1. **Happy path**: Checkout -> payment -> subscription active
2. **Failed payment**: Card declined -> invoice.payment_failed -> subscription past_due
3. **Cancellation**: User cancels -> cancel_at_period_end -> subscription deleted
4. **Upgrade/downgrade**: Plan change -> proration -> new invoice
5. **Webhook replay**: Same event delivered twice -> idempotent handling

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/billing/plans` | No | List available plans |
| GET | `/api/billing/stripe-status` | No | Stripe config status |
| POST | `/api/billing/checkout-session` | Yes | Create checkout session |
| POST | `/api/billing/subscriptions` | Yes | Create subscription directly |
| GET | `/api/billing/subscriptions/current` | Yes | Get active subscription |
| GET | `/api/billing/subscriptions/history` | Yes | Subscription history |
| PUT | `/api/billing/subscriptions/{id}/upgrade` | Yes | Upgrade/downgrade |
| POST | `/api/billing/subscriptions/{id}/cancel` | Yes | Cancel subscription |
| POST | `/api/billing/subscriptions/{id}/reactivate` | Yes | Reactivate canceled |
| GET | `/api/billing/portal` | Yes | Billing portal URL |
| GET | `/api/billing/invoices` | Yes | List invoices |
| POST | `/api/billing/webhooks/stripe` | Stripe sig | Webhook receiver |

## Go-Live Checklist

- [ ] Switch from `sk_test_` to `sk_live_` keys
- [ ] Switch from `pk_test_` to `pk_live_` keys
- [ ] Create live products/prices and update price IDs
- [ ] Configure live webhook endpoint
- [ ] Verify webhook signing secret is for live mode
- [ ] Enable Stripe Radar for fraud protection
- [ ] Configure tax settings (if applicable)
- [ ] Test a real $1 charge and refund it
- [ ] Enable billing portal in live mode
- [ ] Set up Stripe email receipts
- [ ] Review Stripe Dashboard alerts and notifications

## Security Notes

- All Stripe API keys are env-var only (never committed)
- Webhook signature verification is mandatory (no bypass)
- Idempotency keys are generated per-request to prevent duplicate charges
- Test/live mode is determined by the key prefix (`sk_test_` vs `sk_live_`)
- The `/stripe-status` endpoint exposes only the mode, never the key
- Demo mode fallback creates local-only subscriptions with no real charges

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Stripe not configured" | Set `STRIPE_SECRET_KEY` in `.env` |
| Webhook 400 | Check `STRIPE_WEBHOOK_SECRET` matches dashboard |
| "No such price" | Create products in Stripe Dashboard, update price env vars |
| Duplicate subscriptions | Check idempotency — Stripe deduplicates within 24h |
| Portal "no customer" | User must complete checkout first to create Stripe customer |
