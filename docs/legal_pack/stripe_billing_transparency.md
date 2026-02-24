# SecureWave Billing Transparency

**Last updated:** February 2026
**Contact:** billing@securewavevpn.com

> This document explains exactly how billing works, what Stripe processes, what SecureWave stores, and how subscriptions are managed.

---

## How Payments Work

SecureWave uses **Stripe** as its primary payment processor and **PayPal** as an alternative. We do not build our own payment infrastructure.

When you subscribe:

1. You are redirected to a **Stripe-hosted Checkout page** — a page served directly by Stripe's servers, not SecureWave's.
2. You enter your payment details directly into Stripe's form. Your card number never passes through SecureWave's servers.
3. Stripe processes the payment and notifies SecureWave via a **signed webhook event**.
4. SecureWave activates your subscription based on the webhook confirmation.

---

## What Stripe Processes

Stripe receives and processes:

- Your full credit or debit card number, expiry, and CVV
- Your billing name and billing address
- Your email address (for Stripe's records and payment receipts)
- Payment method details (bank account, SEPA, etc. if applicable)

Stripe stores this data in accordance with their [Privacy Policy](https://stripe.com/privacy) and are certified PCI DSS Level 1 — the highest level of payment security certification.

---

## What SecureWave Stores

After a successful payment, SecureWave receives and stores only:

| Data | Source | Purpose |
|------|--------|---------|
| Stripe Customer ID | Stripe webhook | Link your account to Stripe's records for portal access |
| Stripe Subscription ID | Stripe webhook | Track your subscription status |
| Current plan name | Stripe webhook | Control access to features |
| Subscription status | Stripe webhook | `active`, `past_due`, `canceled`, etc. |
| Current period end date | Stripe webhook | Display renewal date in your account |
| Last 4 digits of card | Stripe API (for display) | Shown in billing center so you can identify your card |
| Card brand | Stripe API (for display) | Visa, Mastercard, etc. |
| Invoice history | Stripe API | Display in your billing center |

**SecureWave does not store:**
- Full card number
- Card CVV or security code
- Card expiry date (beyond what Stripe stores)
- Bank account details

---

## Subscription Lifecycle

```
Register → Select plan → Stripe Checkout → Payment confirmed
                                               ↓
                                     Subscription activated
                                               ↓
                              Auto-renews on billing anniversary
                                               ↓
                        Renewal reminder sent 7 days before charge
                                               ↓
                              Cancel any time → active until period end
```

### Auto-Renewal

Your subscription renews automatically unless you cancel. Renewal charges occur on the same day each month (or year, for annual plans). You will receive:

- A renewal reminder email **7 days before** each charge
- A payment receipt from Stripe immediately after each successful charge

### Failed Payments

If a payment fails:

1. Stripe retries according to its retry schedule (Smart Retries)
2. You receive an email notification after each failed attempt
3. After the final retry, your subscription enters `past_due` status and VPN access is restricted
4. Updating your payment method reactivates your subscription immediately

You can update your payment method at any time via the **Stripe Billing Portal** accessible from your account's Billing Center.

---

## Subscription Management

All subscription changes are handled through the **Stripe-hosted Billing Portal**. From there, you can:

- Update your payment method
- Download invoices and receipts
- Upgrade or downgrade your plan (prorated)
- Cancel your subscription
- View billing history

SecureWave staff cannot modify your payment method or process charges directly — all changes go through Stripe.

---

## Refund Policy

**30-day money-back guarantee** for new subscribers:

- Applies to the first billing period only
- Request within 30 days of the initial charge
- Refund processed to your original payment method within **10 business days**
- Does not apply to subscription renewals or plan upgrades

To request a refund: contact billing@securewavevpn.com or use the [Contact form](https://securewavevpn.com/contact).

Renewals, upgrades, and additional purchases are non-refundable except where required by applicable consumer protection law.

---

## Pricing

Current plan pricing is listed at [securewavevpn.com/subscription](https://securewavevpn.com/subscription).

| Plan | Devices | Bandwidth |
|------|---------|-----------|
| Free | 1 | 5 GB/month |
| Basic | 3 | Unlimited |
| Pro | 5 | Unlimited |
| Business | 10 | Unlimited |

Prices are in USD. Taxes may apply depending on your billing country. Annual plans are charged as a single payment.

**Price changes:** We will notify you at least 30 days in advance of any price increase. Price increases apply at the start of your next billing cycle.

---

## Stripe Security

Stripe maintains the following certifications:

- **PCI DSS Level 1** — highest level of payment card industry security
- **SOC 2 Type II** — independently audited security controls
- **ISO 27001** — information security management
- **3D Secure** — optional additional authentication layer

For full details, see [Stripe's Security page](https://stripe.com/docs/security).

---

## Webhook Security

SecureWave uses Stripe's signed webhook events to process subscription updates. Every webhook event is:

1. Verified using Stripe's HMAC-SHA256 signature (`STRIPE_WEBHOOK_SECRET`)
2. Checked for timestamp staleness (events older than 5 minutes are rejected)
3. Checked for duplicate processing (idempotency enforced)

This prevents malicious actors from sending fake payment confirmations to activate subscriptions.

---

## Cancellation

You may cancel your subscription at any time:

1. **Via Stripe Portal:** Go to Billing Center → "Manage billing in portal" → Cancel subscription
2. **Via email:** Contact billing@securewavevpn.com

Upon cancellation:
- Your subscription remains active until the end of the current paid period
- No further charges are made
- You are not charged a cancellation fee

---

## Contact

**Billing questions:** billing@securewavevpn.com
**Refund requests:** billing@securewavevpn.com
**General support:** [securewavevpn.com/contact](https://securewavevpn.com/contact)
**Response time:** 2 business days

---

*SecureWave never calls you to request payment. If you receive an unsolicited call claiming to be SecureWave billing, it is a scam.*
