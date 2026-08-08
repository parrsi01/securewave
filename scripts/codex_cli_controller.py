#!/usr/bin/env python3
"""Single fail-closed command surface for SecureWave Codex CLI operations."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

try:  # Support both direct CLI execution and package-based tests.
    from cli_operation_common import (
        PacketValidationError,
        current_git_identity,
        ensure_external_path,
        fingerprint_api_base,
        is_placeholder,
        operation_allowed,
        parse_csv,
        parse_key_value_file,
        redact_text,
        run_git,
        validate_packet,
        write_json_evidence,
    )
    from login_diagnostic import DiagnosticInputError, normalize_api_base, run_diagnostic
    from codex_local_e2e import LocalE2EError, run_local_e2e
    from codex_local_deb import LocalDebBlocked, LocalDebError, run_local_deb
    from codex_workflow import WorkflowInputError, run_workflow
    from release_arm64 import Arm64ReleaseBlocked, run_preflight as run_arm64_preflight, run_publish as run_arm64_publish
    from login_provenance import main as provenance_main
    from sendgrid_canary import (
        SendGridCanaryError,
        check_configuration as check_sendgrid_configuration,
        configuration_status as sendgrid_configuration_status,
        send_canary as sendgrid_canary,
        validate_recipient as validate_sendgrid_recipient,
    )
    from smtp_canary import (
        SmtpCanaryError,
        check_configuration,
        configuration_status,
        send_canary,
        validate_recipient,
    )
    from verify_operation_approval import ApprovalVerificationError, verify_approval
except ModuleNotFoundError:  # pragma: no cover - import mode depends on invocation
    from scripts.cli_operation_common import (
        PacketValidationError,
        current_git_identity,
        ensure_external_path,
        fingerprint_api_base,
        is_placeholder,
        operation_allowed,
        parse_csv,
        parse_key_value_file,
        redact_text,
        run_git,
        validate_packet,
        write_json_evidence,
    )
    from scripts.login_diagnostic import (
        DiagnosticInputError,
        normalize_api_base,
        run_diagnostic,
    )
    from scripts.codex_local_e2e import LocalE2EError, run_local_e2e
    from scripts.codex_local_deb import LocalDebBlocked, LocalDebError, run_local_deb
    from scripts.codex_workflow import WorkflowInputError, run_workflow
    from scripts.release_arm64 import (
        Arm64ReleaseBlocked,
        run_preflight as run_arm64_preflight,
        run_publish as run_arm64_publish,
    )
    from scripts.login_provenance import main as provenance_main
    from scripts.sendgrid_canary import (
        SendGridCanaryError,
        check_configuration as check_sendgrid_configuration,
        configuration_status as sendgrid_configuration_status,
        send_canary as sendgrid_canary,
        validate_recipient as validate_sendgrid_recipient,
    )
    from scripts.smtp_canary import (
        SmtpCanaryError,
        check_configuration,
        configuration_status,
        send_canary,
        validate_recipient,
    )
    from scripts.verify_operation_approval import ApprovalVerificationError, verify_approval


ROOT = Path(__file__).resolve().parents[1]


class ControllerBlocked(RuntimeError):
    """Raised when a controller prerequisite is absent or contradictory."""


def _automation_result(result: str) -> str:
    if result in {"LOCAL_AUTOMATION_READY", "LOCAL_PACKAGE_READY"}:
        return "READY_FOR_PHASE_0_REVIEW"
    if result == "ARM64_RELEASE_CANDIDATE":
        return "READY_FOR_PHASE_0_REVIEW"
    if result.startswith("PASS_"):
        return "READY_FOR_PHASE_0_REVIEW"
    if result.startswith("BLOCKED_"):
        return "BLOCKED_BEFORE_SMTP"
    if result.startswith("FAIL_"):
        return "FAIL"
    return "UNKNOWN"


def _controller_result(result: str) -> str:
    """Expose a stable external-access blocker without losing diagnostics."""

    if result in {"BLOCKED_EXTERNAL_CONNECTIVITY", "BLOCKED_DNS_OR_TLS"}:
        return "BLOCKED_EXTERNAL_ACCESS"
    return result


def _evidence_dir(value: Path) -> Path:
    try:
        return ensure_external_path(str(value), ROOT, "evidence_dir")
    except PacketValidationError as exc:
        raise ControllerBlocked(str(exc)) from exc


def _load_packet(path: Path) -> dict[str, str]:
    try:
        ensure_external_path(str(path), ROOT, "operator packet")
        packet = parse_key_value_file(path)
        errors = validate_packet(packet, repository_root=ROOT)
    except PacketValidationError as exc:
        raise ControllerBlocked(str(exc)) from exc
    if errors:
        raise ControllerBlocked("operator packet validation failed")
    # Packet validation is not complete until the candidate is the current,
    # locally present commit on a clean worktree.  Keeping this check at the
    # controller boundary prevents a valid-looking packet from being reused
    # against a different checkout or dirty candidate.
    _check_candidate(packet)
    return packet


def _check_candidate(packet: dict[str, str]) -> dict[str, Any]:
    identity = current_git_identity(ROOT)
    if Path(identity["repository_root"]).resolve() != ROOT.resolve():
        raise ControllerBlocked("current repository root does not match the controller root")
    if not identity["branch"]:
        raise ControllerBlocked("current Git branch is not known")
    if not identity["clean"]:
        raise ControllerBlocked("repository worktree is not clean")
    if identity["head"].lower() != packet["candidate_sha"].lower():
        raise ControllerBlocked("operator packet candidate SHA does not match current HEAD")
    cat_file = run_git("cat-file", "-e", f"{packet['candidate_sha']}^{{commit}}", repository_root=ROOT)
    if cat_file.returncode != 0:
        raise ControllerBlocked("operator packet candidate SHA is not present locally")
    return identity


def _check_api_fingerprint(packet: dict[str, str]) -> str:
    api_base = os.environ.get("SECUREWAVE_API_BASE_URL", "")
    if not api_base:
        raise ControllerBlocked("SECUREWAVE_API_BASE_URL is not supplied")
    try:
        actual = fingerprint_api_base(api_base)
    except Exception as exc:
        raise ControllerBlocked("SECUREWAVE_API_BASE_URL could not be fingerprinted") from exc
    if actual.lower() != packet["api_base_fingerprint"].lower():
        raise ControllerBlocked("API base fingerprint does not match the operator packet")
    return api_base


def _approval_paths(packet: dict[str, str], args: argparse.Namespace) -> tuple[Path, Path, Path]:
    approval_file = Path(args.approval_file).expanduser() if args.approval_file else None
    public_key_file = Path(packet["approval_public_key_file"]).expanduser()
    ledger_file = Path(packet["approval_ledger_file"]).expanduser()
    if approval_file is None:
        raise ControllerBlocked("signed approval file is required")
    try:
        approval_file = ensure_external_path(str(approval_file), ROOT, "approval_file")
        public_key_file = ensure_external_path(
            str(public_key_file), ROOT, "approval_public_key_file"
        )
        ledger_file = ensure_external_path(str(ledger_file), ROOT, "approval_ledger_file")
    except PacketValidationError as exc:
        raise ControllerBlocked(str(exc)) from exc
    return approval_file, public_key_file, ledger_file


def _verify_and_consume_approval(
    packet: dict[str, str],
    args: argparse.Namespace,
    *,
    operation: str,
    recipient: str | None = None,
    consume: bool = True,
) -> dict[str, Any]:
    identity = _check_candidate(packet)
    approval_file, public_key_file, ledger_file = _approval_paths(packet, args)
    try:
        return verify_approval(
            approval_file=approval_file,
            public_key_file=public_key_file,
            ledger_file=ledger_file,
            operation=operation,
            environment=packet["environment"],
            target_ref=packet["authorized_target_reference"],
            candidate_sha=identity["head"],
            recipient=recipient,
            consume=consume,
            repository_root=ROOT,
        )
    except ApprovalVerificationError as exc:
        raise ControllerBlocked("signed approval validation failed") from exc


def _write_controller_evidence(evidence_dir: Path, result: dict[str, Any]) -> Path:
    return write_json_evidence(evidence_dir, "controller-result.json", result)


def _local_e2e(args: argparse.Namespace) -> int:
    evidence_dir = _evidence_dir(args.evidence_dir)
    try:
        result, destination = run_local_e2e(evidence_dir)
    except LocalE2EError as exc:
        print(f"CONTROLLER_RESULT=FAIL:{exc}", file=sys.stderr)
        print("AUTOMATION_RESULT=FAIL", file=sys.stderr)
        return 3
    controller_evidence = _write_controller_evidence(
        evidence_dir,
        {
            "operation": "local-e2e",
            "result": result,
            "controller_result": result,
            "evidence_file": destination.name,
            "external_system_status": "not contacted",
        },
    )
    print(f"CONTROLLER_RESULT={result}")
    print(f"CONTROLLER_EVIDENCE={controller_evidence}")
    print("AUTOMATION_RESULT=READY_FOR_PHASE_0_REVIEW")
    return 0


def _local_deb(args: argparse.Namespace) -> int:
    evidence_dir = _evidence_dir(args.evidence_dir)
    try:
        result, destination = run_local_deb(
            api_base=args.api_base,
            output_dir=args.output_dir,
            evidence_dir=evidence_dir,
        )
    except (LocalDebBlocked, LocalDebError, PacketValidationError) as exc:
        raise ControllerBlocked(str(exc)) from exc

    controller_evidence = _write_controller_evidence(
        evidence_dir,
        {
            "operation": "local-deb",
            "result": result,
            "controller_result": result,
            "evidence_file": destination.name,
            "external_system_status": "no application, provider, deployment, or public target contacted",
        },
    )
    print(f"CONTROLLER_RESULT={result}")
    print(f"CONTROLLER_EVIDENCE={controller_evidence}")
    if result == "LOCAL_PACKAGE_READY":
        print("AUTOMATION_RESULT=READY_FOR_PHASE_0_REVIEW")
        return 0
    if result == "BLOCKED_LOCAL_BUILD":
        print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP")
        return 2
    if result == "FAIL":
        print("AUTOMATION_RESULT=FAIL")
        return 3
    print("AUTOMATION_RESULT=UNKNOWN")
    return 4


def _workflow(args: argparse.Namespace) -> int:
    try:
        result = run_workflow(
            evidence_root=args.evidence_dir,
            expected_branch=args.expected_branch,
            expected_sha=args.expected_sha,
            api_base=args.api_base,
            release_packet=args.release_packet,
            staging_packet=args.staging_packet,
            approval_file=args.approval_file,
        )
    except WorkflowInputError as exc:
        raise ControllerBlocked(str(exc)) from exc

    print(f"WORKFLOW_RESULT={result['result']}")
    print(f"WORKFLOW_EVIDENCE={result['run_directory']}")
    print(f"WORKFLOW_SUMMARY_JSON={result['summary_json']}")
    print(f"WORKFLOW_SUMMARY_MD={result['summary_md']}")
    print(f"LOCAL_WORKFLOW_READY={'yes' if result['local_workflow_ready'] else 'no'}")
    print(f"PACKAGE_READY={'yes' if result['package_ready'] else 'no'}")
    print("EXTERNAL_RELEASE_READY=no")
    if result["result"] == "LOCAL_WORKFLOW_READY":
        print("AUTOMATION_RESULT=LOCAL_WORKFLOW_READY")
        return 0
    if result["result"] == "BLOCKED_LOCAL_REMEDIATION":
        print("AUTOMATION_RESULT=BLOCKED_LOCAL_REMEDIATION")
        return 2
    if result["result"] == "FAIL":
        print("AUTOMATION_RESULT=FAIL")
        return 3
    print("AUTOMATION_RESULT=UNKNOWN")
    return 4


def _release_arm64(args: argparse.Namespace) -> int:
    packet = _load_packet(args.packet)
    evidence_dir = _evidence_dir(args.evidence_dir)
    if "release_arm64" not in parse_csv(packet.get("allowed_operations")):
        raise ControllerBlocked("release_arm64 is not authorized by the packet")

    try:
        if args.mode == "preflight":
            result, destination = run_arm64_preflight(
                packet=packet,
                evidence_dir=evidence_dir,
                artifact=args.artifact,
            )
        else:
            if args.artifact is None or args.approval_file is None:
                raise ControllerBlocked(
                    "publish mode requires an external artifact and signed approval file"
                )
            result, destination = run_arm64_publish(
                packet=packet,
                evidence_dir=evidence_dir,
                artifact=args.artifact,
                approval_file=args.approval_file,
            )
    except Arm64ReleaseBlocked as exc:
        raise ControllerBlocked(str(exc)) from exc

    controller_evidence = _write_controller_evidence(
        evidence_dir,
        {
            "operation": "release-arm64",
            "mode": args.mode,
            "result": result,
            "evidence_file": destination.name,
        },
    )
    print(f"CONTROLLER_RESULT={result}")
    print(f"CONTROLLER_EVIDENCE={controller_evidence}")
    if result == "ARM64_RELEASE_CANDIDATE":
        print("AUTOMATION_RESULT=READY_FOR_PHASE_0_REVIEW")
        return 0
    if result.startswith("BLOCKED_"):
        print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP")
        return 2
    print("AUTOMATION_RESULT=FAIL")
    return 3


def _diagnose(args: argparse.Namespace) -> int:
    packet = _load_packet(args.packet)
    _check_candidate(packet)
    try:
        api_base = _check_api_fingerprint(packet)
        api_base = normalize_api_base(api_base)
    except (ControllerBlocked, DiagnosticInputError) as exc:
        raise ControllerBlocked("diagnostic API input is missing or unsafe") from exc
    email = os.environ.get("SECUREWAVE_DIAGNOSTIC_EMAIL", "")
    password = os.environ.get("SECUREWAVE_DIAGNOSTIC_PASSWORD", "")
    if not email or is_placeholder(email) or not password:
        raise ControllerBlocked("diagnostic account credentials are not supplied")
    evidence_dir = _evidence_dir(args.evidence_dir)
    if packet["environment"] == "production":
        if not operation_allowed(packet, "login_diagnostic"):
            raise ControllerBlocked("login_diagnostic is not authorized by the packet")
        # Keep the signed operation name identical to the packet/controller
        # contract. The environment and target are independently bound into
        # the approval, so a production approval cannot be reused for staging.
        _verify_and_consume_approval(packet, args, operation="login_diagnostic")
    elif not operation_allowed(packet, "login_diagnostic"):
        raise ControllerBlocked("login_diagnostic is not authorized by the packet")

    try:
        result, destination = run_diagnostic(
            api_base_url=api_base,
            email=email,
            password=password,
            environment=packet["environment"],
            target_ref=packet["authorized_target_reference"],
            evidence_dir=evidence_dir,
        )
    except DiagnosticInputError as exc:
        raise ControllerBlocked(str(exc)) from exc

    controller_evidence = _write_controller_evidence(
        evidence_dir,
        {
            "operation": "diagnose-login",
            "result": result,
            "controller_result": _controller_result(result),
            "environment": packet["environment"],
            "evidence_file": destination.name,
            "target_reference_present": True,
        },
    )
    print(f"CONTROLLER_RESULT={_controller_result(result)}")
    if _controller_result(result) == "BLOCKED_EXTERNAL_ACCESS":
        print(f"DIAGNOSTIC_RESULT={result}")
    print(f"CONTROLLER_EVIDENCE={controller_evidence}")
    print(f"AUTOMATION_RESULT={_automation_result(result)}")
    return 0 if result == "PASS_LOGIN" else 2 if result.startswith("BLOCKED_") else 3 if result.startswith("FAIL_") else 4


def _smtp(args: argparse.Namespace) -> int:
    packet = _load_packet(args.packet)
    evidence_dir = _evidence_dir(args.evidence_dir)
    if args.mode == "check-only":
        if not operation_allowed(packet, "smtp_check"):
            raise ControllerBlocked("smtp_check is not authorized by the packet")
        # Even a no-send check must be tied to the same clean candidate as the
        # packet. This prevents a stale packet from being treated as current
        # evidence while preserving the no-network/no-SMTP behavior.
        _check_candidate(packet)
        result, destination = check_configuration(evidence_dir=evidence_dir)
    else:
        if not args.recipient:
            raise ControllerBlocked("one recipient is required for an SMTP send")
        try:
            validate_recipient(args.recipient)
        except SmtpCanaryError as exc:
            raise ControllerBlocked(str(exc)) from exc
        if not operation_allowed(packet, "smtp_canary"):
            raise ControllerBlocked("smtp_canary is not authorized by the packet")
        if args.recipient not in parse_csv(packet.get("smtp_recipient_allowlist")):
            raise ControllerBlocked("recipient is not allowlisted by the operator packet")
        configuration_result, _configuration = configuration_status()
        if configuration_result != "PASS_SMTP_CONFIGURATION_ONLY":
            raise ControllerBlocked("SMTP configuration preflight failed")
        _verify_and_consume_approval(
            packet,
            args,
            operation="smtp_canary",
            recipient=args.recipient,
        )
        try:
            result, destination = send_canary(
                recipient=args.recipient,
                evidence_dir=evidence_dir,
            )
        except SmtpCanaryError as exc:
            raise ControllerBlocked(str(exc)) from exc

    controller_evidence = _write_controller_evidence(
        evidence_dir,
        {
            "operation": "smtp-canary",
            "mode": args.mode,
            "result": result,
            "evidence_file": destination.name,
            "recipient_present": bool(args.recipient),
        },
    )
    print(f"CONTROLLER_RESULT={result}")
    print(f"CONTROLLER_EVIDENCE={controller_evidence}")
    print(f"AUTOMATION_RESULT={_automation_result(result)}")
    return 0 if result.startswith("PASS_") else 2 if result.startswith("BLOCKED_") else 3


def _sendgrid(args: argparse.Namespace) -> int:
    packet = _load_packet(args.packet)
    evidence_dir = _evidence_dir(args.evidence_dir)
    if packet.get("email_provider", "").strip().lower() != "sendgrid":
        raise ControllerBlocked("SendGrid operation requires email_provider=sendgrid")
    if packet.get("environment") != "staging" or packet.get("production_excluded") != "true":
        raise ControllerBlocked("SendGrid canary is staging-only and requires production exclusion")

    if args.mode == "check-only":
        if not operation_allowed(packet, "sendgrid_check"):
            raise ControllerBlocked("sendgrid_check is not authorized by the packet")
        _check_candidate(packet)
        result, destination = check_sendgrid_configuration(evidence_dir=evidence_dir)
    else:
        if not args.recipient:
            raise ControllerBlocked("one recipient is required for a SendGrid send")
        try:
            validate_sendgrid_recipient(args.recipient)
        except SendGridCanaryError as exc:
            raise ControllerBlocked(str(exc)) from exc
        if not operation_allowed(packet, "sendgrid_canary"):
            raise ControllerBlocked("sendgrid_canary is not authorized by the packet")
        if args.recipient not in parse_csv(packet.get("sendgrid_recipient_allowlist")):
            raise ControllerBlocked("recipient is not allowlisted by the operator packet")
        configuration_result, _configuration = sendgrid_configuration_status()
        if configuration_result != "PASS_SENDGRID_CONFIGURATION_ONLY":
            raise ControllerBlocked("SendGrid configuration preflight failed")
        _verify_and_consume_approval(
            packet,
            args,
            operation="sendgrid_canary",
            recipient=args.recipient,
        )
        try:
            result, destination = sendgrid_canary(
                recipient=args.recipient,
                evidence_dir=evidence_dir,
            )
        except SendGridCanaryError as exc:
            raise ControllerBlocked(str(exc)) from exc

    controller_evidence = _write_controller_evidence(
        evidence_dir,
        {
            "operation": "sendgrid-canary",
            "mode": args.mode,
            "result": result,
            "evidence_file": destination.name,
            "recipient_present": bool(args.recipient),
        },
    )
    print(f"CONTROLLER_RESULT={result}")
    print(f"CONTROLLER_EVIDENCE={controller_evidence}")
    print(f"AUTOMATION_RESULT={_automation_result(result)}")
    return 0 if result.startswith("PASS_") else 2 if result.startswith("BLOCKED_") else 3


def _run_local_guard() -> dict[str, Any]:
    command = ["bash", "scripts/verify_release_guards.sh"]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
        timeout=300,
    )
    return {
        "command": command,
        "exit_code": completed.returncode,
        "output": redact_text((completed.stdout + "\n" + completed.stderr).strip()),
    }


def _check_deployment_inputs(
    packet: dict[str, str],
    *,
    environment: str,
) -> dict[str, bool]:
    """Bind injected deployment inputs to the packet and require a digest.

    The packet and signed approval carry an inventory reference, while the
    deployment wrapper receives the concrete host/image through the process
    environment.  Requiring the operator to repeat the inventory reference in
    ``SECUREWAVE_DEPLOY_TARGET_REFERENCE`` prevents a host value from being
    silently substituted for an approved target.  The image check is stricter
    than the legacy production wrapper so the controller never authorizes a
    mutable tag.
    """

    supplied_target = os.environ.get("SECUREWAVE_DEPLOY_TARGET_REFERENCE", "").strip()
    if not supplied_target:
        raise ControllerBlocked("SECUREWAVE_DEPLOY_TARGET_REFERENCE is not supplied")
    if supplied_target != packet["authorized_target_reference"]:
        raise ControllerBlocked("deployment target reference does not match the packet")

    image_name = (
        "SECUREWAVE_STAGING_IMAGE"
        if environment == "staging"
        else "SECUREWAVE_PRODUCTION_IMAGE"
    )
    image = os.environ.get(image_name, "").strip()
    if not image:
        raise ControllerBlocked(f"{image_name} is not supplied")
    if not re.fullmatch(
        r"[A-Za-z0-9][A-Za-z0-9._/@:-]*@sha256:[a-fA-F0-9]{64}",
        image,
    ):
        raise ControllerBlocked(f"{image_name} must be a complete sha256 digest")

    expected_confirmation = (
        "securewave-staging" if environment == "staging" else "securewave-production"
    )
    if os.environ.get("CONFIRM_DEPLOY", "") != expected_confirmation:
        raise ControllerBlocked("deployment confirmation does not match the requested environment")

    host_name = (
        "SECUREWAVE_STAGING_HOST"
        if environment == "staging"
        else "SECUREWAVE_PRODUCTION_HOST"
    )
    host = os.environ.get(host_name, "").strip()
    if not host:
        raise ControllerBlocked(f"{host_name} is not supplied")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", host):
        raise ControllerBlocked(f"{host_name} is not a valid host value")
    host_lower = host.lower()
    if (
        host_lower == "localhost"
        or host_lower.startswith("localhost.")
        or host_lower in {"::1", "0.0.0.0"}
        or host_lower.startswith("127.")
    ):
        raise ControllerBlocked(f"{host_name} must not identify a local host")

    if environment == "staging":
        staging_user = os.environ.get("SECUREWAVE_STAGING_USER", "").strip()
        if not staging_user:
            raise ControllerBlocked("SECUREWAVE_STAGING_USER is not supplied")
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", staging_user):
            raise ControllerBlocked("SECUREWAVE_STAGING_USER is not a valid remote user")

        remote_dir = os.environ.get("SECUREWAVE_STAGING_REMOTE_APP_DIR", "").strip()
        if not remote_dir:
            raise ControllerBlocked("SECUREWAVE_STAGING_REMOTE_APP_DIR is not supplied")
        if (
            not re.fullmatch(r"/[A-Za-z0-9._/-]+", remote_dir)
            or "/../" in remote_dir
            or remote_dir.endswith("/..")
            or remote_dir.startswith("../")
        ):
            raise ControllerBlocked(
                "SECUREWAVE_STAGING_REMOTE_APP_DIR is not a safe absolute path"
            )
    else:
        production_user = os.environ.get("SECUREWAVE_PRODUCTION_USER", "securewave").strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", production_user):
            raise ControllerBlocked("SECUREWAVE_PRODUCTION_USER is not a valid remote user")
        production_dir = os.environ.get(
            "SECUREWAVE_REMOTE_APP_DIR", "/opt/securewave"
        ).strip()
        if (
            not re.fullmatch(r"/[A-Za-z0-9._/-]+", production_dir)
            or "/../" in production_dir
            or production_dir.endswith("/..")
            or production_dir.startswith("../")
        ):
            raise ControllerBlocked("SECUREWAVE_REMOTE_APP_DIR is not a safe absolute path")

    return {
        "target_reference_matches_packet": True,
        "immutable_image_verified": True,
        "environment_confirmation_verified": True,
        "deployment_target_input_verified": True,
    }


def _deploy(args: argparse.Namespace) -> int:
    packet = _load_packet(args.packet)
    environment = args.environment.strip().lower()
    if environment != packet["environment"]:
        raise ControllerBlocked("deployment environment does not match the packet")
    evidence_dir = _evidence_dir(args.evidence_dir)
    operation = "deploy_staging" if environment == "staging" else "deploy_production"
    if not operation_allowed(packet, operation):
        raise ControllerBlocked("deployment operation is not authorized by the packet")
    deployment_inputs = _check_deployment_inputs(packet, environment=environment)
    identity = _check_candidate(packet)
    guard = _run_local_guard()
    if guard["exit_code"] != 0:
        raise ControllerBlocked("local release guards did not pass")
    for tool in ("ssh", "scp"):
        if shutil.which(tool) is None:
            raise ControllerBlocked(f"BLOCKED_EXTERNAL_ACCESS: required tool is unavailable:{tool}")
    approval_paths = _approval_paths(packet, args)
    if environment == "staging":
        # The staging wrapper consumes the approval immediately before its
        # first remote mutation.  The controller performs the same signature,
        # target, time, and candidate checks here without consuming it so an
        # approval cannot be consumed before the wrapper is actually reached.
        approval = _verify_and_consume_approval(
            packet,
            args,
            operation=operation,
            consume=False,
        )
    else:
        approval = _verify_and_consume_approval(packet, args, operation=operation)
    env = os.environ.copy()
    # Do not allow an inherited override to select a different compose file or
    # weaken immutable-tag validation inside the existing production script.
    env.pop("SECUREWAVE_COMPOSE_TEMPLATE", None)
    env.pop("SECUREWAVE_ALLOW_AMBIGUOUS_TAG", None)
    if environment == "staging":
        env.update(
            {
                "SECUREWAVE_APPROVAL_FILE": str(approval_paths[0]),
                "SECUREWAVE_APPROVAL_PUBLIC_KEY_FILE": str(approval_paths[1]),
                "SECUREWAVE_APPROVAL_LEDGER_FILE": str(approval_paths[2]),
                "SECUREWAVE_CANDIDATE_SHA": identity["head"],
                "SECUREWAVE_DEPLOY_TARGET_REFERENCE": packet[
                    "authorized_target_reference"
                ],
            }
        )
    script = ROOT / "scripts" / ("deploy_staging.sh" if environment == "staging" else "deploy_production.sh")
    if not script.is_file():
        raise ControllerBlocked("required deployment script is missing")
    completed = subprocess.run(
        [str(script)],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
        timeout=1800,
    )
    if completed.returncode == 0:
        result = "PASS_DEPLOY_COMMAND"
    elif completed.returncode == 2:
        result = "BLOCKED_DEPLOY_GUARD"
    else:
        result = "FAIL_DEPLOY_COMMAND"
    evidence = {
        "operation": "deploy",
        "environment": environment,
        "result": result,
        "repository_root": identity["repository_root"],
        "branch": identity["branch"],
        "candidate_sha": identity["head"],
        "approval_id": approval["approval_id"],
        "deployment_inputs": deployment_inputs,
        "local_release_guard": guard,
        "deployment_command": [str(script)],
        "deployment_exit_code": completed.returncode,
        "deployment_output": redact_text((completed.stdout + "\n" + completed.stderr).strip()),
        "external_system_status": "deployment command executed; post-deployment URL verification is separate",
    }
    destination = _write_controller_evidence(evidence_dir, evidence)
    print(f"CONTROLLER_RESULT={result}")
    print(f"CONTROLLER_EVIDENCE={destination}")
    print(f"AUTOMATION_RESULT={_automation_result(result)}")
    return 0 if completed.returncode == 0 else 2 if completed.returncode == 2 else 3


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    provenance = subparsers.add_parser("reconcile-login-history")
    provenance.add_argument("--evidence-dir", required=True, type=Path)
    provenance.add_argument("--deb-artifact", type=Path)
    provenance.add_argument("--runtime-log", type=Path)
    provenance.add_argument(
        "--installed-root",
        type=Path,
        help="Optional external local filesystem root for fixed installed-file comparison.",
    )

    local_e2e = subparsers.add_parser("local-e2e")
    local_e2e.add_argument("--evidence-dir", required=True, type=Path)

    local_deb = subparsers.add_parser("local-deb")
    local_deb.add_argument("--api-base", required=True)
    local_deb.add_argument("--output-dir", required=True, type=Path)
    local_deb.add_argument("--evidence-dir", required=True, type=Path)

    workflow = subparsers.add_parser(
        "workflow",
        help="run bounded local readiness stages and write external evidence",
    )
    workflow.add_argument("--expected-branch")
    workflow.add_argument("--expected-sha")
    workflow.add_argument("--api-base")
    workflow.add_argument("--release-packet", type=Path)
    workflow.add_argument("--staging-packet", type=Path)
    workflow.add_argument("--approval-file", type=Path)
    workflow.add_argument("--evidence-dir", required=True, type=Path)

    release_arm64 = subparsers.add_parser("release-arm64")
    release_arm64.add_argument("--mode", choices=("preflight", "publish"), required=True)
    release_arm64.add_argument("--packet", required=True, type=Path)
    release_arm64.add_argument("--artifact", type=Path)
    release_arm64.add_argument("--approval-file", type=Path)
    release_arm64.add_argument("--evidence-dir", required=True, type=Path)

    diagnose = subparsers.add_parser("diagnose-login")
    diagnose.add_argument("--packet", required=True, type=Path)
    diagnose.add_argument("--evidence-dir", required=True, type=Path)
    diagnose.add_argument("--approval-file", type=Path)

    smtp = subparsers.add_parser("smtp-canary")
    smtp.add_argument("--mode", choices=("check-only", "send"), required=True)
    smtp.add_argument("--packet", required=True, type=Path)
    smtp.add_argument("--recipient")
    smtp.add_argument("--approval-file", type=Path)
    smtp.add_argument("--evidence-dir", required=True, type=Path)

    sendgrid = subparsers.add_parser("sendgrid-canary")
    sendgrid.add_argument("--mode", choices=("check-only", "send"), required=True)
    sendgrid.add_argument("--packet", required=True, type=Path)
    sendgrid.add_argument("--recipient")
    sendgrid.add_argument("--approval-file", type=Path)
    sendgrid.add_argument("--evidence-dir", required=True, type=Path)

    deploy = subparsers.add_parser("deploy")
    deploy.add_argument("--environment", choices=("staging", "production"), required=True)
    deploy.add_argument("--packet", required=True, type=Path)
    deploy.add_argument("--approval-file", required=True, type=Path)
    deploy.add_argument("--evidence-dir", required=True, type=Path)
    return parser


def main() -> int:
    args = _build_parser().parse_args()
    try:
        if args.command == "reconcile-login-history":
            provenance_args = ["--evidence-dir", str(args.evidence_dir)]
            if args.deb_artifact is not None:
                provenance_args.extend(["--deb-artifact", str(args.deb_artifact)])
            if args.runtime_log is not None:
                provenance_args.extend(["--runtime-log", str(args.runtime_log)])
            if args.installed_root is not None:
                provenance_args.extend(["--installed-root", str(args.installed_root)])
            result = provenance_main(provenance_args)
            print(
                "AUTOMATION_RESULT="
                + ("READY_FOR_PHASE_0_REVIEW" if result == 0 else "FAIL")
            )
            return result
        if args.command == "local-e2e":
            return _local_e2e(args)
        if args.command == "local-deb":
            return _local_deb(args)
        if args.command == "workflow":
            return _workflow(args)
        if args.command == "release-arm64":
            return _release_arm64(args)
        if args.command == "diagnose-login":
            return _diagnose(args)
        if args.command == "smtp-canary":
            return _smtp(args)
        if args.command == "sendgrid-canary":
            return _sendgrid(args)
        if args.command == "deploy":
            return _deploy(args)
        raise ControllerBlocked("unsupported controller command")
    except ControllerBlocked as exc:
        message = str(exc)
        if message.startswith("BLOCKED_EXTERNAL_ACCESS"):
            print("CONTROLLER_RESULT=BLOCKED_EXTERNAL_ACCESS", file=sys.stderr)
        else:
            print(f"CONTROLLER_RESULT=BLOCKED:{message}", file=sys.stderr)
        print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP", file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        print(f"CONTROLLER_RESULT=UNKNOWN:{type(exc).__name__}", file=sys.stderr)
        print("AUTOMATION_RESULT=UNKNOWN", file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main())
