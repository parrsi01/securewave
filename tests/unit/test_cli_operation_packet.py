from datetime import datetime, timedelta, timezone
from pathlib import Path

from scripts.cli_operation_common import fingerprint_api_base, validate_packet


def valid_packet(tmp_path: Path) -> dict[str, str]:
    now = datetime.now(timezone.utc)
    return {
        "packet_version": "2",
        "accountable_owner": "owner-role",
        "approver_role": "approver-role",
        "environment": "staging",
        "authorized_target_reference": "staging-fleet-01",
        "production_excluded": "true",
        "operator": "operator-role",
        "reviewer": "reviewer-role",
        "evidence_owner": "evidence-role",
        "authorization_window_start_utc": (now - timedelta(minutes=1)).isoformat().replace("+00:00", "Z"),
        "authorization_window_end_utc": (now + timedelta(minutes=10)).isoformat().replace("+00:00", "Z"),
        "candidate_sha": "a" * 40,
        "original_expected_sha": "a" * 40,
        "sha_acceptance_decision": "same_candidate",
        "api_base_fingerprint": fingerprint_api_base("https://staging.example.test/api"),
        "headroom_evidence_reference": "evidence-record-01",
        "headroom_result": "target-specific headroom recorded",
        "allowed_operations": "login_diagnostic,smtp_check",
        "smtp_recipient_allowlist": "canary@example.test",
        "approval_public_key_file": str(tmp_path / "approval-public.pem"),
        "approval_ledger_file": str(tmp_path / "approval-ledger.jsonl"),
        "authorized_scope": "phase0_readiness_only",
        "not_authorized": "mock_login,email_verification_bypass,2fa_bypass,SMTP_without_approval,production_deploy,later_phases",
    }


def test_valid_packet_has_no_errors(tmp_path: Path):
    assert validate_packet(valid_packet(tmp_path), repository_root=tmp_path / "repo") == []


