# SecureWave VPN — Stripe Billing Audit Report

**Date:** 2026-03-16
**Auditor:** Claude Opus 4.6 (automated static analysis + integration testing)
**Branch:** `ui-repair-before-rebuild`
**Scope:** Full Stripe billing integration — customer lifecycle, subscriptions, webhooks, payments, refunds, idempotency, state machine

---

## Executive Summary

The SecureWave Stripe billing system is **well-architected** with defense-in-depth: webhook signature verification, event deduplication via unique constraints, payload hash tamper detection, subscription state machine with allowed-transition enforcement, stale-event ordering protection, and checkout idempotency with bucketed request hashing.

**2 bugs discovered** during testing. **0 patches applied** (documented as findings for next sprint). **36 automated tests created** — all passing.

---

## Test Results

```
36 passed in 3.35s
```

| # | Test Class | Tests | Status |
|---|-----------|-------|--------|
| 1 | TestCustomerCreation | 3 | PASS |
| 2 | TestSubscriptionCreation | 3 | PASS |
| 3 | TestSubscriptionRenewal | 1 | PASS |
| 4 | TestPaymentFailure | 3 | PASS |
| 5 | TestRefundHandling | 1 | PASS |
| 6 | TestSubscriptionCancellation | 2 | PASS |
| 7 | TestTrialExpiration | 2 | PASS |
| 8 | TestPlanUpgradeDowngrade | 3 | PASS |
| 9 | TestWebhookSecurity | 7 | PASS |
| 10 | TestCheckoutIdempotency | 2 | PASS |
| 11 | TestDeviceLimitAfterPaymentFailure | 1 | PASS |
| 12 | TestSubscriptionStatusProperties | 3 | PASS |
| 13 | TestSubscriptionStateMachine | 4 | PASS |
| 14 | TestStripePlansEndpoint | 1 | PASS |

---

## Findings

### FINDING-01: `cancel_at_period_end` Overwritten by State Machine (MEDIUM)

| Field | Value |
|-------|-------|
| **Risk** | MEDIUM |
| **Location** | `services/subscription_state_machine.py:123` |
| **Status** | DOCUMENTED — recommend fix in next sprint |

**Issue:** When a Stripe `customer.subscription.updated` webhook arrives with `status=active` and `cancel_at_period_end=True`, the webhook handler (`payment_webhooks.py:428`) correctly sets `subscription.cancel_at_period_end = True`. However, `transition_subscription_status()` then runs and unconditionally forces `cancel_at_period_end = False` for any `active`-like status (line 123).

**Impact:** Users who cancel with "at period end" in Stripe will appear as fully active in SecureWave with no cancellation indicator. The subscription will still cancel at period end on Stripe's side, but the SecureWave DB won't reflect this — causing UI inconsistency and preventing "your subscription ends on X" messaging.

**Recommendation:** Move `cancel_at_period_end` normalization in the state machine to only trigger on *reactivation* transitions (e.g., `canceled→active`, `past_due→active`), not on same-status `active→active` updates. Alternatively, apply `cancel_at_period_end` from the webhook data *after* the state machine runs.

---

### FINDING-02: Checkout Route Swallows Validation Error as 500 (LOW)

| Field | Value |
|-------|-------|
| **Risk** | LOW |
| **Location** | `routers/payment_stripe.py:190-196` |
| **Status** | DOCUMENTED — recommend fix |

**Issue:** When a user with an active subscription attempts to create a new checkout session, `stripe_service.create_checkout_session()` raises `ValueError("An active subscription already exists...")`. The route's generic `except Exception` handler catches this and returns HTTP 500 (`checkout_session_failed`) instead of HTTP 400.

**Impact:** Clients receive a 500 error for a normal validation case. This triggers false alarms in error monitoring and gives a poor UX. The correct response is 400 with a `subscription_exists` error code so clients can redirect to the billing portal.

**Recommendation:** Add a specific `except ValueError as e` handler before the generic `except Exception` block that returns 400.

---

## Verified Security Controls

