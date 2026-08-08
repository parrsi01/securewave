from argparse import Namespace
from pathlib import Path

import pytest

from scripts import codex_cli_controller


def test_external_diagnostic_failures_have_stable_controller_blocker():
    assert (
        codex_cli_controller._controller_result("BLOCKED_EXTERNAL_CONNECTIVITY")
        == "BLOCKED_EXTERNAL_ACCESS"
    )
    assert (
        codex_cli_controller._controller_result("BLOCKED_DNS_OR_TLS")
        == "BLOCKED_EXTERNAL_ACCESS"
    )
    assert codex_cli_controller._controller_result("FAIL_INVALID_CREDENTIALS") == "FAIL_INVALID_CREDENTIALS"


def test_candidate_check_rejects_detached_head(monkeypatch):
    candidate = "a" * 40
    monkeypatch.setattr(
        codex_cli_controller,
        "current_git_identity",
        lambda _root: {
            "repository_root": str(codex_cli_controller.ROOT),
            "head": candidate,
            "branch": "",
            "clean": True,
        },
    )

    with pytest.raises(codex_cli_controller.ControllerBlocked, match="branch"):
        codex_cli_controller._check_candidate({"candidate_sha": candidate})


def test_production_login_diagnostic_uses_packet_operation_name(monkeypatch, tmp_path: Path):
    candidate = "a" * 40
    packet = {
        "environment": "production",
        "candidate_sha": candidate,
        "authorized_target_reference": "production-fleet-01",
        "allowed_operations": "login_diagnostic",
    }
    observed: dict[str, str] = {}

    monkeypatch.setattr(codex_cli_controller, "_load_packet", lambda _path: packet)
    monkeypatch.setattr(
        codex_cli_controller,
        "_check_candidate",
        lambda _packet: {"head": candidate, "clean": True},
    )

    def fake_approval(_packet, _args, *, operation, **_kwargs):
        observed["operation"] = operation
        return {"approval_id": "approval-001"}

    monkeypatch.setattr(codex_cli_controller, "_verify_and_consume_approval", fake_approval)
    monkeypatch.setattr(
        codex_cli_controller,
        "_check_api_fingerprint",
        lambda _packet: "https://production.example.test/api",
    )
    monkeypatch.setenv("SECUREWAVE_DIAGNOSTIC_EMAIL", "operator@example.test")
    monkeypatch.setenv("SECUREWAVE_DIAGNOSTIC_PASSWORD", "runtime-only-password")
    monkeypatch.setattr(
        codex_cli_controller,
        "run_diagnostic",
        lambda **_kwargs: ("PASS_LOGIN", tmp_path / "login-diagnostic.json"),
    )
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "_write_controller_evidence",
        lambda _directory, _payload: tmp_path / "controller-result.json",
    )

    result = codex_cli_controller._diagnose(
        Namespace(
            packet=tmp_path / "packet.txt",
            evidence_dir=tmp_path,
            approval_file=tmp_path / "approval.json",
        )
    )

    assert result == 0
    assert observed["operation"] == "login_diagnostic"


