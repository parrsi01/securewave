#!/usr/bin/env python3
"""Verify and optionally consume a SecureWave Ed25519 operation approval."""

from __future__ import annotations

import argparse
import base64
import binascii
import fcntl
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

try:  # Support both direct CLI execution and package-based tests.
    from cli_operation_common import (
        PacketValidationError,
        ensure_external_path,
        is_placeholder,
        parse_utc,
        validate_target_reference,
    )
except ModuleNotFoundError:  # pragma: no cover - import mode depends on invocation
    from scripts.cli_operation_common import (
        PacketValidationError,
        ensure_external_path,
        is_placeholder,
        parse_utc,
        validate_target_reference,
    )


class ApprovalVerificationError(ValueError):
    """Raised for any invalid, expired, mismatched, or replayed approval."""


ROOT = Path(__file__).resolve().parents[1]


REQUIRED_FIELDS = {
    "schema_version",
    "approval_id",
    "issuer_key_id",
    "environment",
    "target_ref",
    "candidate_sha",
    "operation",
    "not_before_utc",
    "expires_at_utc",
    "recipient_allowlist",
    "nonce",
    "signature",
}

EMAIL_CANARY_OPERATIONS = {"smtp_canary", "sendgrid_canary"}


def canonical_payload(approval: Mapping[str, Any]) -> bytes:
    unsigned = {key: value for key, value in approval.items() if key != "signature"}
    return json.dumps(
        unsigned,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("utf-8")


def _load_public_key(path: Path):
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    except ImportError as exc:  # pragma: no cover - depends on runtime environment
        raise ApprovalVerificationError("cryptography dependency is unavailable") from exc

    try:
        raw = path.read_bytes()
        key = serialization.load_pem_public_key(raw)
    except Exception as exc:
        raise ApprovalVerificationError("approval public key could not be read") from exc
    if not isinstance(key, Ed25519PublicKey):
        raise ApprovalVerificationError("approval public key is not Ed25519")
    return key


def _decode_signature(value: Any) -> bytes:
    if not isinstance(value, str) or not value:
        raise ApprovalVerificationError("approval signature is missing")
    try:
        return base64.b64decode(value.encode("ascii"), validate=True)
    except (UnicodeEncodeError, binascii.Error) as exc:
        raise ApprovalVerificationError("approval signature is not valid base64") from exc


def _validate_shape(approval: Mapping[str, Any]) -> None:
    missing = REQUIRED_FIELDS - set(approval)
    if missing:
        raise ApprovalVerificationError("approval is missing required fields")
    unexpected = set(approval) - REQUIRED_FIELDS
    if unexpected:
        raise ApprovalVerificationError("approval contains unsupported fields")
    if approval.get("schema_version") != 1:
        raise ApprovalVerificationError("unsupported approval schema")
    for field in ("approval_id", "issuer_key_id", "operation", "nonce"):
        value = approval.get(field)
        if not isinstance(value, str) or is_placeholder(value) or any(char.isspace() for char in value):
            raise ApprovalVerificationError(f"approval field is invalid: {field}")
    candidate_sha = approval.get("candidate_sha")
    if not isinstance(candidate_sha, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", candidate_sha):
        raise ApprovalVerificationError("approval candidate SHA is invalid")
    environment = approval.get("environment")
    if environment not in {"staging", "production"}:
        raise ApprovalVerificationError("approval environment is invalid")
    target_ref = approval.get("target_ref")
    if not isinstance(target_ref, str):
        raise ApprovalVerificationError("approval target reference is invalid")
    try:
        validate_target_reference(target_ref)
    except PacketValidationError as exc:
        raise ApprovalVerificationError("approval target reference is invalid") from exc
    recipients = approval.get("recipient_allowlist")
    if not isinstance(recipients, list) or any(
        not isinstance(item, str)
        or not re.fullmatch(r"[^@\s,]+@[^@\s,]+\.[^@\s,]+", item)
        for item in recipients
    ):
        raise ApprovalVerificationError("approval recipient allowlist is invalid")
    if approval.get("operation") in EMAIL_CANARY_OPERATIONS and not recipients:
        raise ApprovalVerificationError(
            "email canary approval must contain a non-empty recipient allowlist"
        )
    try:
        parse_utc(str(approval["not_before_utc"]), "not_before_utc")
        parse_utc(str(approval["expires_at_utc"]), "expires_at_utc")
    except PacketValidationError as exc:
        raise ApprovalVerificationError("approval time window is invalid") from exc


def _read_approval(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ApprovalVerificationError("approval file is unreadable or malformed") from exc
    if not isinstance(value, dict):
        raise ApprovalVerificationError("approval file must contain a JSON object")
    _validate_shape(value)
    return value


def _approval_is_current(approval: Mapping[str, Any], now: datetime) -> None:
    try:
        start = parse_utc(str(approval["not_before_utc"]), "not_before_utc")
        end = parse_utc(str(approval["expires_at_utc"]), "expires_at_utc")
    except PacketValidationError as exc:
        raise ApprovalVerificationError("approval time window is invalid") from exc
    if end <= start:
        raise ApprovalVerificationError("approval window is invalid")
    if now < start or now > end:
        raise ApprovalVerificationError("approval window is not currently valid")


def _approval_is_consumed(ledger_path: Path, approval_id: str) -> bool:
    if not ledger_path.exists():
        return False
    try:
        lines = ledger_path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ApprovalVerificationError("approval ledger is unreadable") from exc
    for line in lines:
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ApprovalVerificationError("approval ledger is malformed") from exc
        if isinstance(record, dict) and record.get("approval_id") == approval_id:
            return True
    return False


def consume_approval(ledger_path: Path, approval_id: str, *, now: datetime) -> None:
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with ledger_path.open("a+", encoding="utf-8") as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            handle.seek(0)
            for line in handle:
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise ApprovalVerificationError("approval ledger is malformed") from exc
                if isinstance(record, dict) and record.get("approval_id") == approval_id:
                    raise ApprovalVerificationError("approval has already been consumed")
            handle.seek(0, os.SEEK_END)
            handle.write(
                json.dumps(
                    {
                        "approval_id": approval_id,
                        "consumed_at_utc": now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
                    },
                    sort_keys=True,
                )
                + "\n"
            )
            handle.flush()
            os.fsync(handle.fileno())
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    except ApprovalVerificationError:
        raise
    except OSError as exc:
        raise ApprovalVerificationError("approval ledger could not be updated") from exc


def verify_approval(
    *,
    approval_file: Path,
    public_key_file: Path,
    ledger_file: Path,
    operation: str,
    environment: str,
    target_ref: str,
    candidate_sha: str,
    recipient: str | None = None,
    consume: bool = False,
    now: datetime | None = None,
    repository_root: Path | None = None,
) -> dict[str, Any]:
    repository_root = repository_root or ROOT
    for path, label in (
        (approval_file, "approval_file"),
        (public_key_file, "approval_public_key_file"),
        (ledger_file, "approval_ledger_file"),
    ):
        try:
            ensure_external_path(str(path), repository_root, label)
        except PacketValidationError as exc:
            raise ApprovalVerificationError(str(exc)) from exc

    approval = _read_approval(approval_file)
    if approval["operation"] != operation:
        raise ApprovalVerificationError("approval operation does not match")
    if approval["environment"] != environment:
        raise ApprovalVerificationError("approval environment does not match")
    if approval["target_ref"] != target_ref:
        raise ApprovalVerificationError("approval target does not match")
    if approval["candidate_sha"].lower() != candidate_sha.lower():
        raise ApprovalVerificationError("approval candidate SHA does not match")
    if operation in EMAIL_CANARY_OPERATIONS and recipient is None:
        raise ApprovalVerificationError(
            "recipient is required when verifying an email canary approval"
        )
    if recipient is not None and recipient not in approval["recipient_allowlist"]:
        raise ApprovalVerificationError("recipient is not allowlisted by approval")

    current = now or datetime.now(timezone.utc)
    _approval_is_current(approval, current)
    public_key = _load_public_key(public_key_file)
    try:
        public_key.verify(_decode_signature(approval["signature"]), canonical_payload(approval))
    except Exception as exc:
        raise ApprovalVerificationError("approval signature is invalid") from exc

    if _approval_is_consumed(ledger_file, str(approval["approval_id"])):
        raise ApprovalVerificationError("approval has already been consumed")
    if consume:
        consume_approval(ledger_file, str(approval["approval_id"]), now=current)
    return {
        "approval_id": approval["approval_id"],
        "issuer_key_id": approval["issuer_key_id"],
        "operation": approval["operation"],
        "environment": approval["environment"],
        "recipient_allowlist_count": len(approval["recipient_allowlist"]),
        "consumed": consume,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approval-file", required=True, type=Path)
    parser.add_argument("--public-key-file", required=True, type=Path)
    parser.add_argument("--ledger-file", required=True, type=Path)
    parser.add_argument("--operation", required=True)
    parser.add_argument("--environment", required=True)
    parser.add_argument("--target-ref", required=True)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--recipient")
    parser.add_argument("--consume", action="store_true")
    args = parser.parse_args()

    try:
        result = verify_approval(
            approval_file=args.approval_file,
            public_key_file=args.public_key_file,
            ledger_file=args.ledger_file,
            operation=args.operation,
            environment=args.environment,
            target_ref=args.target_ref,
            candidate_sha=args.candidate_sha,
            recipient=args.recipient,
            consume=args.consume,
        )
    except ApprovalVerificationError as exc:
        print(f"APPROVAL_STATUS=BLOCKED:{exc}", file=sys.stderr)
        return 2
    print("APPROVAL_STATUS=PASS")
    print(f"APPROVAL_ID={result['approval_id']}")
    print(f"APPROVAL_CONSUMED={str(result['consumed']).lower()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