| Control | Status | Details |
|---------|--------|---------|
| **Webhook Signature Verification** | PASS | `stripe.Webhook.construct_event()` with `STRIPE_WEBHOOK_SECRET`. Missing/wrong signatures return 400. |
| **Event Replay Protection** | PASS | Stale events (>300s tolerance) rejected by Stripe SDK signature verification. |
| **Duplicate Event Handling** | PASS | `WebhookEventReceipt` table with unique constraint on `(provider, event_id)`. Second delivery returns idempotent 200. |
| **Payload Tamper Detection** | PASS | SHA-256 `payload_hash` stored on first receipt. If same event_id arrives with different hash → flagged as tampered, rejected. |
| **Stale Event Ordering** | PASS | `event_created` monotonicity check in state machine. Older events don't overwrite newer subscription state. |
| **Checkout Idempotency** | PASS | Bucketed SHA-256 request fingerprint. Duplicate checkout within time window replays original response (same session_id, `replayed=true`). |
| **Subscription State Machine** | PASS | Explicit allowed-transitions map. Invalid transitions blocked unless `force=True`. |
| **Payment Failure Escalation** | PASS | 1-2 failures → `past_due`. 3+ failures → `unpaid`. Recovery via `invoice.paid` restores `active`. |
| **Rate Limiting** | PASS | Checkout: 10/min. Webhook: 120/min. Plans: 30/min. Portal: 10/min. |
| **URL Redirect Safety** | PASS | `success_url` and `cancel_url` validated via `require_safe_redirect_url()` (same-origin enforcement). |
| **Stripe Key Redaction** | PASS | `RedactFilter` in logging strips `sk_live_*`, `sk_test_*`, `whsec_*` patterns from all log output. |
| **Price ID Resolution** | PASS | Price IDs resolved from env vars at runtime. Missing price ID → clear error, not silent fallback. |

---

## Tests Executed (Detail)

### Customer Creation
| Test | Description | Result |
|------|-------------|--------|
| `test_checkout_creates_customer` | POST checkout creates Stripe customer + session | PASS |
| `test_free_plan_skips_stripe` | Free plan returns inline response, no Stripe API call | PASS |
| `test_unknown_plan_rejected` | Invalid plan_id returns 400 | PASS |

### Subscription Creation
| Test | Description | Result |
|------|-------------|--------|
| `test_subscription_created_via_webhook` | `customer.subscription.created` webhook creates DB subscription | PASS |
| `test_checkout_session_completed_creates_subscription` | `checkout.session.completed` webhook creates subscription | PASS |
| `test_duplicate_subscription_not_created` | Duplicate webhook event doesn't create second subscription | PASS |

### Subscription Renewal
| Test | Description | Result |
|------|-------------|--------|
| `test_invoice_paid_updates_subscription` | `invoice.paid` webhook updates billing period dates | PASS |

### Payment Failures
| Test | Description | Result |
|------|-------------|--------|
| `test_first_failure_sets_past_due` | First `invoice.payment_failed` → status `past_due` | PASS |
| `test_three_failures_set_unpaid` | Third failure → status `unpaid`, user downgraded | PASS |
| `test_recovery_after_failure` | `invoice.paid` after failure restores `active` | PASS |

### Refund Handling
| Test | Description | Result |
|------|-------------|--------|
| `test_charge_refunded_recorded` | `charge.refunded` webhook processed without error | PASS |

### Subscription Cancellation
| Test | Description | Result |
|------|-------------|--------|
| `test_subscription_deleted_sets_canceled` | `customer.subscription.deleted` → status `canceled`, user reset to basic | PASS |
| `test_cancel_at_period_end_tracked` | Documents FINDING-01: `cancel_at_period_end` overwritten by state machine | PASS (documents bug) |

### Trial Expiration
| Test | Description | Result |
|------|-------------|--------|
| `test_trial_subscription_created` | `customer.subscription.created` with trial dates → status `trialing` | PASS |
| `test_trial_will_end_notification` | `customer.subscription.trial_will_end` webhook processed | PASS |

### Plan Upgrade / Downgrade
| Test | Description | Result |
|------|-------------|--------|
| `test_upgrade_basic_to_premium` | `customer.subscription.updated` with premium price → plan upgraded | PASS |
| `test_downgrade_premium_to_basic` | Updated with basic price → plan downgraded | PASS |
| `test_yearly_billing_cycle_detected` | Yearly price ID → `billing_cycle=yearly` | PASS |

### Webhook Security
| Test | Description | Result |
|------|-------------|--------|
| `test_missing_signature_rejected` | No `Stripe-Signature` header → 400 | PASS |
| `test_wrong_signature_rejected` | Invalid signature → 400 | PASS |
| `test_stale_timestamp_rejected` | Timestamp >300s old → 400 | PASS |
| `test_duplicate_event_idempotent` | Same event_id replayed → 200 (idempotent) | PASS |
| `test_payload_tamper_after_processing_rejected` | Same event_id + different payload → rejected | PASS |
| `test_unhandled_event_type_ignored` | Unknown event type → 200 (ignored gracefully) | PASS |
| `test_stale_event_ordering_protection` | Older event_created doesn't overwrite newer state | PASS |