def test_diagnose_login_exposes_external_access_blocker(
    monkeypatch, tmp_path: Path, capsys
):
    candidate = "a" * 40
    packet = {
        "environment": "staging",
        "production_excluded": "true",
        "candidate_sha": candidate,
        "authorized_target_reference": "staging-fleet-01",
        "allowed_operations": "login_diagnostic",
    }
    monkeypatch.setattr(codex_cli_controller, "_load_packet", lambda _path: packet)
    monkeypatch.setattr(
        codex_cli_controller,
        "_check_candidate",
        lambda _packet: {"head": candidate, "clean": True},
    )
    monkeypatch.setattr(
        codex_cli_controller,
        "_check_api_fingerprint",
        lambda _packet: "https://staging.example.test/api",
    )
    monkeypatch.setenv("SECUREWAVE_DIAGNOSTIC_EMAIL", "operator@example.test")
    monkeypatch.setenv("SECUREWAVE_DIAGNOSTIC_PASSWORD", "runtime-only-password")
    monkeypatch.setattr(
        codex_cli_controller,
        "run_diagnostic",
        lambda **_kwargs: ("BLOCKED_EXTERNAL_CONNECTIVITY", tmp_path / "login.json"),
    )
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "_write_controller_evidence",
        lambda _directory, _payload: tmp_path / "controller.json",
    )

    result = codex_cli_controller._diagnose(
        Namespace(
            packet=tmp_path / "packet.txt",
            evidence_dir=tmp_path,
            approval_file=None,
        )
    )

    assert result == 2
    output = capsys.readouterr().out
    assert "CONTROLLER_RESULT=BLOCKED_EXTERNAL_ACCESS" in output
    assert "DIAGNOSTIC_RESULT=BLOCKED_EXTERNAL_CONNECTIVITY" in output


def test_deployment_inputs_require_packet_target_and_immutable_image(monkeypatch):
    packet = {"authorized_target_reference": "staging-fleet-01"}
    monkeypatch.delenv("SECUREWAVE_DEPLOY_TARGET_REFERENCE", raising=False)
    monkeypatch.delenv("SECUREWAVE_STAGING_IMAGE", raising=False)

    with pytest.raises(codex_cli_controller.ControllerBlocked):
        codex_cli_controller._check_deployment_inputs(packet, environment="staging")

    monkeypatch.setenv("SECUREWAVE_DEPLOY_TARGET_REFERENCE", "staging-fleet-01")
    monkeypatch.setenv(
        "SECUREWAVE_STAGING_IMAGE",
        "registry.example.test/securewave:release-20260807",
    )
    monkeypatch.setenv("SECUREWAVE_STAGING_HOST", "staging.example.test")
    monkeypatch.setenv("SECUREWAVE_STAGING_USER", "securewave")
    monkeypatch.setenv("SECUREWAVE_STAGING_REMOTE_APP_DIR", "/opt/securewave")
    monkeypatch.setenv("CONFIRM_DEPLOY", "securewave-staging")
    with pytest.raises(codex_cli_controller.ControllerBlocked):
        codex_cli_controller._check_deployment_inputs(packet, environment="staging")

    monkeypatch.setenv(
        "SECUREWAVE_STAGING_IMAGE",
        "registry.example.test/securewave@sha256:" + "a" * 64,
    )
    assert codex_cli_controller._check_deployment_inputs(
        packet,
        environment="staging",
    ) == {
        "target_reference_matches_packet": True,
        "immutable_image_verified": True,
        "environment_confirmation_verified": True,
        "deployment_target_input_verified": True,
    }


@pytest.mark.parametrize(
    ("variable", "value"),
    [
        ("CONFIRM_DEPLOY", "securewave-production"),
        ("SECUREWAVE_STAGING_HOST", "https://staging.example.test"),
        ("SECUREWAVE_STAGING_HOST", "localhost.staging.example.test"),
        ("SECUREWAVE_STAGING_REMOTE_APP_DIR", "/opt/../securewave"),
    ],
)
def test_staging_deployment_inputs_fail_closed_before_approval(
    monkeypatch, variable, value
):
    packet = {"authorized_target_reference": "staging-fleet-01"}
    monkeypatch.setenv("SECUREWAVE_DEPLOY_TARGET_REFERENCE", "staging-fleet-01")
    monkeypatch.setenv(
        "SECUREWAVE_STAGING_IMAGE",
        "registry.example.test/securewave@sha256:" + "a" * 64,
    )
    monkeypatch.setenv("SECUREWAVE_STAGING_HOST", "staging.example.test")
    monkeypatch.setenv("SECUREWAVE_STAGING_USER", "securewave")
    monkeypatch.setenv("SECUREWAVE_STAGING_REMOTE_APP_DIR", "/opt/securewave")
    monkeypatch.setenv("CONFIRM_DEPLOY", "securewave-staging")
    monkeypatch.setenv(variable, value)

    with pytest.raises(codex_cli_controller.ControllerBlocked):
        codex_cli_controller._check_deployment_inputs(packet, environment="staging")


