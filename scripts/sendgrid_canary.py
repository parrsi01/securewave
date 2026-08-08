#!/usr/bin/env python3
"""Check SendGrid configuration or send one controller-authorized canary.

The canary deliberately uses the application's existing ``EmailService``
provider path.  Direct send execution is refused; the Codex CLI controller
must validate the packet and consume an independent signed approval first.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

try:  # Support both direct CLI execution and package-based tests.
    from cli_operation_common import ensure_external_path, write_json_evidence
except ModuleNotFoundError:  # pragma: no cover - import mode depends on invocation
    from scripts.cli_operation_common import ensure_external_path, write_json_evidence


CANARY_SUBJECT = "SecureWave SendGrid canary"
CANARY_TEXT = "SecureWave SendGrid canary accepted by the configured provider."
CANARY_HTML = "<p>SecureWave SendGrid canary accepted by the configured provider.</p>"


class SendGridCanaryError(ValueError):
    """Raised when the SendGrid canary cannot safely run."""


def _load_email_service():
    """Load the application service with environment-only CLI configuration."""

    os.environ["SECUREWAVE_CLI_ENV_ONLY"] = "true"
    from services.email_service import EmailService

    return EmailService


def _sendgrid_dependency_available() -> bool:
    try:
        import sendgrid  # noqa: F401
    except (ImportError, ModuleNotFoundError):
        return False
    return True


def validate_recipient(recipient: str) -> None:
    if not recipient or "\n" in recipient or "\r" in recipient or "," in recipient:
        raise SendGridCanaryError("recipient must be one valid address")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", recipient):
        raise SendGridCanaryError("recipient must be one valid address")


def _safe_config_status(status: dict[str, Any]) -> dict[str, Any]:
    return {
        "provider": status.get("provider"),
        "enabled": bool(status.get("enabled")),
        "missing": list(status.get("missing") or []),
    }


def configuration_status() -> tuple[str, dict[str, Any]]:
    """Inspect injected SendGrid configuration without connecting or sending."""

    configured_provider = os.getenv("EMAIL_PROVIDER", "").strip().lower()
    if configured_provider != "sendgrid":
        return "BLOCKED_SENDGRID_PROVIDER_NOT_SELECTED", {
            "provider": configured_provider or None,
            "enabled": False,
            "missing": ["EMAIL_PROVIDER=sendgrid"],
        }

    if not _sendgrid_dependency_available():
        return "BLOCKED_SENDGRID_DEPENDENCY_MISSING", {
            "provider": "sendgrid",
            "enabled": False,
            "missing": ["python_module:sendgrid"],
        }

    try:
        service = _load_email_service()()
    except ModuleNotFoundError as exc:
        missing_module = exc.name or "required_python_module"
        return "BLOCKED_SENDGRID_DEPENDENCY_MISSING", {
            "provider": "sendgrid",
            "enabled": False,
            "missing": [f"python_module:{missing_module}"],
        }
    except (OSError, ValueError):
        return "BLOCKED_SENDGRID_CONFIGURATION_INVALID", {
            "provider": "sendgrid",
            "enabled": False,
            "missing": ["configuration_invalid"],
        }

    status = _safe_config_status(service.config_status())
    # The CLI contract is intentionally stricter than the application's
    # backward-compatible FROM_EMAIL fallback to SMTP_FROM_EMAIL/SMTP_USER.
    # A SendGrid staging operation must receive an explicit sender variable;
    # an unrelated SMTP variable cannot silently authorize it.
    explicit_missing = []
    if not os.getenv("SENDGRID_API_KEY"):
        explicit_missing.append("SENDGRID_API_KEY")
    if not os.getenv("FROM_EMAIL"):
        explicit_missing.append("FROM_EMAIL")
    for field in explicit_missing:
        if field not in status["missing"]:
            status["missing"].append(field)
    if status["provider"] != "sendgrid":
        result = "BLOCKED_SENDGRID_PROVIDER_NOT_SELECTED"
    elif status["missing"]:
        result = "BLOCKED_SENDGRID_CONFIGURATION_MISSING"
    else:
        result = "PASS_SENDGRID_CONFIGURATION_ONLY"
    return result, status


def check_configuration(*, evidence_dir: Path) -> tuple[str, Path]:
    evidence_dir = ensure_external_path(str(evidence_dir), ROOT, "evidence_dir")
    result, status = configuration_status()
    evidence = {
        "schema_version": 1,
        "result": result,
        "mode": "check-only",
        "configuration": status,
        "send_attempted": False,
        "delivery_note": "configuration status does not prove SendGrid connectivity or inbox delivery",
    }
    destination = write_json_evidence(evidence_dir, "sendgrid-canary.json", evidence)
    return result, destination


def send_canary(*, recipient: str, evidence_dir: Path) -> tuple[str, Path]:
    validate_recipient(recipient)
    evidence_dir = ensure_external_path(str(evidence_dir), ROOT, "evidence_dir")
    result, status = configuration_status()
    send_attempted = False
    sent = False
    if result == "PASS_SENDGRID_CONFIGURATION_ONLY":
        send_attempted = True
        service = _load_email_service()()
        try:
            sent = bool(
                service.send_email(
                    to_email=recipient,
                    subject=CANARY_SUBJECT,
                    html_content=CANARY_HTML,
                    text_content=CANARY_TEXT,
                )
            )
        except Exception:
            sent = False
        result = "PASS_SENDGRID_SUBMISSION_ACCEPTED" if sent else "FAIL_SENDGRID_SUBMISSION"

    evidence = {
        "schema_version": 1,
        "result": result,
        "mode": "send",
        "configuration": status,
        "recipient_present": True,
        "send_attempted": send_attempted,
        "submission_accepted": sent,
        "delivery_note": "submission acceptance does not prove inbox delivery",
        "secrets_note": "recipient, sender, API key, provider response, and message content were not written to evidence",
    }
    destination = write_json_evidence(evidence_dir, "sendgrid-canary.json", evidence)
    return result, destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("check-only", "send"), required=True)
    parser.add_argument("--recipient")
    parser.add_argument("--evidence-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.mode == "check-only":
            result, destination = check_configuration(evidence_dir=args.evidence_dir)
        else:
            print(
                "SendGrid send is available only through codex_cli_controller.py",
                file=sys.stderr,
            )
            print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP", file=sys.stderr)
            return 2
    except SendGridCanaryError as exc:
        print(f"SENDGRID_CANARY_RESULT=BLOCKED_INPUT:{exc}", file=sys.stderr)
        print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP", file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        print(f"SENDGRID_CANARY_RESULT=UNKNOWN:{type(exc).__name__}", file=sys.stderr)
        print("AUTOMATION_RESULT=UNKNOWN", file=sys.stderr)
        return 4

    print(f"SENDGRID_CANARY_RESULT={result}")
    print(f"SENDGRID_CANARY_EVIDENCE={destination}")
    if result.startswith("PASS_"):
        automation = "READY_FOR_PHASE_0_REVIEW"
        exit_code = 0
    elif result.startswith("BLOCKED_"):
        automation = "BLOCKED_BEFORE_SMTP"
        exit_code = 2
    else:
        automation = "FAIL"
        exit_code = 3
    print(f"AUTOMATION_RESULT={automation}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