def test_packet_rejects_vague_target_and_missing_safety_exclusions(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["authorized_target_reference"] = "staging"
    packet["not_authorized"] = "production_deploy"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("specific" in error for error in errors)
    assert any("mock_login" in error for error in errors)
    assert any("SMTP_without_approval" in error for error in errors)


def test_packet_rejects_hostname_shaped_target_reference(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["authorized_target_reference"] = "staging.example.test"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("not a hostname" in error for error in errors)


def test_packet_rejects_authorization_for_later_phases(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["not_authorized"] = (
        "mock_login,email_verification_bypass,2fa_bypass,"
        "SMTP_without_approval,production_deploy"
    )
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("later_phases" in error for error in errors)


def test_smtp_send_authorization_requires_recipient_allowlist(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["allowed_operations"] = "smtp_canary"
    packet["smtp_recipient_allowlist"] = ""
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("recipient allowlist" in error for error in errors)


def test_sendgrid_operations_require_provider_allowlist_and_safety_exclusion(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["email_provider"] = "sendgrid"
    packet["allowed_operations"] = "sendgrid_check,sendgrid_canary"
    packet["sendgrid_recipient_allowlist"] = "canary@example.test"
    packet["not_authorized"] += ",email_without_approval"

    assert validate_packet(packet, repository_root=tmp_path / "repo") == []

    packet["sendgrid_recipient_allowlist"] = ""
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("sendgrid_canary authorization" in error for error in errors)


def test_sendgrid_operations_reject_wrong_provider_and_missing_exclusion(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["email_provider"] = "smtp"
    packet["allowed_operations"] = "sendgrid_check,sendgrid_canary"
    packet["sendgrid_recipient_allowlist"] = "canary@example.test"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("email_provider=sendgrid" in error for error in errors)
    assert any("email_without_approval" in error for error in errors)

    packet["email_provider"] = "sendgrid"
    packet["not_authorized"] += ",email_without_approval"
    packet["environment"] = "production"
    packet["production_excluded"] = "false"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("staging-only" in error for error in errors)


def test_sendgrid_packet_rejects_secret_like_provider_fields(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["email_provider"] = "sendgrid"
    packet["allowed_operations"] = "sendgrid_check"
    packet["sendgrid_api_key"] = "must-not-be-in-packet"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("secret-like packet field" in error for error in errors)


def test_staging_packet_cannot_authorize_production_deploy(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["allowed_operations"] = "deploy_production"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("must not authorize deploy_production" in error for error in errors)


def test_production_packet_cannot_exclude_production_deploy(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["environment"] = "production"
    packet["production_excluded"] = "false"
    packet["not_authorized"] = "mock_login,email_verification_bypass,2fa_bypass,SMTP_without_approval,production_deploy"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("must not exclude production_deploy" in error for error in errors)


def test_packet_rejects_secret_like_fields(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["smtp_password"] = "must-not-be-in-packet"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("secret-like packet field" in error for error in errors)


def test_packet_rejects_unsupported_fields(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["unreviewed_operation"] = "deploy_anything"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("unsupported packet field:unreviewed_operation" in error for error in errors)

    packet = valid_packet(tmp_path)
    packet["smtp_pass"] = "must-not-be-in-packet"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("secret-like packet field" in error for error in errors)


def test_packet_requires_explicit_acceptance_for_promoted_candidate(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["candidate_sha"] = "b" * 40
    packet["sha_acceptance_decision"] = "accept_promoted_candidate"
    assert validate_packet(packet, repository_root=tmp_path / "repo") == []

    packet["sha_acceptance_decision"] = "same_candidate"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("contradict" in error for error in errors)


def test_packet_rejects_original_sha_requirement_when_candidate_differs(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["candidate_sha"] = "b" * 40
    packet["sha_acceptance_decision"] = "require_original_expected_sha"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("original expected SHA is required" in error for error in errors)


def test_packet_rejects_invalid_smtp_recipient_and_audit_flag(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["smtp_recipient_allowlist"] = "not-an-email"
    packet["read_only_external_audit_authorized"] = "maybe"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("invalid recipient" in error for error in errors)
    assert any("external_audit" in error for error in errors)


def test_packet_rejects_vague_headroom_evidence(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["headroom_evidence_reference"] = "cost-guardrail"
    packet["headroom_result"] = "sufficient"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("target-specific evidence" in error for error in errors)
    assert any("observed target-specific result" in error for error in errors)


def test_packet_rejects_noncanonical_environment_spelling(tmp_path: Path):
    packet = valid_packet(tmp_path)
    packet["environment"] = "PRODUCTION"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("lowercase canonical" in error for error in errors)


def arm64_release_packet(tmp_path: Path) -> dict[str, str]:
    packet = valid_packet(tmp_path)
    packet.update(
        {
            "environment": "production",
            "production_excluded": "false",
            "allowed_operations": "release_arm64,deploy_production",
            "release_branch": "agent/securewave-model-reliability",
            "artifact_platform": "linux",
            "artifact_architecture": "arm64",
            "artifact_sha256": "b" * 64,
            "arm64_validation_target_reference": "arm64-validation-01",
            "public_download_reference": "public-download-01",
            "immutable_image_reference": "registry.example.test/securewave@sha256:" + "c" * 64,
            "authorized_scope": "arm64_release_and_production_publish",
            "not_authorized": "mock_login,email_verification_bypass,2fa_bypass,SMTP_without_approval,later_phases",
        }
    )
    return packet


def test_arm64_release_packet_requires_explicit_artifact_and_target_data(tmp_path: Path):
    packet = arm64_release_packet(tmp_path)
    assert validate_packet(packet, repository_root=tmp_path / "repo") == []

    packet["artifact_architecture"] = "amd64"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("artifact_architecture=arm64" in error for error in errors)


def test_arm64_release_packet_rejects_mutable_image_and_staging_scope(tmp_path: Path):
    packet = arm64_release_packet(tmp_path)
    packet["immutable_image_reference"] = "registry.example.test/securewave:latest"
    packet["authorized_scope"] = "phase0_readiness_only"
    errors = validate_packet(packet, repository_root=tmp_path / "repo")
    assert any("immutable_image_reference" in error for error in errors)
    assert any("authorized_scope" in error for error in errors)