def test_production_deployment_inputs_require_explicit_host_and_confirmation(monkeypatch):
    packet = {"authorized_target_reference": "production-fleet-01"}
    monkeypatch.setenv("SECUREWAVE_DEPLOY_TARGET_REFERENCE", "production-fleet-01")
    monkeypatch.setenv(
        "SECUREWAVE_PRODUCTION_IMAGE",
        "registry.example.test/securewave@sha256:" + "a" * 64,
    )
    monkeypatch.delenv("SECUREWAVE_PRODUCTION_HOST", raising=False)
    monkeypatch.delenv("CONFIRM_DEPLOY", raising=False)

    with pytest.raises(codex_cli_controller.ControllerBlocked):
        codex_cli_controller._check_deployment_inputs(packet, environment="production")

    monkeypatch.setenv("SECUREWAVE_PRODUCTION_HOST", "production.example.test")
    monkeypatch.setenv("CONFIRM_DEPLOY", "securewave-production")
    assert codex_cli_controller._check_deployment_inputs(
        packet,
        environment="production",
    ) == {
        "target_reference_matches_packet": True,
        "immutable_image_verified": True,
        "environment_confirmation_verified": True,
        "deployment_target_input_verified": True,
    }


@pytest.mark.parametrize(
    ("variable", "value"),
    [
        ("SECUREWAVE_PRODUCTION_HOST", "localhost.example.test"),
        ("SECUREWAVE_PRODUCTION_USER", "bad user"),
        ("SECUREWAVE_REMOTE_APP_DIR", "/opt/../securewave"),
    ],
)
def test_production_deployment_inputs_match_wrapper_guards(
    monkeypatch, variable, value
):
    packet = {"authorized_target_reference": "production-fleet-01"}
    monkeypatch.setenv("SECUREWAVE_DEPLOY_TARGET_REFERENCE", "production-fleet-01")
    monkeypatch.setenv(
        "SECUREWAVE_PRODUCTION_IMAGE",
        "registry.example.test/securewave@sha256:" + "a" * 64,
    )
    monkeypatch.setenv("SECUREWAVE_PRODUCTION_HOST", "production.example.test")
    monkeypatch.setenv("CONFIRM_DEPLOY", "securewave-production")
    monkeypatch.setenv(variable, value)

    with pytest.raises(codex_cli_controller.ControllerBlocked):
        codex_cli_controller._check_deployment_inputs(packet, environment="production")


def test_smtp_send_preflights_configuration_before_consuming_approval(
    monkeypatch, tmp_path: Path
):
    packet = {
        "allowed_operations": "smtp_canary",
        "smtp_recipient_allowlist": "canary@example.test",
    }
    approval_called = False

    monkeypatch.setattr(codex_cli_controller, "_load_packet", lambda _path: packet)
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "configuration_status",
        lambda: ("BLOCKED_SMTP_CONFIGURATION_MISSING", {"missing": ["SMTP_PASSWORD"]}),
    )

    def fail_if_approval_is_consumed(*_args, **_kwargs):
        nonlocal approval_called
        approval_called = True
        raise AssertionError("approval must not be consumed for missing SMTP configuration")

    monkeypatch.setattr(
        codex_cli_controller,
        "_verify_and_consume_approval",
        fail_if_approval_is_consumed,
    )

    with pytest.raises(codex_cli_controller.ControllerBlocked):
        codex_cli_controller._smtp(
            Namespace(
                mode="send",
                packet=tmp_path / "packet.txt",
                recipient="canary@example.test",
                approval_file=tmp_path / "approval.json",
                evidence_dir=tmp_path,
            )
        )

    assert approval_called is False


