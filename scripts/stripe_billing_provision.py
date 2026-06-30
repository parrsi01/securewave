#!/usr/bin/env python3
"""Provision SecureWave Stripe Billing resources and write private release env."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
VENV_PYTHON = ROOT_DIR / ".venv" / "bin" / "python"
if VENV_PYTHON.exists() and Path(sys.executable) != VENV_PYTHON:
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), str(Path(__file__).resolve()), *sys.argv[1:]])

if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from dotenv import load_dotenv

from services.stripe_provisioning import StripeBillingProvisioner


def _load_env_file(path: Path) -> None:
    if path.exists():
        load_dotenv(path, override=True)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create/reuse Stripe Products, Prices, webhook endpoint, and Customer Portal config for SecureWave billing.",
    )
    parser.add_argument(
        "--env-file",
        default=os.getenv("SECUREWAVE_BILLING_RELEASE_ENV_FILE", str(ROOT_DIR / "securewave_private" / "billing_release.env")),
        help="Private env file to load/write. Defaults to securewave_private/billing_release.env.",
    )
    parser.add_argument(
        "--app-url",
        default=os.getenv("APP_URL") or os.getenv("APP_BASE_URL"),
        help="Public app URL used for the Stripe webhook endpoint. Defaults to APP_URL/APP_BASE_URL.",
    )
    parser.add_argument(
        "--currency",
        default=os.getenv("STRIPE_CURRENCY", "usd"),
        help="Currency for recurring Prices. Defaults to usd.",
    )
    parser.add_argument(
        "--allow-test-mode",
        action="store_true",
        help="Allow sk_test_/pk_test_ keys. Production runs should not use this.",
    )
    parser.add_argument(
        "--confirm-live",
        action="store_true",
        help="Required before mutating live Stripe resources.",
    )
    parser.add_argument(
        "--no-write-env-file",
        action="store_true",
        help="Provision Stripe resources but do not write the private env file.",
    )
    return parser


def main() -> int:
    load_dotenv()
    args = _build_parser().parse_args()
    env_file = Path(args.env_file).expanduser().resolve()
    _load_env_file(env_file)

    secret_key = os.getenv("STRIPE_SECRET_KEY") or os.getenv("STRIPE_SECRET") or ""
    publishable_key = os.getenv("STRIPE_PUBLISHABLE_KEY") or ""

    if not args.app_url:
        print("ERROR: APP_URL or --app-url is required.", file=sys.stderr)
        return 2
    if not args.allow_test_mode and not args.confirm_live:
        print("ERROR: pass --confirm-live to create/update live Stripe billing resources.", file=sys.stderr)
        return 2

    try:
        provisioner = StripeBillingProvisioner(
            app_url=args.app_url,
            secret_key=secret_key,
            publishable_key=publishable_key,
            env_file=env_file,
            currency=args.currency,
            allow_test_mode=args.allow_test_mode,
        )
        result = provisioner.provision(write_env_file=not args.no_write_env_file)
    except Exception as exc:
        print(f"ERROR: Stripe billing provisioning failed: {exc}", file=sys.stderr)
        return 1

    print("[PASS] Stripe billing resources are provisioned.")
    for product in result.products.values():
        product_action = "created" if product.created else "reused"
        print(f"[INFO] {product.plan_id}: product {product.product_id} ({product_action})")
        for price in product.prices.values():
            price_action = "created" if price.created else "reused"
            print(f"[INFO] {product.plan_id}/{price.billing_cycle}: {price.price_id} ({price_action})")

    webhook_action = "created" if result.webhook_created else "reused"
    print(f"[INFO] webhook endpoint: {result.webhook_endpoint_id} ({webhook_action})")
    portal_action = "created" if result.portal_created else "updated"
    print(f"[INFO] customer portal config: {result.portal_config_id} ({portal_action})")
    if result.env_file:
        print(f"[PASS] wrote private billing env: {result.env_file}")

    for blocker in result.blockers:
        print(f"[WARN] {blocker}")

    if result.blockers:
        print("[WARN] Run scripts/billing_release_gate.sh after resolving the warnings above.")
        return 1

    print("[NEXT] Run: bash scripts/billing_release_gate.sh --env-file " + str(env_file))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
