#!/usr/bin/env python3
"""
SecureWave VPN - Billing Automation Cron Jobs
Scheduled tasks for subscription management and billing operations

Usage:
    python billing_cron.py hourly    # Run hourly tasks
    python billing_cron.py daily     # Run daily tasks
    python billing_cron.py weekly    # Run weekly tasks
    python billing_cron.py all       # Run all tasks (testing only)

Crontab setup:
    # Hourly tasks (every hour)
    0 * * * * cd /path/to/securewave && python scripts/billing_cron.py hourly >> logs/billing_hourly.log 2>&1

    # Daily tasks (3 AM every day)
    0 3 * * * cd /path/to/securewave && python scripts/billing_cron.py daily >> logs/billing_daily.log 2>&1

    # Weekly tasks (Sunday 4 AM)
    0 4 * * 0 cd /path/to/securewave && python scripts/billing_cron.py weekly >> logs/billing_weekly.log 2>&1
"""

import sys
import os
import logging
from datetime import datetime
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.session import SessionLocal
from services.billing_automation import BillingScheduler


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(f'logs/billing_cron_{datetime.now().strftime("%Y%m%d")}.log')
    ]
)

logger = logging.getLogger(__name__)


def run_hourly_tasks():
    """Run hourly billing tasks"""
    logger.info("=" * 80)
    logger.info("STARTING HOURLY BILLING TASKS")
    logger.info("=" * 80)

    db = SessionLocal()
    try:
        scheduler = BillingScheduler(db)
        results = scheduler.run_hourly_tasks()

        logger.info("HOURLY TASKS RESULTS:")
        logger.info(f"  Failed Payments Processed: {results['failed_payments']['total']}")
        logger.info(f"  Payment Retry Attempts: {results['failed_payments']['retry_attempts']}")
        logger.info(f"  Successfully Recovered: {results['failed_payments']['successfully_recovered']}")
        logger.info(f"  Overdue Invoices Processed: {results['overdue_invoices']['total']}")
        logger.info(f"  Reminders Sent: {results['overdue_invoices']['reminders_sent']}")

        logger.info("✓ HOURLY TASKS COMPLETED SUCCESSFULLY")
        return 0

    except Exception as e:
        logger.error(f"✗ HOURLY TASKS FAILED: {e}", exc_info=True)
        return 1

    finally:
        db.close()
        logger.info("=" * 80)


def run_daily_tasks():
    """Run daily billing tasks"""
    logger.info("=" * 80)
    logger.info("STARTING DAILY BILLING TASKS")
    logger.info("=" * 80)

    db = SessionLocal()
    try:
        scheduler = BillingScheduler(db)
        results = scheduler.run_daily_tasks()

        logger.info("DAILY TASKS RESULTS:")
        logger.info(f"  Upcoming Renewals Processed: {results['upcoming_renewals']['total']}")
        logger.info(f"  Renewal Reminders Sent: {results['upcoming_renewals']['reminders_sent']}")
        logger.info(f"  Trial Expirations Processed: {results['trial_expirations']['total']}")
        logger.info(f"  Expired Trials: {results['lifecycle']['expired_trials']}")
        logger.info(f"  Expired Subscriptions: {results['lifecycle']['expired_subscriptions']}")
        logger.info(f"  Pending Cancellations: {results['lifecycle']['pending_cancellations']}")
        logger.info(f"  Subscriptions Synced: {results['sync']['total']}")

        # Log health report
        health = results['health_report']
        logger.info("BILLING HEALTH REPORT:")
        logger.info(f"  Active Subscriptions: {health['subscriptions']['active']}/{health['subscriptions']['total']}")
        logger.info(f"  Health Score: {health['subscriptions']['health_score']:.1f}%")
        logger.info(f"  MRR: ${health['revenue']['mrr']:.2f}")
        logger.info(f"  ARR: ${health['revenue']['arr']:.2f}")
        logger.info(f"  Payment Success Rate: {health['invoices']['payment_success_rate']:.1f}%")
        logger.info(f"  Churn Rate: {health['churn']['churn_rate']:.2f}% ({health['churn']['status']})")

        logger.info("✓ DAILY TASKS COMPLETED SUCCESSFULLY")
        return 0

    except Exception as e:
        logger.error(f"✗ DAILY TASKS FAILED: {e}", exc_info=True)
        return 1

    finally:
        db.close()
        logger.info("=" * 80)