def test_smtp_controller_sends_one_allowlisted_canary_after_approval(
    monkeypatch, tmp_path: Path
):
    candidate = "a" * 40
    packet = {
        "environment": "staging",
        "production_excluded": "true",
        "candidate_sha": candidate,
        "authorized_target_reference": "staging-fleet-01",
        "allowed_operations": "smtp_canary",
        "smtp_recipient_allowlist": "canary@example.test",
    }
    approval_calls: dict[str, object] = {}
    send_calls: list[dict[str, object]] = []

    monkeypatch.setattr(codex_cli_controller, "_load_packet", lambda _path: packet)
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "configuration_status",
        lambda: ("PASS_SMTP_CONFIGURATION_ONLY", {"provider": "smtp", "missing": []}),
    )

    def fake_approval(_packet, _args, *, operation, recipient, **_kwargs):
        approval_calls.update(operation=operation, recipient=recipient)
        return {"approval_id": "approval-001"}

    def fake_send(*, recipient, evidence_dir):
        send_calls.append({"recipient": recipient, "evidence_dir": evidence_dir})
        evidence = tmp_path / "smtp-canary.json"
        evidence.write_text("{}\n", encoding="utf-8")
        return "PASS_SMTP_SUBMISSION_ACCEPTED", evidence

    monkeypatch.setattr(codex_cli_controller, "_verify_and_consume_approval", fake_approval)
    monkeypatch.setattr(codex_cli_controller, "send_canary", fake_send)
    monkeypatch.setattr(
        codex_cli_controller,
        "_write_controller_evidence",
        lambda _directory, _payload: tmp_path / "controller-result.json",
    )

    result = codex_cli_controller._smtp(
        Namespace(
            mode="send",
            packet=tmp_path / "packet.txt",
            recipient="canary@example.test",
            approval_file=tmp_path / "approval.json",
            evidence_dir=tmp_path,
        )
    )

    assert result == 0
    assert approval_calls == {
        "operation": "smtp_canary",
        "recipient": "canary@example.test",
    }
    assert send_calls == [
        {"recipient": "canary@example.test", "evidence_dir": tmp_path}
    ]


def test_sendgrid_send_preflights_configuration_before_consuming_approval(
    monkeypatch, tmp_path: Path
):
    packet = {
        "email_provider": "sendgrid",
        "allowed_operations": "sendgrid_canary",
        "sendgrid_recipient_allowlist": "canary@example.test",
    }
    approval_called = False

    monkeypatch.setattr(codex_cli_controller, "_load_packet", lambda _path: packet)
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "sendgrid_configuration_status",
        lambda: (
            "BLOCKED_SENDGRID_CONFIGURATION_MISSING",
            {"missing": ["SENDGRID_API_KEY"]},
        ),
    )

    def fail_if_approval_is_consumed(*_args, **_kwargs):
        nonlocal approval_called
        approval_called = True
        raise AssertionError("approval must not be consumed for missing SendGrid configuration")

    monkeypatch.setattr(
        codex_cli_controller,
        "_verify_and_consume_approval",
        fail_if_approval_is_consumed,
    )

    with pytest.raises(codex_cli_controller.ControllerBlocked):
        codex_cli_controller._sendgrid(
            Namespace(
                mode="send",
                packet=tmp_path / "packet.txt",
                recipient="canary@example.test",
                approval_file=tmp_path / "approval.json",
                evidence_dir=tmp_path,
            )
        )

    assert approval_called is False