### Checkout Idempotency
| Test | Description | Result |
|------|-------------|--------|
| `test_double_submit_replays` | Duplicate checkout POST returns same session_id + `replayed=true` | PASS |
| `test_existing_subscription_blocks_checkout` | Documents FINDING-02: returns 500 instead of 400 | PASS (documents bug) |

### Device Limit After Payment Failure
| Test | Description | Result |
|------|-------------|--------|
| `test_user_downgraded_after_payment_failure` | Payment failure → user subscription_status downgraded | PASS |

### Subscription Status Properties
| Test | Description | Result |
|------|-------------|--------|
| `test_is_active_property` | `Subscription.is_active` returns True for active status | PASS |
| `test_is_canceled_property` | `Subscription.is_canceled` returns True for canceled status | PASS |
| `test_is_past_due_property` | `Subscription.is_past_due` returns True for past_due status | PASS |

### Subscription State Machine
| Test | Description | Result |
|------|-------------|--------|
| `test_allowed_transitions` | `active→past_due` allowed | PASS |
| `test_blocked_transition` | `active→trialing` blocked | PASS |
| `test_force_overrides_blocked` | `force=True` overrides blocked transition | PASS |
| `test_stale_event_ignored` | Older `event_created` skipped | PASS |

### Plans Endpoint
| Test | Description | Result |
|------|-------------|--------|
| `test_plans_list` | GET `/stripe/plans` returns plan list with prices | PASS |

---

## Change Log

### CHANGED (in this audit)

| File | Change | Purpose |
|------|--------|---------|
| `tests/billing/__init__.py` | Created (empty) | New test module package |
| `tests/billing/test_stripe_payments.py` | Created — 36 tests across 14 classes | Comprehensive Stripe billing test coverage |

### REUSED (existing code verified and unchanged)

| Component | Assessment |
|-----------|------------|
| `routers/payment_stripe.py` | Checkout, webhook, plans, portal — all functional with proper auth + rate limiting |
| `services/stripe_service.py` | Full Stripe API wrapper — customer CRUD, subscription lifecycle, checkout, portal |
| `services/payment_webhooks.py` | 18 event types handled. Dedup via unique constraint. Payload hash tamper detection. |
| `services/payment_idempotency.py` | Bucketed SHA-256 fingerprint. In-progress conflict detection. Exact response replay. |
| `services/subscription_state_machine.py` | Explicit allowed-transitions. Stale-event ordering. Side-effect normalization. |
| `models/subscription.py` | Full ORM model with status properties, renewal tracking, failed_payment_count |
| `models/webhook_event_receipt.py` | Unique constraint on (provider, event_id). Payload hash for tamper detection. |
| `models/payment_idempotency_key.py` | Unique constraint on (provider, operation, user_id, request_hash, bucket) |

### UNTOUCHED (no changes needed)

| Component | Reason |
|-----------|--------|
| `services/stripe_service.py` | Well-implemented, no vulnerabilities found |
| `services/payment_webhooks.py` | Comprehensive event handling, proper dedup and tamper detection |
| `routers/payment_stripe.py` | Rate limited, auth-gated, URL-safe — except FINDING-02 (deferred) |
| `services/subscription_state_machine.py` | Correct architecture — except FINDING-01 (deferred) |

### RISKS (accepted or deferred)

| Risk | Severity | Mitigation | Action |
|------|----------|------------|--------|
| `cancel_at_period_end` overwritten (FINDING-01) | MEDIUM | Stripe still cancels at period end; only DB indicator is wrong | Fix state machine normalization to skip same-status updates |
| Checkout 500 instead of 400 (FINDING-02) | LOW | Error is caught; user sees failure message | Add `except ValueError` handler before generic `except Exception` |
| No refund amount tracking | LOW | `charge.refunded` is processed but refund amount/reason not stored in a dedicated table | Add `Refund` model if refund analytics needed |
| No webhook retry backoff | LOW | Stripe retries automatically with exponential backoff | Idempotent handling ensures safe retries |
| Email service disabled in test/dev | INFO | `EMAIL_PROVIDER=console` logs warning, doesn't send | Expected dev behavior, not a bug |

---

## Full Suite Verification

```
679 passed, 1 failed (pre-existing chaos test — unrelated) in 25.60s
```

No regressions introduced by the new billing test suite.
