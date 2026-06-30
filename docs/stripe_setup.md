# Stripe Payment Integration Setup Guide

This document covers the complete Stripe integration for SecureWave VPN,
from account creation through production launch.

---

## 1. Account Setup

### Create a Stripe Account

1. Go to [https://dashboard.stripe.com/register](https://dashboard.stripe.com/register).
2. Complete the registration form with your business details.
3. Verify your email address.

### Enable Test Mode

1. In the Stripe Dashboard, toggle **Test mode** in the top-right corner.
2. Navigate to **Developers > API keys**.
3. Copy your **Publishable key** (`pk_test_...`) and **Secret key** (`sk_test_...`).
4. Store these securely -- never commit them to version control.

---

## 2. Products and Prices

Create three subscription products in the Stripe Dashboard under
**Products > Add product**, or use the automated SecureWave provisioning script.

### Basic Plan

| Field          | Value             |
|----------------|-------------------|
| Product name   | SecureWave Basic   |
| Monthly price  | $9.99/month       |
| Annual price   | $99.99/year        |
| Description    | VPN access for 1 device, standard server selection |

### Premium Plan

| Field          | Value              |
|----------------|-------------------|
| Product name   | SecureWave Premium  |
| Monthly price  | $9.99/month        |
| Annual price   | $99.99/year         |
| Description    | VPN access for up to 5 devices, priority server selection, kill switch |

### Ultra Plan

| Field          | Value              |
|----------------|-------------------|
| Product name   | SecureWave Ultra    |
| Monthly price  | $24.99/month       |
| Annual price   | $249.99/year        |
| Description    | Unlimited devices, dedicated servers, MARL-optimized routing, 24/7 support |

### Recommended: automated provisioning

The production path is the repo script below. It creates or reuses the Stripe
Products, recurring Prices, webhook endpoint, and Customer Portal configuration,
then writes the ignored private release env file with `0600` permissions.

```bash
export STRIPE_SECRET_KEY="sk_live_..."
export STRIPE_PUBLISHABLE_KEY="pk_live_..."
export APP_URL="https://securewaveapp.com"

python scripts/stripe_billing_provision.py --confirm-live
bash scripts/billing_release_gate.sh --env-file securewave_private/billing_release.env
```

For a Stripe test-mode rehearsal, use `sk_test_...`, `pk_test_...`, a local or
staging app URL, and pass `--allow-test-mode` instead of `--confirm-live`.

If the webhook endpoint already exists, Stripe does not expose its signing
secret through the API. In that case, copy the endpoint's `whsec_...` value from
the Stripe Dashboard into `securewave_private/billing_release.env`, then rerun
the billing release gate.

### Manual Stripe CLI alternative

```bash
# Basic Plan
stripe products create --name="SecureWave Basic" \
  --description="VPN access for 1 device, standard server selection"

stripe prices create \
  --product=prod_BASIC_ID \
  --unit-amount=999 \
  --currency=usd \
  --recurring[interval]=month

stripe prices create \
  --product=prod_BASIC_ID \
  --unit-amount=9999 \
  --currency=usd \
  --recurring[interval]=year

# Premium Plan
stripe products create --name="SecureWave Premium" \
  --description="VPN access for up to 5 devices, priority server selection, kill switch"

stripe prices create \
  --product=prod_PREMIUM_ID \
  --unit-amount=999 \
  --currency=usd \
  --recurring[interval]=month

stripe prices create \
  --product=prod_PREMIUM_ID \
  --unit-amount=9999 \
  --currency=usd \
  --recurring[interval]=year

# Ultra Plan
stripe products create --name="SecureWave Ultra" \
  --description="Unlimited devices, dedicated servers, MARL-optimized routing, 24/7 support"

stripe prices create \
  --product=prod_ULTRA_ID \
  --unit-amount=2499 \
  --currency=usd \
  --recurring[interval]=month

stripe prices create \
  --product=prod_ULTRA_ID \
  --unit-amount=24999 \
  --currency=usd \
  --recurring[interval]=year
```

After creating products, note the `prod_*` and `price_*` IDs for your
environment configuration.

---

## 3. Webhook Configuration

### Endpoint URL

```
https://your-domain.com/api/billing/webhooks/stripe
```

For local development with the Stripe CLI:

```bash
stripe listen --forward-to http://localhost:8000/api/billing/webhooks/stripe
```

### Events to Subscribe

Configure the webhook endpoint to receive the following events:

| Event                              | Purpose                                      |
|------------------------------------|----------------------------------------------|
| `checkout.session.completed`       | Sync paid Checkout subscriptions locally      |
| `customer.created`                 | Track Stripe customer lifecycle events        |
| `customer.updated`                 | Track Stripe customer lifecycle events        |
| `customer.deleted`                 | Track Stripe customer lifecycle events        |
| `customer.subscription.created`    | Activate new subscription in our database     |
| `customer.subscription.updated`    | Handle plan changes, renewals, pauses         |
| `customer.subscription.deleted`    | Deactivate subscription on cancellation       |
| `customer.subscription.trial_will_end` | Notify before a trial ends                 |
| `invoice.created`                  | Create local invoice records                  |
| `invoice.finalized`                | Track finalized invoices                      |
| `invoice.paid`                     | Confirm recurring payment success             |
| `invoice.payment_failed`           | Handle failed recurring payment               |
| `invoice.payment_action_required`  | Handle 3D Secure/action-required invoices     |
| `payment_intent.succeeded`         | Confirm successful payment                    |
| `payment_intent.payment_failed`    | Handle failed payment attempts                |
| `charge.succeeded`                 | Track charge success                          |
| `charge.failed`                    | Track charge failure                          |
| `charge.refunded`                  | Sync refunds                                  |

### Dashboard Steps

1. Go to **Developers > Webhooks > Add endpoint**.
2. Enter the endpoint URL above.
3. Select the events listed in the table.
4. Click **Add endpoint**.
5. Copy the **Signing secret** (`whsec_...`) for your environment variables.

---

## 4. Environment Variables

Add the following variables to your `.env` file or deployment environment.
All values below are placeholders -- replace them with your actual keys.

```bash
PAYMENTS_MOCK=false
DEMO_BILLING=false
PAYMENT_PROVIDER=stripe

# Stripe API Keys (replace with your actual live keys from Stripe Dashboard)
STRIPE_SECRET_KEY=sk_live_YOUR_SECRET_KEY_HERE
STRIPE_PUBLISHABLE_KEY=pk_live_YOUR_PUBLISHABLE_KEY_HERE
STRIPE_API_VERSION=2026-02-25.clover

# Webhook Signing Secret (from Stripe Dashboard -> Developers -> Webhooks)
STRIPE_WEBHOOK_SECRET=whsec_YOUR_WEBHOOK_SECRET_HERE

# Price IDs (from product creation above)
STRIPE_PRICE_BASIC_MONTHLY=price_XXXXXXXXXXXXXXXXXXXXXXXX
STRIPE_PRICE_BASIC_YEARLY=price_XXXXXXXXXXXXXXXXXXXXXXXX
STRIPE_PRICE_PREMIUM_MONTHLY=price_XXXXXXXXXXXXXXXXXXXXXXXX
STRIPE_PRICE_PREMIUM_YEARLY=price_XXXXXXXXXXXXXXXXXXXXXXXX
STRIPE_PRICE_ULTRA_MONTHLY=price_XXXXXXXXXXXXXXXXXXXXXXXX
STRIPE_PRICE_ULTRA_YEARLY=price_XXXXXXXXXXXXXXXXXXXXXXXX

# Required: Stripe Customer Portal
STRIPE_PORTAL_CONFIG_ID=bpc_XXXXXXXXXXXXXXXXXXXXXXXX
STRIPE_AUTOMATIC_TAX=false
```

**Security rules:**

- Never commit `.env` files to version control.
- In production, use environment-injected secrets from your approved secret
  manager.
- Rotate keys immediately if any are exposed.

---

## 5. Testing with Test Mode

### Test Card Numbers

Stripe provides test card numbers that work only in test mode.

| Card Number          | Scenario                          |
|----------------------|-----------------------------------|
| `4242 4242 4242 4242` | Successful payment               |
| `4000 0000 0000 3220` | 3D Secure 2 authentication required |
| `4000 0000 0000 9995` | Payment declined (insufficient funds) |
| `4000 0000 0000 0069` | Expired card                      |
| `4000 0000 0000 0127` | Incorrect CVC                     |

For all test cards, use:

- **Expiry**: Any future date (e.g., `12/34`)
- **CVC**: Any 3 digits (e.g., `123`)
- **ZIP**: Any 5 digits (e.g., `12345`)

### Testing Webhooks Locally

```bash
# Install the Stripe CLI
brew install stripe/stripe-cli/stripe   # macOS
# or: https://stripe.com/docs/stripe-cli#install

# Login
stripe login

# Forward events to your local server
stripe listen --forward-to http://localhost:8000/api/billing/webhooks/stripe

# In another terminal, trigger a test event
stripe trigger payment_intent.succeeded
stripe trigger customer.subscription.created
stripe trigger invoice.payment_failed
```

### Verifying Integration

1. Create a test subscription through the SecureWave UI.
2. Confirm the webhook logs show event receipt in your server logs.
3. Verify the subscription status updates in the SecureWave database.
4. Test cancellation and confirm the subscription is deactivated.

---

## 6. Going Live Checklist

Before switching from test mode to production:

- [ ] Replace `sk_test_*` with `sk_live_*` in your production secrets.
- [ ] Replace `pk_test_*` with `pk_live_*` in your frontend configuration.
- [ ] Run `python scripts/stripe_billing_provision.py --confirm-live`.
- [ ] Create or verify a webhook endpoint pointing to your production URL.
- [ ] Copy the new live **webhook signing secret** (`whsec_...`) to production.
- [ ] Update all `price_*` IDs and `STRIPE_PORTAL_CONFIG_ID` in
      `securewave_private/billing_release.env`.
- [ ] Run `bash scripts/billing_release_gate.sh --env-file securewave_private/billing_release.env`.
- [ ] Enable **Stripe Radar** for fraud prevention under **More > Radar > Settings**.
- [ ] Enable **3D Secure** for cards that support it (Radar rules).
- [ ] Configure **Stripe Tax** if required for your jurisdiction.
- [ ] Verify webhook signature verification is enforced in the backend
      (`stripe.Webhook.construct_event()` with `STRIPE_WEBHOOK_SECRET`).
- [ ] Test a real $1.00 charge to your own card and then refund it.
- [ ] Confirm email receipts are sent by Stripe or your own email service.
- [ ] Remove or restrict access to `/api/docs` in production
      (already handled by `docs_enabled` flag in `main.py`).

---

## 7. PCI Compliance Notes

SecureWave uses **Stripe Elements** (or Stripe Checkout) on the frontend,
which means:

- **Card numbers never touch our servers.** Stripe.js tokenizes card data
  directly in the browser and sends it to Stripe's PCI-compliant infrastructure.
- The backend only receives a `payment_method` ID or `payment_intent` ID --
  never raw card numbers, CVCs, or expiry dates.
- This qualifies SecureWave for **SAQ A** (the simplest PCI DSS
  self-assessment questionnaire).

### What We Must Still Do

1. **Serve all pages over HTTPS.** Enforced via `Strict-Transport-Security`
   header in `main.py`.
2. **Never log or store card data.** Our `RedactFilter` in `main.py` already
   strips sensitive patterns from logs.
3. **Keep Stripe SDK updated.** Pin to latest stable in `requirements.txt`.
4. **Restrict API key access.** Only the backend process should have access
   to `STRIPE_SECRET_KEY`.
5. **Use restricted API keys in production** where possible (Stripe Dashboard >
   Developers > API Keys > Create restricted key) to limit permissions to
   only what is needed (e.g., charges, subscriptions, webhooks).

### Stripe Elements Integration

The frontend should load Stripe.js from the official CDN:

```html
<script src="https://js.stripe.com/v3/"></script>
```

Never self-host `stripe.js`. Stripe requires loading from their CDN to
maintain PCI compliance.

---

## References

- [Stripe Docs: Subscriptions](https://stripe.com/docs/billing/subscriptions/overview)
- [Stripe Docs: Webhooks](https://stripe.com/docs/webhooks)
- [Stripe Docs: Testing](https://stripe.com/docs/testing)
- [Stripe Docs: PCI Compliance](https://stripe.com/docs/security/guide)
- [Stripe CLI](https://stripe.com/docs/stripe-cli)
