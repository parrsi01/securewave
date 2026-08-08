#!/usr/bin/env python3
"""Shared fail-closed helpers for SecureWave CLI-only operations.

This module intentionally contains no network, SSH, SMTP, or deployment
side-effects.  It parses the non-secret operator packet, validates paths and
time windows, and provides redaction helpers for evidence written outside the
repository.
"""

from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import urlsplit, urlunsplit


PLACEHOLDER_VALUES = {
    "",
    "n/a",
    "na",
    "none",
    "null",
    "tbd",
    "todo",
    "unknown",
    "later",
    "soon",
    "to-be-decided",
}

VAGUE_TARGET_REFERENCES = {
    "dev",
    "development",
    "local",
    "prod",
    "production",
    "staging",
    "stage",
    "test",
    "testing",
    "unknown",
}

# A target packet carries an approved inventory/reference identifier, not the
# concrete host used by an SSH or HTTP client.  Reject DNS-shaped values here
# so an operator cannot accidentally substitute a guessed hostname for the
# accountable inventory record.  References without dots (for example,
# ``staging-fleet-01``) remain valid and are still required to be explicit.
HOSTNAME_LIKE_TARGET = re.compile(
    r"(?=.{1,253}$)"
    r"(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+"
    r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
)

REQUIRED_PACKET_FIELDS = (
    "packet_version",
    "accountable_owner",
    "approver_role",
    "environment",
    "authorized_target_reference",
    "production_excluded",
    "operator",
    "reviewer",
    "evidence_owner",
    "authorization_window_start_utc",
    "authorization_window_end_utc",
    "candidate_sha",
    "original_expected_sha",
    "sha_acceptance_decision",
    "api_base_fingerprint",
    "headroom_evidence_reference",
    "headroom_result",
    "allowed_operations",
    "approval_public_key_file",
    "approval_ledger_file",
    "authorized_scope",
    "not_authorized",
)

OPTIONAL_PACKET_FIELDS = {
    "email_provider",
    "sendgrid_recipient_allowlist",
    "smtp_recipient_allowlist",
    "read_only_external_audit_authorized",
    "release_branch",
    "artifact_platform",
    "artifact_architecture",
    "artifact_sha256",
    "api_base_fingerprint",
    "arm64_validation_target_reference",
    "public_download_reference",
    "immutable_image_reference",
}

KNOWN_PACKET_FIELDS = set(REQUIRED_PACKET_FIELDS) | OPTIONAL_PACKET_FIELDS

ALLOWED_PACKET_OPERATIONS = {
    "login_diagnostic",
    "sendgrid_check",
    "sendgrid_canary",
    "smtp_check",
    "smtp_canary",
    "deploy_staging",
    "deploy_production",
    "release_arm64",
}

REQUIRED_NOT_AUTHORIZED = {
    "mock_login",
    "email_verification_bypass",
    "2fa_bypass",
    "SMTP_without_approval",
    "later_phases",
}

VAGUE_HEADROOM_REFERENCES = {
    "documentation",
    "docs",
    "general-documentation",
    "general-cost-guardrail",
    "cost-guardrail",
    "repository-test",
    "runbook",
}

VAGUE_HEADROOM_RESULTS = {
    "adequate",
    "available",
    "capacity is sufficient",
    "capacity sufficient",
    "good",
    "headroom available",
    "looks good",
    "ok",
    "pass",
    "sufficient",
    "true",
    "yes",
}


class PacketValidationError(ValueError):
    """Raised when the non-secret operator packet is not fail-closed valid."""


def parse_key_value_file(path: Path) -> dict[str, str]:
    """Parse a simple ``key=value`` operator packet.

    The format intentionally does not support shell expansion, quoting, or
    command substitution.  A packet is data, not a shell script.
    """

    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise PacketValidationError(f"unable to read packet: {type(exc).__name__}") from exc

    for line_number, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise PacketValidationError(f"packet line {line_number} is not key=value data")
        key, value = line.split("=", 1)
        key = key.strip()
        if not key or not re.fullmatch(r"[A-Za-z0-9_]+", key):
            raise PacketValidationError(f"packet line {line_number} has an invalid key")
        if key in values:
            raise PacketValidationError(f"packet key is duplicated: {key}")
        values[key] = value.strip()
    return values


