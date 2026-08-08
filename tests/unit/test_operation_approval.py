import base64
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

cryptography = pytest.importorskip("cryptography")
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from scripts.verify_operation_approval import (
    ApprovalVerificationError,
    canonical_payload,
    verify_approval,
)


def _write_approval(
    tmp_path: Path,
    candidate_sha: str = "a" * 40,
    operation: str = "smtp_canary",
    artifact_sha256: str | None = None,
    immutable_image_reference: str | None = None,
):
    private_key = Ed25519PrivateKey.generate()
    public_key_path = tmp_path / "approval-public.pem"
    public_key_path.write_bytes(
        private_key.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    )
    now = datetime.now(timezone.utc)
    approval = {
        "schema_version": 1,
        "approval_id": "approval-001",
        "issuer_key_id": "operator-key-001",
        "environment": "production" if operation == "release_arm64" else "staging",
        "target_ref": "production-fleet-01" if operation == "release_arm64" else "staging-fleet-01",
        "candidate_sha": candidate_sha,
        "operation": operation,
        "not_before_utc": (now - timedelta(minutes=1)).isoformat().replace("+00:00", "Z"),
        "expires_at_utc": (now + timedelta(minutes=10)).isoformat().replace("+00:00", "Z"),
        "recipient_allowlist": ["canary@example.test"],
        "nonce": "nonce-001",
    }
    if operation == "release_arm64":
        approval["artifact_sha256"] = artifact_sha256 or "b" * 64
        approval["immutable_image_reference"] = immutable_image_reference or (
            "registry.example.test/securewave@sha256:" + "c" * 64
        )
    approval["signature"] = base64.b64encode(private_key.sign(canonical_payload(approval))).decode("ascii")
    approval_path = tmp_path / "approval.json"
    approval_path.write_text(json.dumps(approval), encoding="utf-8")
    return approval_path, public_key_path, tmp_path / "approval-ledger.jsonl"


def test_valid_approval_is_consumed_once(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    result = verify_approval(
        approval_file=approval,
        public_key_file=public_key,
        ledger_file=ledger,
        operation="smtp_canary",
        environment="staging",
        target_ref="staging-fleet-01",
        candidate_sha="a" * 40,
        recipient="canary@example.test",
        consume=True,
        repository_root=tmp_path / "repo",
    )
    assert result["consumed"] is True
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            recipient="canary@example.test",
            repository_root=tmp_path / "repo",
        )


def test_approval_target_mismatch_is_rejected(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="different-target",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


def test_invalid_signature_is_rejected(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    payload = json.loads(approval.read_text(encoding="utf-8"))
    payload["signature"] = base64.b64encode(b"invalid-signature").decode("ascii")
    approval.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("environment", "production"),
        ("operation", "deploy_staging"),
        ("candidate_sha", "b" * 40),
    ],
)
def test_approval_context_mismatch_is_rejected(tmp_path: Path, field: str, value: str):
    approval, public_key, ledger = _write_approval(tmp_path)
    payload = json.loads(approval.read_text(encoding="utf-8"))
    payload[field] = value
    approval.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


@pytest.mark.parametrize("time_field", ["expired", "future"])
def test_approval_outside_time_window_is_rejected(tmp_path: Path, time_field: str):
    approval, public_key, ledger = _write_approval(tmp_path)
    now = datetime.now(timezone.utc)
    payload = json.loads(approval.read_text(encoding="utf-8"))
    if time_field == "expired":
        payload["not_before_utc"] = (now - timedelta(hours=2)).isoformat().replace("+00:00", "Z")
        payload["expires_at_utc"] = (now - timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    else:
        payload["not_before_utc"] = (now + timedelta(hours=1)).isoformat().replace("+00:00", "Z")
        payload["expires_at_utc"] = (now + timedelta(hours=2)).isoformat().replace("+00:00", "Z")
    approval.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


def test_recipient_mismatch_is_rejected(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            recipient="other@example.test",
            repository_root=tmp_path / "repo",
        )


def test_smtp_approval_requires_recipient_at_verification_time(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    with pytest.raises(ApprovalVerificationError, match="recipient is required"):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


def test_sendgrid_approval_requires_recipient_at_verification_time(tmp_path: Path):
    approval, public_key, ledger = _write_approval(
        tmp_path,
        operation="sendgrid_canary",
    )
    with pytest.raises(ApprovalVerificationError, match="recipient is required"):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="sendgrid_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


def test_smtp_approval_rejects_empty_signed_allowlist(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    payload = json.loads(approval.read_text(encoding="utf-8"))
    payload["recipient_allowlist"] = []
    approval.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ApprovalVerificationError, match="non-empty recipient"):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            recipient="canary@example.test",
            repository_root=tmp_path / "repo",
        )


def test_sendgrid_approval_rejects_empty_signed_allowlist(tmp_path: Path):
    approval, public_key, ledger = _write_approval(
        tmp_path,
        operation="sendgrid_canary",
    )
    payload = json.loads(approval.read_text(encoding="utf-8"))
    payload["recipient_allowlist"] = []
    approval.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ApprovalVerificationError, match="non-empty recipient"):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="sendgrid_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            recipient="canary@example.test",
            repository_root=tmp_path / "repo",
        )


def test_malformed_approval_is_rejected(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    approval.write_text("[]", encoding="utf-8")
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


def test_approval_with_unsupported_field_is_rejected(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    payload = json.loads(approval.read_text(encoding="utf-8"))
    payload["unsupported"] = "must-not-be-accepted"
    approval.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


def test_approval_with_invalid_recipient_allowlist_is_rejected(tmp_path: Path):
    approval, public_key, ledger = _write_approval(tmp_path)
    payload = json.loads(approval.read_text(encoding="utf-8"))
    payload["recipient_allowlist"] = ["not-an-email"]
    approval.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(ApprovalVerificationError):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="smtp_canary",
            environment="staging",
            target_ref="staging-fleet-01",
            candidate_sha="a" * 40,
            repository_root=tmp_path / "repo",
        )


def test_release_approval_binds_artifact_and_image_digest(tmp_path: Path):
    artifact_sha = "b" * 64
    image_reference = "registry.example.test/securewave@sha256:" + "c" * 64
    approval, public_key, ledger = _write_approval(
        tmp_path,
        operation="release_arm64",
        artifact_sha256=artifact_sha,
        immutable_image_reference=image_reference,
    )

    result = verify_approval(
        approval_file=approval,
        public_key_file=public_key,
        ledger_file=ledger,
        operation="release_arm64",
        environment="production",
        target_ref="production-fleet-01",
        candidate_sha="a" * 40,
        artifact_sha256=artifact_sha,
        immutable_image_reference=image_reference,
        repository_root=tmp_path / "repo",
    )
    assert result["operation"] == "release_arm64"

    with pytest.raises(ApprovalVerificationError, match="artifact SHA"):
        verify_approval(
            approval_file=approval,
            public_key_file=public_key,
            ledger_file=ledger,
            operation="release_arm64",
            environment="production",
            target_ref="production-fleet-01",
            candidate_sha="a" * 40,
            artifact_sha256="d" * 64,
            immutable_image_reference=image_reference,
            repository_root=tmp_path / "repo",
        )
