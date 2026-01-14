"""
SecureWave VPN - Billing Automation Service
Automated subscription renewals, dunning management, and lifecycle processing
"""

import logging
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from sqlalchemy.orm import Session

from models.subscription import Subscription
from models.invoice import Invoice
from models.user import User
from services.subscription_manager import SubscriptionManager
from services.stripe_service import StripeService
from services.paypal_service import PayPalService

logger = logging.getLogger(__name__)


class BillingAutomationService:
    """
    Automated billing operations service
    Handles subscription renewals, failed payments, and lifecycle management
    """

    # Retry schedule for failed payments (in days)
    RETRY_SCHEDULE = [3, 7, 14, 21]  # Retry on days 3, 7, 14, and 21
    GRACE_PERIOD_DAYS = 7  # Days to maintain access after failed payment
    CANCELLATION_THRESHOLD = 30  # Days after which to cancel for non-payment

    def __init__(self, db: Session):
        """
        Initialize billing automation service

        Args:
            db: Database session
        """
        self.db = db
        self.subscription_manager = SubscriptionManager(db)
        self.stripe = StripeService()
        self.paypal = PayPalService()

    # ===========================
    # RENEWAL PROCESSING
    # ===========================

    def process_upcoming_renewals(self, days_ahead: int = 7) -> Dict:
        """
        Process subscriptions renewing in the next X days
        Send renewal reminders and verify payment methods

        Args:
            days_ahead: Number of days to look ahead

        Returns:
            Processing results
        """
        try:
            renewal_threshold = datetime.utcnow() + timedelta(days=days_ahead)

            # Get subscriptions renewing soon
            upcoming_renewals = self.db.query(Subscription).filter(
                Subscription.status == "active",
                Subscription.next_billing_date <= renewal_threshold,
                Subscription.next_billing_date > datetime.utcnow(),
                Subscription.auto_renew == True,
                Subscription.cancel_at_period_end == False
            ).all()

            results = {
                "total": len(upcoming_renewals),
                "reminders_sent": 0,
                "payment_methods_verified": 0,
                "issues_found": 0,
                "errors": []
            }

            for subscription in upcoming_renewals:
                try:
                    days_until_renewal = (subscription.next_billing_date - datetime.utcnow()).days

                    # Send renewal reminder at 7 days, 3 days, and 1 day
                    if days_until_renewal in [7, 3, 1]:
                        self._send_renewal_reminder(subscription, days_until_renewal)
                        results["reminders_sent"] += 1

                    # Verify payment method
                    if subscription.provider == "stripe":
                        if self._verify_stripe_payment_method(subscription):
                            results["payment_methods_verified"] += 1
                        else:
                            results["issues_found"] += 1
                            self._send_payment_method_issue_alert(subscription)

                except Exception as e:
                    logger.error(f"✗ Error processing renewal for subscription {subscription.id}: {e}")
                    results["errors"].append(str(e))

            logger.info(f"✓ Processed {results['total']} upcoming renewals")
            return results

        except Exception as e:
            logger.error(f"✗ Failed to process upcoming renewals: {e}")
            raise

    def process_trial_expirations(self, days_ahead: int = 3) -> Dict:
        """
        Process trial subscriptions expiring soon
        Send trial ending reminders

        Args:
            days_ahead: Days ahead to check

        Returns:
            Processing results
        """
        try:
            expiry_threshold = datetime.utcnow() + timedelta(days=days_ahead)

            # Get trials expiring soon
            expiring_trials = self.db.query(Subscription).filter(
                Subscription.status == "trialing",
                Subscription.trial_end <= expiry_threshold,
                Subscription.trial_end > datetime.utcnow()
            ).all()

            results = {
                "total": len(expiring_trials),
                "reminders_sent": 0,
                "errors": []
            }

            for subscription in expiring_trials:
                try:
                    days_remaining = (subscription.trial_end - datetime.utcnow()).days

                    # Send reminders at 3 days and 1 day
                    if days_remaining in [3, 1]:
                        self._send_trial_ending_reminder(subscription, days_remaining)
                        results["reminders_sent"] += 1

                except Exception as e:
                    logger.error(f"✗ Error processing trial expiration for {subscription.id}: {e}")
                    results["errors"].append(str(e))

            logger.info(f"✓ Processed {results['total']} expiring trials")
            return results

        except Exception as e:
            logger.error(f"✗ Failed to process trial expirations: {e}")
            raise

    # ===========================
    # FAILED PAYMENT HANDLING
    # ===========================

    def process_failed_payments(self) -> Dict:
        """
        Process subscriptions with failed payments
        Implement dunning management with progressive retry

        Returns:
            Processing results
        """
        try:
            # Get subscriptions with failed payments
            failed_subscriptions = self.db.query(Subscription).filter(
                Subscription.status == "past_due",
                Subscription.failed_payment_count > 0
            ).all()

            results = {
                "total": len(failed_subscriptions),
                "retry_attempts": 0,
                "successfully_recovered": 0,
                "grace_period_ending": 0,
                "cancelled": 0,
                "errors": []
            }

            for subscription in failed_subscriptions:
                try:
                    days_since_failure = (datetime.utcnow() - subscription.last_payment_date).days

                    # Check if we should retry payment
                    if days_since_failure in self.RETRY_SCHEDULE:
                        retry_result = self._retry_failed_payment(subscription)
                        results["retry_attempts"] += 1

                        if retry_result["success"]:
                            results["successfully_recovered"] += 1
                            subscription.status = "active"
                            subscription.failed_payment_count = 0
                            subscription.last_payment_status = "succeeded"
                        else:
                            subscription.failed_payment_count += 1

                    # Check if grace period is ending
                    if days_since_failure >= self.GRACE_PERIOD_DAYS - 1:
                        self._send_grace_period_ending_notice(subscription)
                        results["grace_period_ending"] += 1

                    # Cancel after threshold
                    if days_since_failure >= self.CANCELLATION_THRESHOLD:
                        self._cancel_for_non_payment(subscription)
                        results["cancelled"] += 1

                    self.db.commit()

                except Exception as e:
                    self.db.rollback()
                    logger.error(f"✗ Error processing failed payment for {subscription.id}: {e}")
                    results["errors"].append(str(e))

            logger.info(f"✓ Processed {results['total']} failed payments")
            return results

        except Exception as e:
            logger.error(f"✗ Failed to process failed payments: {e}")
            raise

    def _retry_failed_payment(self, subscription: Subscription) -> Dict:
        """
        Retry a failed payment

        Args:
            subscription: Subscription to retry

        Returns:
            Retry result
        """
        try:
            logger.info(f"⟳ Retrying payment for subscription {subscription.id}")

            if subscription.provider == "stripe":
                # Retrieve latest invoice
                invoices = self.stripe.list_invoices(
                    customer_id=subscription.stripe_customer_id,
                    limit=1
                )

                if invoices and invoices[0].status == "open":
                    # Attempt to pay invoice
                    invoice = self.stripe.pay_invoice(invoices[0].id)

                    if invoice.status == "paid":
                        logger.info(f"✓ Payment retry successful for subscription {subscription.id}")
                        return {"success": True, "invoice_id": invoice.id}
                    else:
                        logger.warning(f"⚠ Payment retry failed for subscription {subscription.id}")
                        return {"success": False, "reason": invoice.status}

            elif subscription.provider == "paypal":
                # PayPal handles retries automatically
                # We sync the status from PayPal
                paypal_sub = self.paypal.get_subscription(subscription.paypal_subscription_id)

                if paypal_sub and paypal_sub.get("status") == "ACTIVE":
                    logger.info(f"✓ PayPal subscription recovered: {subscription.id}")
                    return {"success": True}

            return {"success": False, "reason": "no_retry_available"}

        except Exception as e:
            logger.error(f"✗ Failed to retry payment: {e}")
            return {"success": False, "reason": str(e)}

    def _cancel_for_non_payment(self, subscription: Subscription) -> None:
        """
        Cancel subscription due to non-payment

        Args:
            subscription: Subscription to cancel
        """
        try:
            logger.warning(f"⚠ Cancelling subscription {subscription.id} for non-payment")

            # Cancel with provider
            self.subscription_manager.cancel_subscription(
                subscription_id=subscription.id,
                cancel_at_period_end=False,
                reason="non_payment"
            )

            # Send cancellation notice
            self._send_cancellation_notice(subscription, reason="non_payment")

            logger.info(f"✓ Subscription {subscription.id} cancelled for non-payment")

        except Exception as e:
            logger.error(f"✗ Failed to cancel subscription for non-payment: {e}")
            raise

    # ===========================
    # SUBSCRIPTION LIFECYCLE
    # ===========================

    def process_subscription_lifecycle(self) -> Dict:
        """
        Process all subscription lifecycle events
        Check for expirations, cancellations, and status updates

        Returns:
            Processing results
        """
        try:
            results = {
                "expired_trials": 0,
                "expired_subscriptions": 0,
                "pending_cancellations": 0,
                "status_updates": 0,
                "errors": []
            }

            # Process expired trials
            expired_trials = self.db.query(Subscription).filter(
                Subscription.status == "trialing",
                Subscription.trial_end <= datetime.utcnow()
            ).all()

            for subscription in expired_trials:
                try:
                    # Sync with provider to get post-trial status
                    if subscription.provider == "stripe":
                        self.subscription_manager.sync_subscription_from_stripe(
                            subscription.stripe_subscription_id
                        )
                    elif subscription.provider == "paypal":
                        self.subscription_manager.sync_subscription_from_paypal(
                            subscription.paypal_subscription_id
                        )

                    results["expired_trials"] += 1

                except Exception as e:
                    logger.error(f"✗ Error processing expired trial {subscription.id}: {e}")
                    results["errors"].append(str(e))

            # Process subscriptions set to cancel at period end
            pending_cancellations = self.db.query(Subscription).filter(
                Subscription.cancel_at_period_end == True,
                Subscription.current_period_end <= datetime.utcnow()
            ).all()

            for subscription in pending_cancellations:
                try:
                    subscription.status = "canceled"
                    subscription.canceled_at = datetime.utcnow()
                    self.db.commit()

                    self._send_cancellation_confirmation(subscription)
                    results["pending_cancellations"] += 1

                except Exception as e:
                    self.db.rollback()
                    logger.error(f"✗ Error cancelling subscription {subscription.id}: {e}")
                    results["errors"].append(str(e))

            # Process expired subscriptions (past period end, not auto-renew)
            expired_subscriptions = self.db.query(Subscription).filter(
                Subscription.status == "active",
                Subscription.auto_renew == False,
                Subscription.current_period_end <= datetime.utcnow()
            ).all()

            for subscription in expired_subscriptions:
                try:
                    subscription.status = "expired"
                    subscription.expired_at = datetime.utcnow()
                    self.db.commit()

                    self._send_expiration_notice(subscription)
                    results["expired_subscriptions"] += 1

                except Exception as e:
                    self.db.rollback()
                    logger.error(f"✗ Error expiring subscription {subscription.id}: {e}")
                    results["errors"].append(str(e))

            logger.info(f"✓ Processed subscription lifecycle: {results}")
            return results

        except Exception as e:
            logger.error(f"✗ Failed to process subscription lifecycle: {e}")
            raise

    # ===========================
    # SYNC OPERATIONS
    # ===========================

    def sync_all_active_subscriptions(self) -> Dict:
        """
        Sync all active subscriptions with payment providers
        Ensures database is in sync with Stripe and PayPal

        Returns:
            Sync results
        """
        try:
            active_subscriptions = self.db.query(Subscription).filter(
                Subscription.status.in_(["active", "trialing", "past_due"])
            ).all()

            results = {
                "total": len(active_subscriptions),
                "stripe_synced": 0,
                "paypal_synced": 0,
                "errors": []
            }

            for subscription in active_subscriptions:
                try:
                    if subscription.provider == "stripe":
                        self.subscription_manager.sync_subscription_from_stripe(
                            subscription.stripe_subscription_id
                        )
                        results["stripe_synced"] += 1

                    elif subscription.provider == "paypal":
                        self.subscription_manager.sync_subscription_from_paypal(
                            subscription.paypal_subscription_id
                        )
                        results["paypal_synced"] += 1

                except Exception as e:
                    logger.error(f"✗ Error syncing subscription {subscription.id}: {e}")
                    results["errors"].append(str(e))

            logger.info(f"✓ Synced {results['total']} active subscriptions")
            return results

        except Exception as e:
            logger.error(f"✗ Failed to sync subscriptions: {e}")
            raise

    # ===========================
    # INVOICE PROCESSING
    # ===========================

    def process_overdue_invoices(self) -> Dict:
        """
        Process overdue invoices
        Send reminders and take action on severely overdue invoices

        Returns:
            Processing results
        """
        try:
            overdue_invoices = self.db.query(Invoice).filter(
                Invoice.status == "open",
                Invoice.due_date <= datetime.utcnow()
            ).all()

            results = {
                "total": len(overdue_invoices),
                "reminders_sent": 0,
                "errors": []
            }

            for invoice in overdue_invoices:
                try:
                    days_overdue = invoice.days_overdue

                    # Send reminders at specific intervals
                    if days_overdue in [1, 7, 14, 21, 28]:
                        self._send_overdue_invoice_reminder(invoice, days_overdue)
                        results["reminders_sent"] += 1

                    # Update attempt counter
                    invoice.attempt_count += 1

                    # Set next payment attempt
                    if days_overdue < 30:
                        next_retry = self._get_next_retry_date(days_overdue)
                        invoice.next_payment_attempt = next_retry

                    self.db.commit()

                except Exception as e:
                    self.db.rollback()
                    logger.error(f"✗ Error processing overdue invoice {invoice.id}: {e}")
                    results["errors"].append(str(e))

            logger.info(f"✓ Processed {results['total']} overdue invoices")
            return results

        except Exception as e:
            logger.error(f"✗ Failed to process overdue invoices: {e}")
            raise

    def _get_next_retry_date(self, days_overdue: int) -> datetime:
        """
        Calculate next payment retry date based on dunning schedule

        Args:
            days_overdue: Number of days invoice is overdue

        Returns:
            Next retry date
        """
        for retry_day in self.RETRY_SCHEDULE:
            if days_overdue < retry_day:
                return datetime.utcnow() + timedelta(days=retry_day - days_overdue)

        # If past all scheduled retries, try in 7 days
        return datetime.utcnow() + timedelta(days=7)

    # ===========================
    # REPORTING
    # ===========================

    def generate_billing_health_report(self) -> Dict:
        """
        Generate comprehensive billing health report

        Returns:
            Health report with metrics
        """
        try:
            # Get subscription statistics
            total_subscriptions = self.db.query(Subscription).count()
            active_subscriptions = self.db.query(Subscription).filter_by(status="active").count()
            trialing_subscriptions = self.db.query(Subscription).filter_by(status="trialing").count()
            past_due_subscriptions = self.db.query(Subscription).filter_by(status="past_due").count()
            canceled_subscriptions = self.db.query(Subscription).filter_by(status="canceled").count()

            # Get revenue metrics
            monthly_revenue = self.db.query(Subscription).filter(
                Subscription.status == "active",
                Subscription.billing_cycle == "monthly"
            ).with_entities(Subscription.amount).all()

            yearly_revenue = self.db.query(Subscription).filter(
                Subscription.status == "active",
                Subscription.billing_cycle == "yearly"
            ).with_entities(Subscription.amount).all()

            total_mrr = sum([sub.amount for sub in monthly_revenue])
            total_arr = sum([sub.amount for sub in yearly_revenue])

            # Get churn metrics
            thirty_days_ago = datetime.utcnow() - timedelta(days=30)
            recent_cancellations = self.db.query(Subscription).filter(
                Subscription.canceled_at >= thirty_days_ago
            ).count()

            # Get invoice statistics
            total_invoices = self.db.query(Invoice).count()
            paid_invoices = self.db.query(Invoice).filter_by(status="paid").count()
            open_invoices = self.db.query(Invoice).filter_by(status="open").count()
            overdue_invoices = self.db.query(Invoice).filter(
                Invoice.status == "open",
                Invoice.due_date <= datetime.utcnow()
            ).count()

            # Calculate payment success rate
            payment_success_rate = (paid_invoices / total_invoices * 100) if total_invoices > 0 else 0

            # Calculate churn rate
            churn_rate = (recent_cancellations / total_subscriptions * 100) if total_subscriptions > 0 else 0

            report = {
                "timestamp": datetime.utcnow().isoformat(),
                "subscriptions": {
                    "total": total_subscriptions,
                    "active": active_subscriptions,
                    "trialing": trialing_subscriptions,
                    "past_due": past_due_subscriptions,
                    "canceled": canceled_subscriptions,
                    "health_score": (active_subscriptions / total_subscriptions * 100) if total_subscriptions > 0 else 0
                },
                "revenue": {
                    "mrr": round(total_mrr, 2),
                    "arr": round(total_arr, 2),
                    "projected_annual": round((total_mrr * 12) + total_arr, 2)
                },
                "invoices": {
                    "total": total_invoices,
                    "paid": paid_invoices,
                    "open": open_invoices,
                    "overdue": overdue_invoices,
                    "payment_success_rate": round(payment_success_rate, 2)
                },
                "churn": {
                    "recent_cancellations": recent_cancellations,
                    "churn_rate": round(churn_rate, 2),
                    "status": "healthy" if churn_rate < 5 else "warning" if churn_rate < 10 else "critical"
                }
            }

            logger.info(f"✓ Generated billing health report")
            return report

        except Exception as e:
            logger.error(f"✗ Failed to generate billing health report: {e}")
            raise

    # ===========================
    # PAYMENT METHOD VERIFICATION
    # ===========================

    def _verify_stripe_payment_method(self, subscription: Subscription) -> bool:
        """
        Verify Stripe payment method is valid and not expiring soon

        Args:
            subscription: Subscription to verify

        Returns:
            True if payment method is valid
        """
        try:
            if not subscription.stripe_payment_method_id:
                return False

            payment_method = self.stripe.get_payment_method(
                subscription.stripe_payment_method_id
            )

            if not payment_method:
                return False

            # Check if card is expiring in next 30 days
            if payment_method.type == "card":
                card = payment_method.card
                exp_date = datetime(card.exp_year, card.exp_month, 1)
                days_until_expiry = (exp_date - datetime.utcnow()).days

                if days_until_expiry <= 30:
                    logger.warning(f"⚠ Payment method expiring soon for subscription {subscription.id}")
                    return False

            return True

        except Exception as e:
            logger.error(f"✗ Failed to verify payment method: {e}")
            return False

    # ===========================
    # NOTIFICATION HELPERS
    # ===========================

    def _send_renewal_reminder(self, subscription: Subscription, days_remaining: int) -> None:
        """Send renewal reminder email"""
        logger.info(f"📧 Sending renewal reminder to subscription {subscription.id} ({days_remaining} days)")
        # Email notification will be implemented in email service

    def _send_trial_ending_reminder(self, subscription: Subscription, days_remaining: int) -> None:
        """Send trial ending reminder"""
        logger.info(f"📧 Sending trial ending reminder to subscription {subscription.id} ({days_remaining} days)")

    def _send_payment_method_issue_alert(self, subscription: Subscription) -> None:
        """Send payment method issue alert"""
        logger.warning(f"📧 Sending payment method issue alert to subscription {subscription.id}")

    def _send_grace_period_ending_notice(self, subscription: Subscription) -> None:
        """Send grace period ending notice"""
        logger.warning(f"📧 Sending grace period ending notice to subscription {subscription.id}")

    def _send_cancellation_notice(self, subscription: Subscription, reason: str) -> None:
        """Send cancellation notice"""
        logger.info(f"📧 Sending cancellation notice to subscription {subscription.id} (reason: {reason})")

    def _send_cancellation_confirmation(self, subscription: Subscription) -> None:
        """Send cancellation confirmation"""
        logger.info(f"📧 Sending cancellation confirmation to subscription {subscription.id}")

    def _send_expiration_notice(self, subscription: Subscription) -> None:
        """Send expiration notice"""
        logger.info(f"📧 Sending expiration notice to subscription {subscription.id}")

    def _send_overdue_invoice_reminder(self, invoice: Invoice, days_overdue: int) -> None:
        """Send overdue invoice reminder"""
        logger.warning(f"📧 Sending overdue invoice reminder for invoice {invoice.id} ({days_overdue} days)")