def is_placeholder(value: str | None) -> bool:
    return (value or "").strip().lower() in PLACEHOLDER_VALUES


def parse_csv(value: str | None) -> list[str]:
    return [item.strip() for item in (value or "").split(",") if item.strip()]


def parse_utc(value: str, field_name: str) -> datetime:
    text = value.strip()
    if not text.endswith("Z"):
        raise PacketValidationError(f"{field_name} must use an explicit UTC Z suffix")
    try:
        parsed = datetime.fromisoformat(text[:-1] + "+00:00")
    except ValueError as exc:
        raise PacketValidationError(f"{field_name} is not valid UTC") from exc
    if parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        raise PacketValidationError(f"{field_name} must be UTC")
    return parsed.astimezone(timezone.utc)


def validate_target_reference(value: str) -> None:
    """Reject vague or URL/IP-shaped values without guessing an inventory ID."""

    candidate = value.strip()
    if is_placeholder(candidate):
        raise PacketValidationError("authorized_target_reference is missing")
    if candidate.lower() in VAGUE_TARGET_REFERENCES:
        raise PacketValidationError("authorized_target_reference must be specific")
    if any(character.isspace() for character in candidate):
        raise PacketValidationError("authorized_target_reference must not contain whitespace")
    if "://" in candidate or "/" in candidate:
        raise PacketValidationError("authorized_target_reference must be an inventory reference, not a URL/path")
    if HOSTNAME_LIKE_TARGET.fullmatch(candidate):
        raise PacketValidationError(
            "authorized_target_reference must be an inventory reference, not a hostname"
        )
    try:
        ipaddress.ip_address(candidate)
    except ValueError:
        return
    raise PacketValidationError("authorized_target_reference must not be a raw IP address")


def ensure_external_path(path_value: str, repository_root: Path, label: str) -> Path:
    """Resolve a path and reject files stored inside the repository."""

    if is_placeholder(path_value):
        raise PacketValidationError(f"{label} is missing")
    path = Path(path_value).expanduser().resolve(strict=False)
    root = repository_root.resolve()
    try:
        path.relative_to(root)
    except ValueError:
        return path
    raise PacketValidationError(f"{label} must be outside the repository")


