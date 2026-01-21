from services.payment_webhooks import PaymentWebhookHandler


def test_stripe_payment_failed_sends_notification(db, test_user, monkeypatch):
    from models.subscription import Subscription

    sent = {"count": 0}

    def fake_send_email(*args, **kwargs):
        sent["count"] += 1
        return True

    monkeypatch.setattr(
        "services.payment_webhooks.EmailService.send_email",
        fake_send_email,
        raising=False,
    )

    subscription = Subscription(
        user_id=test_user.id,
        plan_id="basic",
        plan_name="Basic",
        provider="stripe",
        status="active",
        stripe_subscription_id="sub_test_123",
        amount=9.0,
        currency="USD",
    )
    db.add(subscription)
    db.commit()

    handler = PaymentWebhookHandler(db)
    handler._stripe_invoice_payment_failed(
        {
            "id": "in_test_123",
            "subscription": "sub_test_123",
            "hosted_invoice_url": "https://example.com/invoice",
        }
    )

    assert sent["count"] >= 1


def test_stripe_action_required_sends_notification(db, test_user, monkeypatch):
    from models.subscription import Subscription
    from models.invoice import Invoice

    sent = {"count": 0}

    def fake_send_email(*args, **kwargs):
        sent["count"] += 1
        return True

    monkeypatch.setattr(
        "services.payment_webhooks.EmailService.send_email",
        fake_send_email,
        raising=False,
    )

    subscription = Subscription(
        user_id=test_user.id,
        plan_id="basic",
        plan_name="Basic",
        provider="stripe",
        status="active",
        stripe_subscription_id="sub_action_123",
        amount=9.0,
        currency="USD",
    )
    db.add(subscription)
    db.commit()

    invoice = Invoice(
        user_id=test_user.id,
        subscription_id=subscription.id,
        invoice_number="INV-ACTION-123",
        provider="stripe",
        stripe_invoice_id="in_action_123",
        amount_due=9.0,
        amount_paid=0.0,
        amount_remaining=9.0,
        currency="USD",
        subtotal=9.0,
        status="open",
    )
    db.add(invoice)
    db.commit()

    handler = PaymentWebhookHandler(db)
    handler._stripe_invoice_action_required(
        {
            "id": "in_action_123",
            "subscription": "sub_action_123",
            "hosted_invoice_url": "https://example.com/invoice",
        }
    )

    assert sent["count"] >= 1
    db.refresh(invoice)
    assert invoice.status == "open"
