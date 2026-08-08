#!/usr/bin/env python3
"""Check SMTP configuration or send one controller-authorized canary.

Direct ``send`` execution is intentionally refused.  The controller must
verify and consume a signed operation approval before calling ``send_canary``.
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


CANARY_SUBJECT = "SecureWave SMTP canary"
CANARY_TEXT = "SecureWave SMTP canary accepted by the configured provider."
CANARY_HTML = "<p>SecureWave SMTP canary accepted by the configured provider.</p>"


class SmtpCanaryError(ValueError):
    """Raised when the canary cannot safely run."""


def _load_email_service():
    # EmailService preserves dotenv loading for the application.  The CLI
    # canary explicitly opts out so only injected process environment values
    # can configure this operation.
    os.environ["SECUREWAVE_CLI_ENV_ONLY"] = "true"
    from services.email_service import EmailService

    return EmailService


def validate_recipient(recipient: str) -> None:
    if not recipient or "\n" in recipient or "\r" in recipient or "," in recipient:
        raise SmtpCanaryError("recipient must be one valid address")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", recipient):
        raise SmtpCanaryError("recipient must be one valid address")


def _safe_config_status(status: dict[str, Any]) -> dict[str, Any]:
    return {
        "provider": status.get("provider"),
        "enabled": bool(status.get("enabled")),
        "missing": list(status.get("missing") or []),
    }


def configuration_status() -> tuple[str, dict[str, Any]]:
    """Inspect injected SMTP configuration without connecting or sending."""

    try:
        service = _load_email_service()()
    except ModuleNotFoundError as exc:
        # The repository's application dependency set includes python-dotenv,
        # but a bare system Python may not have it.  Keep this a deterministic
        # blocker rather than converting a missing local tool into UNKNOWN or
        # attempting to install anything automatically.
        missing_module = exc.name or "required_python_module"
        return "BLOCKED_SMTP_DEPENDENCY_MISSING", {
            "provider": None,
            "enabled": False,
            "missing": [f"python_module:{missing_module}"],
        }
    except (OSError, ValueError):
        # Invalid local SMTP configuration (for example, a non-numeric port)
        # must fail closed without exposing the value or exception text.
        return "BLOCKED_SMTP_CONFIGURATION_INVALID", {
            "provider": None,
            "enabled": False,
            "missing": ["configuration_invalid"],
        }
    status = _safe_config_status(service.config_status())
    if status["provider"] != "smtp":
        result = "BLOCKED_SMTP_PROVIDER_NOT_SELECTED"
    elif status["missing"]:
        result = "BLOCKED_SMTP_CONFIGURATION_MISSING"
    else:
        result = "PASS_SMTP_CONFIGURATION_ONLY"
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
        "delivery_note": "configuration status does not prove SMTP connectivity or inbox delivery",
    }
    destination = write_json_evidence(evidence_dir, "smtp-canary.json", evidence)
    return result, destination


def send_canary(*, recipient: str, evidence_dir: Path) -> tuple[str, Path]:
    validate_recipient(recipient)
    evidence_dir = ensure_external_path(str(evidence_dir), ROOT, "evidence_dir")
    result, status = configuration_status()
    send_attempted = False
    if result != "PASS_SMTP_CONFIGURATION_ONLY":
        sent = False
    else:
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
        result = "PASS_SMTP_SUBMISSION_ACCEPTED" if sent else "FAIL_SMTP_SUBMISSION"
    evidence = {
        "schema_version": 1,
        "result": result,
        "mode": "send",
        "configuration": status,
        "recipient_present": True,
        "send_attempted": send_attempted,
        "submission_accepted": sent,
        "delivery_note": "submission acceptance does not prove inbox delivery",
        "secrets_note": "recipient and SMTP credentials were not written to evidence",
    }
    destination = write_json_evidence(evidence_dir, "smtp-canary.json", evidence)
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
            print("SMTP send is available only through codex_cli_controller.py", file=sys.stderr)
            print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP", file=sys.stderr)
            return 2
    except SmtpCanaryError as exc:
        print(f"SMTP_CANARY_RESULT=BLOCKED_INPUT:{exc}", file=sys.stderr)
        print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP", file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        print(f"SMTP_CANARY_RESULT=UNKNOWN:{type(exc).__name__}", file=sys.stderr)
        print("AUTOMATION_RESULT=UNKNOWN", file=sys.stderr)
        return 4

    print(f"SMTP_CANARY_RESULT={result}")
    print(f"SMTP_CANARY_EVIDENCE={destination}")
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