def fingerprint_api_base(api_base_url: str) -> str:
    """Return a non-secret fingerprint for an explicit API base URL."""

    parsed = urlsplit(api_base_url.strip())
    canonical = urlunsplit(
        (
            parsed.scheme.lower(),
            parsed.netloc.lower(),
            parsed.path.rstrip("/") or "/",
            "",
            "",
        )
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def validate_packet(
    packet: Mapping[str, str],
    *,
    repository_root: Path,
    now: datetime | None = None,
) -> list[str]:
    """Return all packet validation errors without printing packet values."""

    errors: list[str] = []
    unknown_fields = set(packet) - KNOWN_PACKET_FIELDS
    for field in sorted(unknown_fields):
        errors.append(f"unsupported packet field:{field}")
    for key in packet:
        normalized_key = key.strip().lower()
        if any(
            marker in normalized_key
            for marker in (
                "password",
                "passwd",
                "passphrase",
                "smtp_pass",
                "token",
                "secret",
                "credential",
                "api_key",
                "private_key",
                "privatekey",
            )
        ):
            errors.append(f"secret-like packet field is not allowed:{key}")
    for field in REQUIRED_PACKET_FIELDS:
        if field not in packet or is_placeholder(packet.get(field)):
            errors.append(f"missing:{field}")

    if packet.get("packet_version") not in {"2"}:
        errors.append("packet_version must be 2")

    raw_environment = packet.get("environment", "").strip()
    environment = raw_environment.lower()
    if environment not in {"staging", "production"}:
        errors.append("environment must be staging or production")
    elif raw_environment != environment:
        errors.append("environment must use lowercase canonical spelling")

    production_excluded = packet.get("production_excluded", "").strip().lower()
    if production_excluded not in {"true", "false"}:
        errors.append("production_excluded must be explicitly true or false")
    elif environment == "staging" and production_excluded != "true":
        errors.append("staging packet must set production_excluded=true")
    elif environment == "production" and production_excluded != "false":
        errors.append("production packet must set production_excluded=false")

    target = packet.get("authorized_target_reference", "")
    if target and not is_placeholder(target):
        try:
            validate_target_reference(target)
        except PacketValidationError as exc:
            errors.append(str(exc))

    candidate_sha = packet.get("candidate_sha", "")
    if candidate_sha and not re.fullmatch(r"[0-9a-fA-F]{40}", candidate_sha):
        errors.append("candidate_sha must be a 40-character Git SHA")

    original_expected_sha = packet.get("original_expected_sha", "")
    if original_expected_sha and not re.fullmatch(r"[0-9a-fA-F]{40}", original_expected_sha):
        errors.append("original_expected_sha must be a 40-character Git SHA")
    sha_decision = packet.get("sha_acceptance_decision", "").strip().lower()
    allowed_sha_decisions = {
        "same_candidate",
        "accept_promoted_candidate",
        "require_original_expected_sha",
    }
    if sha_decision and sha_decision not in allowed_sha_decisions:
        errors.append("sha_acceptance_decision is not explicit")
    if (
        re.fullmatch(r"[0-9a-fA-F]{40}", candidate_sha or "")
        and re.fullmatch(r"[0-9a-fA-F]{40}", original_expected_sha or "")
        and sha_decision
    ):
        same_sha = candidate_sha.lower() == original_expected_sha.lower()
        if same_sha and sha_decision != "same_candidate":
            errors.append("sha_acceptance_decision contradicts matching SHAs")
        if not same_sha and sha_decision == "same_candidate":
            errors.append("sha_acceptance_decision contradicts differing SHAs")
        if not same_sha and sha_decision == "require_original_expected_sha":
            errors.append("original expected SHA is required but candidate differs")

    fingerprint = packet.get("api_base_fingerprint", "")
    if fingerprint and not re.fullmatch(r"[0-9a-fA-F]{64}", fingerprint):
        errors.append("api_base_fingerprint must be a SHA-256 hex fingerprint")

    release_operation = "release_arm64" in set(parse_csv(packet.get("allowed_operations")))
    if release_operation:
        if environment != "production":
            errors.append("release_arm64 is production-only")
        if production_excluded != "false":
            errors.append("release_arm64 requires production_excluded=false")
        release_branch = packet.get("release_branch", "").strip()
        if is_placeholder(release_branch) or any(char.isspace() for char in release_branch):
            errors.append("release_branch is required for release_arm64")
        elif ".." in release_branch or release_branch.startswith("-"):
            errors.append("release_branch is not a valid Git branch reference")

        if packet.get("artifact_platform", "").strip().lower() != "linux":
            errors.append("release_arm64 requires artifact_platform=linux")
        if packet.get("artifact_architecture", "").strip().lower() != "arm64":
            errors.append("release_arm64 requires artifact_architecture=arm64")
        if not re.fullmatch(r"[0-9a-fA-F]{64}", packet.get("artifact_sha256", "")):
            errors.append("release_arm64 requires a SHA-256 artifact_sha256")
        validation_target = packet.get("arm64_validation_target_reference", "")
        if is_placeholder(validation_target):
            errors.append("release_arm64 requires arm64_validation_target_reference")
        else:
            try:
                validate_target_reference(validation_target)
            except PacketValidationError as exc:
                errors.append(f"invalid ARM64 validation target: {exc}")
        if is_placeholder(packet.get("public_download_reference")):
            errors.append("release_arm64 requires public_download_reference")
        image_reference = packet.get("immutable_image_reference", "").strip()
        if not re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9._/@:-]*@sha256:[a-fA-F0-9]{64}",
            image_reference,
        ):
            errors.append("release_arm64 requires an immutable_image_reference digest")
        if "deploy_production" not in set(parse_csv(packet.get("allowed_operations"))):
            errors.append("release_arm64 requires deploy_production authorization")

    headroom_reference = packet.get("headroom_evidence_reference", "").strip().lower()
    if headroom_reference in VAGUE_HEADROOM_REFERENCES:
        errors.append(
            "headroom_evidence_reference must identify target-specific evidence"
        )
    headroom_result = packet.get("headroom_result", "").strip().lower()
    if headroom_result in VAGUE_HEADROOM_RESULTS:
        errors.append(
            "headroom_result must state an observed target-specific result"
        )

    allowed_operations = parse_csv(packet.get("allowed_operations"))
    if not allowed_operations:
        errors.append("allowed_operations is empty")
    for operation in allowed_operations:
        if operation not in ALLOWED_PACKET_OPERATIONS:
            errors.append(f"unknown operation:{operation}")
    allowed_operation_set = set(allowed_operations)
    if environment == "staging" and "deploy_production" in allowed_operation_set:
        errors.append("staging packet must not authorize deploy_production")
    if environment == "production" and "deploy_staging" in allowed_operation_set:
        errors.append("production packet must not authorize deploy_staging")
    email_provider = packet.get("email_provider", "").strip().lower()
    sendgrid_allowlist = parse_csv(packet.get("sendgrid_recipient_allowlist"))
    if email_provider and email_provider != "sendgrid":
        errors.append("email_provider must be sendgrid when present")
    if "sendgrid_check" in allowed_operation_set or "sendgrid_canary" in allowed_operation_set:
        if email_provider != "sendgrid":
            errors.append("SendGrid operations require email_provider=sendgrid")
        if environment != "staging":
            errors.append("SendGrid operations are staging-only in packet version 2")
        if production_excluded != "true":
            errors.append("SendGrid staging operations require production_excluded=true")
    if "sendgrid_canary" in allowed_operation_set and not sendgrid_allowlist:
        errors.append("sendgrid_canary authorization requires a non-empty recipient allowlist")
    if any(
        "\n" in recipient
        or "\r" in recipient
        or not re.fullmatch(r"[^@\s,]+@[^@\s,]+\.[^@\s,]+", recipient)
        for recipient in sendgrid_allowlist
    ):
        errors.append("sendgrid_recipient_allowlist contains an invalid recipient")
    recipient_allowlist = parse_csv(packet.get("smtp_recipient_allowlist"))
    if "smtp_canary" in allowed_operations and not recipient_allowlist:
        errors.append("smtp_canary authorization requires a non-empty recipient allowlist")
    if any(
        "\n" in recipient
        or "\r" in recipient
        or not re.fullmatch(r"[^@\s,]+@[^@\s,]+\.[^@\s,]+", recipient)
        for recipient in recipient_allowlist
    ):
        errors.append("smtp_recipient_allowlist contains an invalid recipient")

    external_audit = packet.get("read_only_external_audit_authorized")
    if external_audit is not None and external_audit.strip().lower() not in {"true", "false"}:
        errors.append("read_only_external_audit_authorized must be explicitly true or false")

    not_authorized = set(parse_csv(packet.get("not_authorized")))
    missing_safety_exclusions = REQUIRED_NOT_AUTHORIZED - not_authorized
    for exclusion in sorted(missing_safety_exclusions):
        errors.append(f"missing safety exclusion:{exclusion}")
    if "sendgrid_canary" in allowed_operation_set and "email_without_approval" not in not_authorized:
        errors.append("SendGrid canary must exclude email_without_approval")
    if environment == "staging" and "production_deploy" not in not_authorized:
        errors.append("staging packet must exclude production_deploy")
    if environment == "production" and "production_deploy" in not_authorized:
        errors.append("production packet must not exclude production_deploy")

    if packet.get("authorized_scope", "").strip() not in {
        "phase0_readiness_only",
        "arm64_release_and_production_publish",
    }:
        errors.append("authorized_scope is not recognized")
    if release_operation and packet.get("authorized_scope", "").strip() != "arm64_release_and_production_publish":
        errors.append("release_arm64 requires authorized_scope=arm64_release_and_production_publish")

    starts_at: datetime | None = None
    ends_at: datetime | None = None
    for field in ("authorization_window_start_utc", "authorization_window_end_utc"):
        value = packet.get(field, "")
        if value and not is_placeholder(value):
            try:
                parsed = parse_utc(value, field)
                if field.endswith("start_utc"):
                    starts_at = parsed
                else:
                    ends_at = parsed
            except PacketValidationError as exc:
                errors.append(str(exc))
    if starts_at and ends_at:
        if ends_at <= starts_at:
            errors.append("authorization window end must be after start")
        current = now or datetime.now(timezone.utc)
        if current < starts_at or current > ends_at:
            errors.append("authorization window is not currently valid")

    for path_field in ("approval_public_key_file", "approval_ledger_file"):
        value = packet.get(path_field, "")
        if value and not is_placeholder(value):
            try:
                ensure_external_path(value, repository_root, path_field)
            except PacketValidationError as exc:
                errors.append(str(exc))

    return errors