# ===========================
# SCHEDULED TASK ORCHESTRATOR
# ===========================

class BillingScheduler:
    """
    Orchestrates scheduled billing tasks
    To be called by cron jobs or background workers
    """

    def __init__(self, db: Session):
        """Initialize billing scheduler"""
        self.db = db
        self.billing = BillingAutomationService(db)

    def run_hourly_tasks(self) -> Dict:
        """Run tasks that should execute hourly"""
        logger.info("⏰ Running hourly billing tasks")

        results = {
            "failed_payments": self.billing.process_failed_payments(),
            "overdue_invoices": self.billing.process_overdue_invoices()
        }

        logger.info("✓ Hourly billing tasks completed")
        return results

    def run_daily_tasks(self) -> Dict:
        """Run tasks that should execute daily"""
        logger.info("⏰ Running daily billing tasks")

        results = {
            "upcoming_renewals": self.billing.process_upcoming_renewals(days_ahead=7),
            "trial_expirations": self.billing.process_trial_expirations(days_ahead=3),
            "lifecycle": self.billing.process_subscription_lifecycle(),
            "sync": self.billing.sync_all_active_subscriptions(),
            "health_report": self.billing.generate_billing_health_report()
        }

        logger.info("✓ Daily billing tasks completed")
        return results

    def run_weekly_tasks(self) -> Dict:
        """Run tasks that should execute weekly"""
        logger.info("⏰ Running weekly billing tasks")

        results = {
            "full_sync": self.billing.sync_all_active_subscriptions(),
            "health_report": self.billing.generate_billing_health_report()
        }

        logger.info("✓ Weekly billing tasks completed")
        return results
