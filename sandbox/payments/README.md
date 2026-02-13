# SecureWave Payment Test Harness

## Setup

1. Set Stripe **test** keys in `.env`:
   ```
   STRIPE_SECRET_KEY=sk_test_...
   STRIPE_PUBLISHABLE_KEY=pk_test_...
   STRIPE_WEBHOOK_SECRET=whsec_...
   ```

2. Start the backend:
   ```bash
   uvicorn main:app --reload --port 8000
   ```

3. Run tests:
   ```bash
   python sandbox/payments/test_stripe_flow.py
   ```

## Scripts

| Script | Purpose |
|--------|---------|
| `test_stripe_flow.py` | End-to-end: plans, checkout session, webhook sim |
| `simulate_webhook.py` | Send simulated Stripe webhook events locally |

## Stripe CLI (optional)

For real webhook forwarding:
```bash
stripe listen --forward-to localhost:8000/api/billing/webhooks/stripe
stripe trigger checkout.session.completed
```