def test_sendgrid_controller_sends_one_allowlisted_canary_after_approval(
    monkeypatch, tmp_path: Path
):
    candidate = "a" * 40
    packet = {
        "environment": "staging",
        "production_excluded": "true",
        "candidate_sha": candidate,
        "authorized_target_reference": "staging-fleet-01",
        "email_provider": "sendgrid",
        "allowed_operations": "sendgrid_canary",
        "sendgrid_recipient_allowlist": "canary@example.test",
    }
    approval_calls: dict[str, object] = {}
    send_calls: list[dict[str, object]] = []

    monkeypatch.setattr(codex_cli_controller, "_load_packet", lambda _path: packet)
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "sendgrid_configuration_status",
        lambda: ("PASS_SENDGRID_CONFIGURATION_ONLY", {"provider": "sendgrid", "missing": []}),
    )

    def fake_approval(_packet, _args, *, operation, recipient, **_kwargs):
        approval_calls.update(operation=operation, recipient=recipient)
        return {"approval_id": "approval-001"}

    def fake_send(*, recipient, evidence_dir):
        send_calls.append({"recipient": recipient, "evidence_dir": evidence_dir})
        evidence = tmp_path / "sendgrid-canary.json"
        evidence.write_text("{}\n", encoding="utf-8")
        return "PASS_SENDGRID_SUBMISSION_ACCEPTED", evidence

    monkeypatch.setattr(codex_cli_controller, "_verify_and_consume_approval", fake_approval)
    monkeypatch.setattr(codex_cli_controller, "sendgrid_canary", fake_send)
    monkeypatch.setattr(
        codex_cli_controller,
        "_write_controller_evidence",
        lambda _directory, _payload: tmp_path / "controller-result.json",
    )

    result = codex_cli_controller._sendgrid(
        Namespace(
            mode="send",
            packet=tmp_path / "packet.txt",
            recipient="canary@example.test",
            approval_file=tmp_path / "approval.json",
            evidence_dir=tmp_path,
        )
    )

    assert result == 0
    assert approval_calls == {
        "operation": "sendgrid_canary",
        "recipient": "canary@example.test",
    }
    assert send_calls == [
        {"recipient": "canary@example.test", "evidence_dir": tmp_path}
    ]


def test_sendgrid_check_only_does_not_require_approval(monkeypatch, tmp_path: Path):
    candidate = "a" * 40
    packet = {
        "environment": "staging",
        "production_excluded": "true",
        "candidate_sha": candidate,
        "authorized_target_reference": "staging-fleet-01",
        "email_provider": "sendgrid",
        "allowed_operations": "sendgrid_check",
    }

    monkeypatch.setattr(codex_cli_controller, "_load_packet", lambda _path: packet)
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "_check_candidate",
        lambda _packet: {"head": candidate, "clean": True},
    )
    monkeypatch.setattr(
        codex_cli_controller,
        "check_sendgrid_configuration",
        lambda *, evidence_dir: (
            "PASS_SENDGRID_CONFIGURATION_ONLY",
            evidence_dir / "sendgrid-canary.json",
        ),
    )
    monkeypatch.setattr(
        codex_cli_controller,
        "_write_controller_evidence",
        lambda _directory, _payload: tmp_path / "controller-result.json",
    )

    result = codex_cli_controller._sendgrid(
        Namespace(
            mode="check-only",
            packet=tmp_path / "packet.txt",
            recipient=None,
            approval_file=None,
            evidence_dir=tmp_path,
        )
    )

    assert result == 0


def test_local_e2e_is_a_fixed_controller_operation(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "run_local_e2e",
        lambda _evidence_dir: ("LOCAL_AUTOMATION_READY", tmp_path / "local-e2e.json"),
    )
    monkeypatch.setattr(
        codex_cli_controller,
        "_write_controller_evidence",
        lambda _directory, _payload: tmp_path / "controller-result.json",
    )

    result = codex_cli_controller._local_e2e(
        Namespace(evidence_dir=tmp_path)
    )

    assert result == 0


def test_local_e2e_failure_is_not_reported_as_unknown(monkeypatch, tmp_path: Path, capsys):
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "run_local_e2e",
        lambda _evidence_dir: (_ for _ in ()).throw(
            codex_cli_controller.LocalE2EError("safe local contract failure")
        ),
    )

    result = codex_cli_controller._local_e2e(
        Namespace(evidence_dir=tmp_path)
    )

    assert result == 3
    assert "CONTROLLER_RESULT=FAIL:safe local contract failure" in capsys.readouterr().err