def operation_allowed(packet: Mapping[str, str], operation: str) -> bool:
    return operation in set(parse_csv(packet.get("allowed_operations")))


def redact_email(value: str) -> str:
    if "@" not in value:
        return "[redacted-email]"
    return "[redacted-email]"


def redact_text(value: str) -> str:
    """Remove common secrets, emails, URLs, and bearer values from text."""

    text = str(value)
    text = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "[redacted-email]", text)
    text = re.sub(r"(?i)Bearer\s+[A-Za-z0-9._~+/=-]+", "Bearer [redacted-token]", text)
    text = re.sub(r"https?://[^\s'\"]+", "[redacted-url]", text)
    text = re.sub(
        r"(?i)\b(password|passwd|secret|token|authorization|private[_-]?key)\b\s*[:=]\s*[^\s,;]+",
        r"\1=[redacted]",
        text,
    )
    text = re.sub(r"\b[A-Za-z0-9_-]{24,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b", "[redacted-token]", text)
    return text


def write_json_evidence(evidence_dir: Path, filename: str, payload: Mapping[str, Any]) -> Path:
    evidence_dir.mkdir(parents=True, exist_ok=True)
    destination = evidence_dir / filename
    destination.write_text(
        json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    try:
        os.chmod(destination, 0o600)
    except OSError:
        pass
    return destination


def run_git(*arguments: str, repository_root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *arguments],
        cwd=repository_root,
        text=True,
        capture_output=True,
        check=False,
    )


def current_git_identity(repository_root: Path) -> dict[str, Any]:
    root = run_git("rev-parse", "--show-toplevel", repository_root=repository_root)
    head = run_git("rev-parse", "HEAD", repository_root=repository_root)
    branch = run_git("branch", "--show-current", repository_root=repository_root)
    status = run_git("status", "--short", "--branch", repository_root=repository_root)
    if root.returncode or head.returncode or branch.returncode or status.returncode:
        raise RuntimeError("unable to read Git identity")
    return {
        "repository_root": root.stdout.strip(),
        "head": head.stdout.strip(),
        "branch": branch.stdout.strip(),
        "status": redact_text(status.stdout.strip()),
        "clean": not bool(status.stdout.strip().splitlines()[1:]),
    }