def run_weekly_tasks():
    """Run weekly billing tasks"""
    logger.info("=" * 80)
    logger.info("STARTING WEEKLY BILLING TASKS")
    logger.info("=" * 80)

    db = SessionLocal()
    try:
        scheduler = BillingScheduler(db)
        results = scheduler.run_weekly_tasks()

        logger.info("WEEKLY TASKS RESULTS:")
        logger.info(f"  Full Sync Completed: {results['full_sync']['total']} subscriptions")
        logger.info(f"  Stripe Synced: {results['full_sync']['stripe_synced']}")
        logger.info(f"  PayPal Synced: {results['full_sync']['paypal_synced']}")

        # Log health report
        health = results['health_report']
        logger.info("WEEKLY HEALTH REPORT:")
        logger.info(f"  Total Subscriptions: {health['subscriptions']['total']}")
        logger.info(f"  Active: {health['subscriptions']['active']}")
        logger.info(f"  Trialing: {health['subscriptions']['trialing']}")
        logger.info(f"  Past Due: {health['subscriptions']['past_due']}")
        logger.info(f"  Canceled: {health['subscriptions']['canceled']}")
        logger.info(f"  Projected Annual Revenue: ${health['revenue']['projected_annual']:.2f}")

        logger.info("✓ WEEKLY TASKS COMPLETED SUCCESSFULLY")
        return 0

    except Exception as e:
        logger.error(f"✗ WEEKLY TASKS FAILED: {e}", exc_info=True)
        return 1

    finally:
        db.close()
        logger.info("=" * 80)


def run_all_tasks():
    """Run all tasks (for testing purposes)"""
    logger.warning("Running ALL tasks - this should only be used for testing!")

    exit_code = 0

    logger.info("\n" + "=" * 80)
    logger.info("RUNNING HOURLY TASKS")
    logger.info("=" * 80)
    if run_hourly_tasks() != 0:
        exit_code = 1

    logger.info("\n" + "=" * 80)
    logger.info("RUNNING DAILY TASKS")
    logger.info("=" * 80)
    if run_daily_tasks() != 0:
        exit_code = 1

    logger.info("\n" + "=" * 80)
    logger.info("RUNNING WEEKLY TASKS")
    logger.info("=" * 80)
    if run_weekly_tasks() != 0:
        exit_code = 1

    return exit_code


def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print(__doc__)
        print("\nError: Task type required")
        print("Usage: python billing_cron.py {hourly|daily|weekly|all}")
        sys.exit(1)

    task_type = sys.argv[1].lower()

    # Create logs directory if it doesn't exist
    os.makedirs('logs', exist_ok=True)

    logger.info(f"Billing Cron Job Started - Task Type: {task_type}")
    logger.info(f"Timestamp: {datetime.now().isoformat()}")

    if task_type == "hourly":
        exit_code = run_hourly_tasks()
    elif task_type == "daily":
        exit_code = run_daily_tasks()
    elif task_type == "weekly":
        exit_code = run_weekly_tasks()
    elif task_type == "all":
        exit_code = run_all_tasks()
    else:
        logger.error(f"Invalid task type: {task_type}")
        print(f"Error: Invalid task type '{task_type}'")
        print("Valid options: hourly, daily, weekly, all")
        exit_code = 1

    logger.info(f"Billing Cron Job Finished - Exit Code: {exit_code}")
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
