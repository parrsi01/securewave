#!/usr/bin/env python3
"""Run SecureWave's bounded, local Codex CLI readiness workflow.

This module is imported by ``codex_cli_controller.py`` and is not an
independent deployment interface.  It owns only the local stages; provider
canaries and deployment remain explicit controller operations with their
existing packet and signed-approval gates.
"""

from __future__ import annotations

import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

try:  # Support direct CLI execution and package-based imports.
    from cli_operation_common import (
        ensure_external_path,
        redact_text,
        write_json_evidence,
    )
except ModuleNotFoundError:  # pragma: no cover - import mode depends on invocation
    from scripts.cli_operation_common import (
        ensure_external_path,
        redact_text,
        write_json_evidence,
    )


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_VERSION = 1
COMMAND_TIMEOUT_SECONDS = {
    "precheck": 20,
    "validation": 180,
    "local_e2e": 300,
    "package": 1800,
}
PROTECTED_PATHS = (
    ".codex/environments/environment.toml",
    "static/downloads/manifest.json",
)
ENVIRONMENT_GROUPS = {
    "LOCAL_REQUIRED": (),
    "TEST_REQUIRED": (),
    "STAGING_REQUIRED": (
        "SECUREWAVE_API_BASE_URL",
        "SECUREWAVE_DIAGNOSTIC_EMAIL",
        "SECUREWAVE_DIAGNOSTIC_PASSWORD",
        "SECUREWAVE_DEPLOY_TARGET_REFERENCE",
        "SECUREWAVE_STAGING_HOST",
        "SECUREWAVE_STAGING_IMAGE",
        "SECUREWAVE_STAGING_USER",
        "SECUREWAVE_STAGING_REMOTE_APP_DIR",
        "CONFIRM_DEPLOY",
    ),
    "EMAIL_REQUIRED": (
        "EMAIL_PROVIDER",
        "SENDGRID_API_KEY",
        "FROM_EMAIL",
        "SMTP_HOST",
        "SMTP_PORT",
        "SMTP_USER",
        "SMTP_PASSWORD",
    ),
    "PRODUCTION_REQUIRED": (
        "SECUREWAVE_PRODUCTION_HOST",
        "SECUREWAVE_PRODUCTION_IMAGE",
        "SECUREWAVE_PRODUCTION_USER",
        "SECUREWAVE_REMOTE_APP_DIR",
    ),
}


class WorkflowInputError(ValueError):
    """Raised for unsafe or unusable workflow input paths."""


def _status_for_checks(checks: Iterable[dict[str, Any]]) -> str:
    checks = list(checks)
    # Command results are blocking unless a check explicitly marks itself
    # advisory. This keeps a failed validation command from being reported as
    # a passing stage merely because it did not carry a flag.
    blocking = [item for item in checks if item.get("blocks_stage", True)]
    if any(item.get("status") == "FAIL" for item in blocking):
        return "FAIL"
    if any(item.get("status") == "BLOCKED" for item in blocking):
        return "BLOCKED"
    if any(item.get("status") == "UNKNOWN" for item in blocking):
        return "UNKNOWN"
    if not checks or all(item.get("status") == "NOT_RUN" for item in checks):
        return "NOT_RUN"
    return "PASS"


def _has_blocking_check(checks: Iterable[dict[str, Any]], field: str) -> bool:
    """Return whether a failed check blocks a named downstream stage."""

    bad_statuses = {"FAIL", "BLOCKED", "UNKNOWN"}
    return any(
        item.get(field, item.get("blocks_stage", True))
        and item.get("status") in bad_statuses
        for item in checks
    )


def classify_remote_failure(output: str) -> str:
    """Classify Git transport failure without exposing the remote response."""

    lowered = output.lower()
    if any(
        phrase in lowered
        for phrase in (
            "could not resolve host",
            "failed to connect",
            "connection timed out",
            "network is unreachable",
            "operation timed out",
            "couldn't connect",
        )
    ):
        return "BLOCKED_REMOTE_NETWORK"
    if any(
        phrase in lowered
        for phrase in (
            "authentication failed",
            "access denied",
            "repository not found",
            "http 401",
            "http 403",
            "status code 401",
            "status code 403",
        )
    ):
        return "BLOCKED_REMOTE_GIT_AUTH"
    if any(phrase in lowered for phrase in ("not a git repository", "invalid url", "no such remote")):
        return "FAIL_REMOTE_INVALID"
    return "UNKNOWN_REMOTE_GIT"


def _safe_slug(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")
    return slug[:80] or "command"


def _command_text(command: list[str]) -> str:
    return " ".join(shlex.quote(item) for item in command)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _presence(names: Iterable[str]) -> dict[str, str]:
    return {name: "PRESENT" if os.environ.get(name) else "MISSING" for name in names}


def _write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def _run_command(
    *,
    command: list[str],
    display_command: str | None,
    label: str,
    evidence_dir: Path,
    timeout: int,
    env: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Run one bounded command and retain raw output only externally."""

    command_display = display_command or _command_text(command)
    command_dir = evidence_dir / "commands"
    command_dir.mkdir(parents=True, exist_ok=True)
    stdout_path = command_dir / f"{_safe_slug(label)}.stdout.log"
    stderr_path = command_dir / f"{_safe_slug(label)}.stderr.log"
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
            timeout=timeout,
        )
    except FileNotFoundError:
        _write_text(stdout_path, "")
        _write_text(stderr_path, "command not found\n")
        return {
            "command": command_display,
            "exit_code": None,
            "status": "BLOCKED",
            "blocker": "BLOCKED_TOOLCHAIN_MISSING",
            "evidence": {"stdout": str(stdout_path), "stderr": str(stderr_path)},
        }
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        _write_text(stdout_path, str(stdout))
        _write_text(stderr_path, str(stderr) + "\ncommand timed out\n")
        return {
            "command": command_display,
            "exit_code": None,
            "status": "BLOCKED",
            "blocker": "BLOCKED_TOOLCHAIN_TIMEOUT",
            "evidence": {"stdout": str(stdout_path), "stderr": str(stderr_path)},
        }

    _write_text(stdout_path, completed.stdout)
    _write_text(stderr_path, completed.stderr)
    result: dict[str, Any] = {
        "command": command_display,
        "exit_code": completed.returncode,
        "status": "PASS" if completed.returncode == 0 else "FAIL",
        "evidence": {"stdout": str(stdout_path), "stderr": str(stderr_path)},
    }
    redacted_output = redact_text((completed.stdout + "\n" + completed.stderr).strip())
    if redacted_output:
        result["redacted_tail"] = redacted_output[-600:]
    return result


def _new_run_directory(root: Path) -> Path:
    root = ensure_external_path(str(root), ROOT, "workflow evidence root")
    root.mkdir(parents=True, exist_ok=True)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}"
    run_dir = root / f"securewave-codex-workflow-{run_id}"
    run_dir.mkdir()
    return run_dir


def _stage(name: str, checks: list[dict[str, Any]], **extra: Any) -> dict[str, Any]:
    return {"stage": name, "status": _status_for_checks(checks), "checks": checks, **extra}


def _identity() -> dict[str, Any]:
    commands = {
        "root": ["git", "rev-parse", "--show-toplevel"],
        "head": ["git", "rev-parse", "HEAD"],
        "branch": ["git", "branch", "--show-current"],
        "status": ["git", "status", "--short", "--branch"],
    }
    values: dict[str, str] = {}
    for key, command in commands.items():
        completed = subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if completed.returncode != 0:
            raise WorkflowInputError(f"unable to read Git {key}")
        values[key] = completed.stdout.strip()
    status_lines = values["status"].splitlines()
    return {
        "repository_root": values["root"],
        "head": values["head"],
        "branch": values["branch"],
        "status": redact_text(values["status"]),
        "clean": not bool(status_lines[1:]),
    }


def _precheck(
    *,
    evidence_dir: Path,
    expected_branch: str | None,
    expected_sha: str | None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    identity = _identity()
    checks: list[dict[str, Any]] = []
    root_ok = Path(identity["repository_root"]).resolve() == ROOT.resolve()
    checks.append(
        {
            "name": "repository_root",
            "status": "PASS" if root_ok else "FAIL",
            "value": identity["repository_root"],
            "blocks_stage": True,
            "blocks_local_validation": True,
            "blocks_package": True,
        }
    )
    branch_ok = bool(identity["branch"])
    checks.append(
        {
            "name": "current_branch",
            "status": "PASS" if branch_ok else "BLOCKED",
            "value": identity["branch"] if branch_ok else "MISSING",
            "blocker": None if branch_ok else "BLOCKED_BRANCH_UNKNOWN",
            "blocks_stage": True,
            "blocks_local_validation": True,
            "blocks_package": True,
        }
    )
    clean_ok = bool(identity["clean"])
    checks.append(
        {
            "name": "worktree_clean",
            "status": "PASS" if clean_ok else "BLOCKED",
            "value": identity["status"],
            "blocker": None if clean_ok else "BLOCKED_WORKTREE_DIRTY",
            "blocks_stage": True,
            # Local engineering checks can run on intentional edits. Package
            # provenance and release readiness still require a clean tree.
            "blocks_local_validation": False,
            "blocks_package": True,
        }
    )

    for name, actual, expected, blocker in (
        ("expected_branch", identity["branch"], expected_branch, "BLOCKED_EXPECTED_BRANCH_MISMATCH"),
        ("expected_candidate_sha", identity["head"], expected_sha, "BLOCKED_CANDIDATE_CHANGED"),
    ):
        if expected is None:
            checks.append(
                {
                    "name": name,
                    "status": "BLOCKED",
                    "value": "NOT_SUPPLIED",
                    "blocker": "BLOCKED_EXPECTED_CANDIDATE_INPUT",
                    "blocks_stage": False,
                    "blocks_local_validation": False,
                    "blocks_package": False,
                }
            )
        else:
            matches = actual.lower() == expected.lower()
            checks.append(
                {
                    "name": name,
                    "status": "PASS" if matches else "BLOCKED",
                    "value": actual,
                    "expected": expected,
                    "blocker": None if matches else blocker,
                    "blocks_stage": not matches,
                    "blocks_local_validation": False,
                    "blocks_package": not matches,
                }
            )

    protected: dict[str, str] = {}
    for relative in PROTECTED_PATHS:
        path = ROOT / relative
        if not path.is_file():
            checks.append(
                {
                    "name": f"protected:{relative}",
                    "status": "FAIL",
                    "blocker": "FAIL_PROTECTED_FILE_MISSING",
                    "blocks_stage": True,
                    "blocks_local_validation": False,
                    "blocks_package": True,
                }
            )
            continue
        digest = _sha256(path)
        protected[relative] = digest
        checks.append(
            {
                "name": f"protected:{relative}",
                "status": "PASS",
                "sha256": digest,
                "blocks_stage": False,
                "blocks_local_validation": False,
                "blocks_package": False,
            }
        )

    tool_checks: dict[str, Any] = {}
    for name in ("git", "rg", "python3", "bash"):
        tool_checks[name] = "PRESENT" if shutil.which(name) else "MISSING"
    tool_checks["pytest"] = "UNKNOWN"
    pytest_probe = _run_command(
        command=[sys.executable, "-m", "pytest", "--version"],
        display_command="PYDANTIC_DISABLE_PLUGINS=1 PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 python -m pytest --version",
        label="precheck-pytest",
        evidence_dir=evidence_dir,
        timeout=COMMAND_TIMEOUT_SECONDS["precheck"],
        env={**os.environ, "PYDANTIC_DISABLE_PLUGINS": "1", "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1"},
    )
    if pytest_probe["status"] == "PASS":
        tool_checks["pytest"] = "PRESENT"
    elif pytest_probe.get("blocker"):
        tool_checks["pytest"] = pytest_probe["blocker"]
    checks.append(
        {
            "name": "pytest",
            **pytest_probe,
            "blocks_stage": True,
            "blocks_local_validation": True,
            "blocks_package": False,
        }
    )

    docker_platform = "MISSING"
    if shutil.which("docker"):
        docker_probe = _run_command(
            command=["docker", "version", "--format", "{{.Server.Os}}/{{.Server.Arch}}"],
            display_command="docker version --format '{{.Server.Os}}/{{.Server.Arch}}'",
            label="precheck-docker",
            evidence_dir=evidence_dir,
            timeout=COMMAND_TIMEOUT_SECONDS["precheck"],
        )
        if docker_probe["status"] == "PASS":
            docker_platform = docker_probe.get("redacted_tail", "").strip().splitlines()[-1] or "UNKNOWN"
            if docker_platform not in {"linux/arm64", "linux/aarch64"}:
                docker_probe["status"] = "BLOCKED"
                docker_probe["blocker"] = "BLOCKED_ARM64_RUNTIME_REQUIRED"
        else:
            docker_probe["status"] = "BLOCKED"
            docker_probe.setdefault("blocker", "BLOCKED_ARM64_RUNTIME_REQUIRED")
        checks.append(
            {
                "name": "docker",
                **docker_probe,
                "blocks_stage": False,
                "blocks_local_validation": False,
                "blocks_package": True,
            }
        )
    else:
        checks.append(
            {
                "name": "docker",
                "status": "BLOCKED",
                "blocker": "BLOCKED_ARM64_RUNTIME_REQUIRED",
                "blocks_stage": False,
                "blocks_local_validation": False,
                "blocks_package": True,
            }
        )

    checks.append(
        {
            "name": "flutter",
            "status": "PASS" if shutil.which("flutter") else "BLOCKED",
            "value": "PRESENT" if shutil.which("flutter") else "MISSING",
            "blocker": None if shutil.which("flutter") else "BLOCKED_FLUTTER_TOOLCHAIN_MISSING",
            "blocks_stage": False,
            "blocks_local_validation": False,
            "blocks_package": False,
        }
    )

    remote_url = ""
    remote_config = subprocess.run(
        ["git", "config", "--get", "remote.origin.url"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if remote_config.returncode == 0:
        remote_url = remote_config.stdout.strip()
    remote_structurally_valid = bool(
        re.fullmatch(r"https?://[^\s/]+/[^\s]+", remote_url)
        or re.fullmatch(r"git@[^\s:]+:[^\s]+", remote_url)
        or re.fullmatch(r"ssh://[^\s/]+/[^\s]+", remote_url)
    )
    checks.append(
        {
            "name": "origin",
            "status": "PASS" if remote_structurally_valid else "FAIL",
            "value": "PRESENT" if remote_url else "MISSING",
            "blocker": None if remote_structurally_valid else "FAIL_REMOTE_INVALID",
            "blocks_stage": False,
            "blocks_local_validation": False,
            "blocks_package": False,
        }
    )

    remote_probe = _run_command(
        command=["git", "ls-remote", "--heads", "origin"],
        display_command="GIT_TERMINAL_PROMPT=0 git ls-remote --heads origin",
        label="precheck-git-remote",
        evidence_dir=evidence_dir,
        timeout=COMMAND_TIMEOUT_SECONDS["precheck"],
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )
    if remote_probe["status"] == "FAIL":
        raw = ""
        for path_key in ("stdout", "stderr"):
            try:
                raw += "\n" + Path(remote_probe["evidence"][path_key]).read_text(encoding="utf-8")
            except OSError:
                pass
        remote_probe["status"] = "BLOCKED"
        remote_probe["blocker"] = classify_remote_failure(raw)
    if remote_probe["status"] == "PASS":
        raw_lines = remote_probe.get("redacted_tail", "").splitlines()
        remote_probe["remote_branch_names"] = [
            line.split("refs/heads/", 1)[1]
            for line in raw_lines
            if "refs/heads/" in line
        ]
        remote_probe["remote_branch_count"] = len(remote_probe["remote_branch_names"])
    else:
        remote_probe["remote_branch_names"] = []
        remote_probe["remote_branch_count"] = "UNKNOWN"
    remote_probe["name"] = "git_remote_reachability"
    remote_probe["blocks_stage"] = False
    remote_probe["blocks_local_validation"] = False
    remote_probe["blocks_package"] = False
    checks.append(remote_probe)

    host_arch = platform.machine().lower()
    environment_presence = {
        group: _presence(names) for group, names in ENVIRONMENT_GROUPS.items()
    }
    evidence = {
        "repository": identity,
        "expected_branch": expected_branch,
        "expected_candidate_sha": expected_sha,
        "protected_sha256": protected,
        "host_architecture": host_arch,
        "docker_server_platform": docker_platform,
        "tools": tool_checks,
        "environment_presence": environment_presence,
        "origin_url_present": bool(remote_url),
        "remote": remote_probe,
    }
    return _stage("PRECHECK", checks, identity=identity, evidence=evidence), evidence


def _local_validate(evidence_dir: Path) -> dict[str, Any]:
    python_files = [str(path.relative_to(ROOT)) for path in [ROOT / "main.py", *sorted((ROOT / "scripts").glob("*.py"))]]
    shell_files = [str(path.relative_to(ROOT)) for path in sorted((ROOT / "scripts").glob("*.sh"))]
    checks = [
        _run_command(
            command=["git", "diff", "--check"],
            display_command="git diff --check",
            label="validate-git-diff",
            evidence_dir=evidence_dir,
            timeout=COMMAND_TIMEOUT_SECONDS["validation"],
        ),
        _run_command(
            command=[sys.executable, "-m", "py_compile", *python_files],
            display_command="python -m py_compile main.py scripts/*.py",
            label="validate-python-compile",
            evidence_dir=evidence_dir,
            timeout=COMMAND_TIMEOUT_SECONDS["validation"],
        ),
        _run_command(
            command=["bash", "-n", *shell_files],
            display_command="bash -n scripts/*.sh",
            label="validate-shell-syntax",
            evidence_dir=evidence_dir,
            timeout=COMMAND_TIMEOUT_SECONDS["validation"],
        ),
        _run_command(
            command=["bash", "scripts/verify_release_guards.sh"],
            display_command="bash scripts/verify_release_guards.sh",
            label="validate-release-guards",
            evidence_dir=evidence_dir,
            timeout=COMMAND_TIMEOUT_SECONDS["validation"],
        ),
        _run_command(
            command=["bash", "scripts/verify_website.sh"],
            display_command="bash scripts/verify_website.sh",
            label="validate-website",
            evidence_dir=evidence_dir,
            timeout=COMMAND_TIMEOUT_SECONDS["validation"],
        ),
    ]
    pytest_command = [
        sys.executable,
        "-m",
        "pytest",
        "--confcutdir=tests/unit",
        "-q",
        "tests/unit/test_codex_local_deb.py",
        "tests/unit/test_codex_local_lane_contract.py",
        "tests/unit/test_cli_controller.py",
        "tests/unit/test_release_arm64.py",
        "tests/unit/test_codex_workflow.py",
    ]
    checks.append(
        _run_command(
            command=pytest_command,
            display_command=(
                "PYDANTIC_DISABLE_PLUGINS=1 PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 "
                "python -m pytest --confcutdir=tests/unit -q "
                "tests/unit/test_codex_local_deb.py tests/unit/test_codex_local_lane_contract.py "
                "tests/unit/test_cli_controller.py tests/unit/test_release_arm64.py "
                "tests/unit/test_codex_workflow.py"
            ),
            label="validate-focused-pytest",
            evidence_dir=evidence_dir,
            timeout=COMMAND_TIMEOUT_SECONDS["validation"],
            env={
                **os.environ,
                "PYDANTIC_DISABLE_PLUGINS": "1",
                "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1",
            },
        )
    )
    return _stage("LOCAL_VALIDATE", checks)


def _controller_child(
    *,
    operation: str,
    evidence_dir: Path,
    timeout: int,
    extra: list[str],
    label: str,
) -> dict[str, Any]:
    command = [sys.executable, str(ROOT / "scripts/codex_cli_controller.py"), operation, *extra]
    result = _run_command(
        command=command,
        display_command=_command_text(command),
        label=label,
        evidence_dir=evidence_dir,
        timeout=timeout,
        env={**os.environ, "PYDANTIC_DISABLE_PLUGINS": "1", "PYTHONUNBUFFERED": "1"},
    )
    for path_key in ("stdout", "stderr"):
        path = Path(result["evidence"][path_key])
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            lines = []
        result[f"controller_{path_key}"] = [
            redact_text(line)
            for line in lines
            if any(marker in line for marker in ("CONTROLLER_RESULT=", "AUTOMATION_RESULT=", "LOCAL_E2E_", "CONTROLLER_EVIDENCE="))
        ]
    if result["status"] == "FAIL" and result.get("exit_code") in {2, 3}:
        result["status"] = "BLOCKED" if result["exit_code"] == 2 else "FAIL"
    return result


def _local_e2e(evidence_dir: Path, local_validate: dict[str, Any]) -> dict[str, Any]:
    if local_validate["status"] in {"FAIL", "BLOCKED", "UNKNOWN"}:
        return _stage(
            "LOCAL_E2E",
            [
                {
                    "name": "local_validate_gate",
                    "status": "NOT_RUN",
                    "blocker": "BLOCKED_LOCAL_VALIDATE_FAILED",
                    "blocks_stage": True,
                }
            ],
        )
    result = _controller_child(
        operation="local-e2e",
        evidence_dir=evidence_dir,
        timeout=COMMAND_TIMEOUT_SECONDS["local_e2e"],
        extra=["--evidence-dir", str(evidence_dir / "local-e2e")],
        label="local-e2e",
    )
    if result.get("blocker") == "BLOCKED_TOOLCHAIN_TIMEOUT":
        result["blocker"] = "BLOCKED_LOCAL_E2E_TIMEOUT"
    return _stage("LOCAL_E2E", [result])


def _package(
    evidence_dir: Path,
    *,
    api_base: str | None,
    local_validate: dict[str, Any],
    local_e2e: dict[str, Any],
    precheck: dict[str, Any],
) -> dict[str, Any]:
    if local_validate["status"] in {"FAIL", "BLOCKED", "UNKNOWN"}:
        return _stage(
            "PACKAGE",
            [
                {
                    "name": "local_validate_gate",
                    "status": "NOT_RUN",
                    "blocker": "BLOCKED_LOCAL_VALIDATE_FAILED",
                    "blocks_stage": True,
                }
            ],
        )
    if local_e2e["status"] in {"FAIL", "BLOCKED", "UNKNOWN"}:
        return _stage(
            "PACKAGE",
            [
                {
                    "name": "local_e2e_gate",
                    "status": "NOT_RUN",
                    "blocker": _stage_blocker(local_e2e, "BLOCKED_LOCAL_E2E_FAILED"),
                    "blocks_stage": True,
                }
            ],
        )
    for check in precheck.get("checks", []):
        if check.get("blocks_package") and check.get("status") in {"FAIL", "BLOCKED", "UNKNOWN"}:
            return _stage(
                "PACKAGE",
                [
                    {
                        "name": "precheck_package_gate",
                        "status": "BLOCKED",
                        "blocker": check.get("blocker", "BLOCKED_PRECHECK_FAILED"),
                        "blocks_stage": True,
                    }
                ],
            )
    if not api_base:
        return _stage(
            "PACKAGE",
            [
                {
                    "name": "api_base",
                    "status": "BLOCKED",
                    "blocker": "BLOCKED_LOCAL_API_BASE_MISSING",
                    "blocks_stage": True,
                }
            ],
        )
    output_dir = evidence_dir / "artifacts"
    result = _controller_child(
        operation="local-deb",
        evidence_dir=evidence_dir,
        timeout=COMMAND_TIMEOUT_SECONDS["package"],
        extra=[
            "--api-base",
            api_base,
            "--output-dir",
            str(output_dir),
            "--evidence-dir",
            str(evidence_dir / "local-deb"),
        ],
        label="local-package",
    )
    package_evidence = evidence_dir / "local-deb" / "local-deb.json"
    try:
        package_payload = json.loads(package_evidence.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        package_payload = {}
    package_fields = package_payload.get("package")
    if isinstance(package_fields, dict):
        result["package_metadata"] = {
            key: package_fields[key]
            for key in ("package", "version", "architecture", "sha256", "profile", "source_sha")
            if key in package_fields
        }
        result["package_evidence"] = str(package_evidence)
    if result.get("exit_code") == 2:
        result["status"] = "BLOCKED"
        if any("ARM64" in line or "arm64" in line for line in result.get("controller_stderr", []) + result.get("controller_stdout", [])):
            result["blocker"] = "BLOCKED_ARM64_RUNTIME_REQUIRED"
        else:
            result["blocker"] = "BLOCKED_LOCAL_BUILD"
    return _stage("PACKAGE", [result], output_dir=str(output_dir))


def _release_readiness(
    *,
    precheck: dict[str, Any],
    local_validate: dict[str, Any],
    local_e2e: dict[str, Any],
    package: dict[str, Any],
    release_packet: Path | None,
    staging_packet: Path | None,
    approval_file: Path | None,
) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    for name, stage in (
        ("precheck", precheck),
        ("local_validate", local_validate),
        ("local_e2e", local_e2e),
        ("package", package),
    ):
        stage_status = stage["status"]
        checks.append(
            {
                "name": name,
                "status": "PASS" if stage_status == "PASS" else stage_status,
                "blocker": _stage_blocker(stage, f"BLOCKED_{name.upper()}"),
                "blocks_stage": stage_status in {"FAIL", "BLOCKED", "UNKNOWN"},
            }
        )
    packet_checks = (
        ("release_packet", release_packet, "BLOCKED_RELEASE_PACKET_MISSING"),
        ("staging_packet", staging_packet, "BLOCKED_STAGING_PACKET_MISSING"),
        ("approval_file", approval_file, "BLOCKED_APPROVAL_MISSING"),
    )
    for name, path, blocker in packet_checks:
        present = bool(path and path.is_file())
        checks.append(
            {
                "name": name,
                "status": "PASS" if present else "BLOCKED",
                "value": "PRESENT" if present else "MISSING",
                "blocker": None if present else blocker,
                "blocks_stage": True,
            }
        )
    return _stage(
        "RELEASE_READINESS",
        checks,
        external_inputs={
            "release_packet": "PRESENT" if release_packet and release_packet.is_file() else "MISSING",
            "staging_packet": "PRESENT" if staging_packet and staging_packet.is_file() else "MISSING",
            "approval_file": "PRESENT" if approval_file and approval_file.is_file() else "MISSING",
        },
        environment_presence={
            group: _presence(names) for group, names in ENVIRONMENT_GROUPS.items()
        },
    )


def _external_stage(name: str) -> dict[str, Any]:
    return _stage(
        name,
        [
            {
                "name": "explicit_external_authorization",
                "status": "NOT_RUN",
                "blocker": "BLOCKED_EXTERNAL_APPROVAL_REQUIRED",
                "blocks_stage": True,
            }
        ],
        mutation="NOT_RUN",
    )


def _stage_blocker(stage: dict[str, Any], fallback: str) -> str | None:
    for check in stage.get("checks", []):
        if check.get("blocker"):
            return str(check["blocker"])
    return fallback if stage.get("status") in {"FAIL", "BLOCKED", "UNKNOWN"} else None


def _automation_result(stages: dict[str, dict[str, Any]]) -> tuple[str, bool, bool]:
    local_names = ("PRECHECK", "LOCAL_VALIDATE", "LOCAL_E2E")
    package_status = stages["PACKAGE"]["status"]
    package_blockers = {
        str(check.get("blocker"))
        for check in stages["PACKAGE"].get("checks", [])
        if check.get("blocker")
    }
    package_environment_blocked = package_blockers == {"BLOCKED_ARM64_RUNTIME_REQUIRED"}
    local_checks_pass = all(stages[name]["status"] == "PASS" for name in local_names)
    local_workflow_ready = local_checks_pass and (
        package_status == "PASS"
        or (package_status == "BLOCKED" and package_environment_blocked)
    )
    package_ready = package_status == "PASS"
    if any(stages[name]["status"] == "FAIL" for name in ("PRECHECK", "LOCAL_VALIDATE", "LOCAL_E2E", "PACKAGE")):
        return "FAIL", local_workflow_ready, package_ready
    if local_workflow_ready:
        return "LOCAL_WORKFLOW_READY", local_workflow_ready, package_ready
    return "BLOCKED_LOCAL_REMEDIATION", local_workflow_ready, package_ready


def run_workflow(
    *,
    evidence_root: Path,
    expected_branch: str | None,
    expected_sha: str | None,
    api_base: str | None,
    release_packet: Path | None,
    staging_packet: Path | None,
    approval_file: Path | None,
) -> dict[str, Any]:
    """Run only the local workflow stages and write a redacted external report."""

    run_dir = _new_run_directory(evidence_root)
    for path_name, path in (
        ("release_packet", release_packet),
        ("staging_packet", staging_packet),
        ("approval_file", approval_file),
    ):
        if path is not None:
            try:
                ensure_external_path(str(path), ROOT, path_name)
            except Exception as exc:
                raise WorkflowInputError(f"{path_name} must be outside the repository") from exc

    precheck, precheck_evidence = _precheck(
        evidence_dir=run_dir,
        expected_branch=expected_branch,
        expected_sha=expected_sha,
    )
    stages: dict[str, dict[str, Any]] = {"PRECHECK": precheck}
    local_validation_gate = _has_blocking_check(
        precheck.get("checks", []), "blocks_local_validation"
    )
    if local_validation_gate:
        local_validate = _stage(
            "LOCAL_VALIDATE",
            [
                {
                    "name": "precheck_gate",
                    "status": "NOT_RUN",
                    "blocker": "BLOCKED_PRECHECK_FAILED",
                    "blocks_stage": True,
                }
            ],
        )
    else:
        local_validate = _local_validate(run_dir)
    stages["LOCAL_VALIDATE"] = local_validate
    local_e2e = _local_e2e(run_dir, local_validate)
    stages["LOCAL_E2E"] = local_e2e
    package = _package(
        run_dir,
        api_base=api_base,
        local_validate=local_validate,
        local_e2e=local_e2e,
        precheck=precheck,
    )
    stages["PACKAGE"] = package
    release_readiness = _release_readiness(
        precheck=precheck,
        local_validate=local_validate,
        local_e2e=local_e2e,
        package=package,
        release_packet=release_packet,
        staging_packet=staging_packet,
        approval_file=approval_file,
    )
    stages["RELEASE_READINESS"] = release_readiness
    stages["EXTERNAL_CANARY"] = _external_stage("EXTERNAL_CANARY")
    stages["DEPLOY"] = _external_stage("DEPLOY")

    final_result, local_ready, package_ready = _automation_result(stages)
    ending_identity = _identity()
    protected_end = {
        relative: _sha256(ROOT / relative)
        for relative in PROTECTED_PATHS
        if (ROOT / relative).is_file()
    }
    protected_status = {
        relative: "PASS_UNCHANGED" if precheck_evidence["protected_sha256"].get(relative) == digest else "FAIL_CHANGED"
        for relative, digest in protected_end.items()
    }
    blockers = sorted(
        {
            str(check.get("blocker"))
            for stage in stages.values()
            for check in stage.get("checks", [])
            if check.get("blocker")
        }
        | {
            "BLOCKED_BEFORE_EXTERNAL_MUTATION"
        }
    )
    summary = {
        "workflow_version": WORKFLOW_VERSION,
        "run_directory": str(run_dir),
        "repository_root": str(ROOT),
        "branch": ending_identity["branch"],
        "starting_head": precheck_evidence["repository"]["head"],
        "ending_head": ending_identity["head"],
        "expected_candidate_sha": expected_sha,
        "expected_branch": expected_branch,
        "starting_status": precheck_evidence["repository"]["status"],
        "ending_status": ending_identity["status"],
        "stages": stages,
        "protected_paths": protected_status,
        "blockers": blockers,
        "local_workflow_ready": "yes" if local_ready else "no",
        "package_ready": "yes" if package_ready else "no",
        "external_release_ready": "no",
        "external_operations": {
            "deployment": "NOT_RUN",
            "SMTP": "NOT_RUN",
            "SendGrid": "NOT_RUN",
            "Terraform mutation": "NOT_RUN",
            "public URL verification": "NOT_RUN",
            "live VPN mutation": "NOT_RUN",
        },
        "external_system_mutation": "NOT_RUN",
        "final_automation_result": final_result,
    }
    summary_json = write_json_evidence(run_dir, "summary.json", summary)
    markdown = _summary_markdown(summary)
    summary_md = run_dir / "summary.md"
    _write_text(summary_md, markdown)
    return {
        "result": final_result,
        "local_workflow_ready": local_ready,
        "package_ready": package_ready,
        "run_directory": str(run_dir),
        "summary_json": str(summary_json),
        "summary_md": str(summary_md),
        "blockers": blockers,
    }


def _summary_markdown(summary: dict[str, Any]) -> str:
    lines = [
        "# SecureWave Codex workflow evidence",
        "",
        f"`AUTOMATION_RESULT={summary['final_automation_result']}`",
        "",
        "This report covers local readiness only. External provider, deployment, Terraform, public URL, and live VPN mutations were not run.",
        "",
        "## Identity",
        "",
        f"- Repository: `{summary['repository_root']}`",
        f"- Branch: `{summary['branch']}`",
        f"- Starting HEAD: `{summary['starting_head']}`",
        f"- Ending HEAD: `{summary['ending_head']}`",
        f"- Worktree start: `{summary['starting_status']}`",
        f"- Worktree end: `{summary['ending_status']}`",
        "",
        "## Stages",
        "",
        "| Stage | Result |",
        "|---|---|",
    ]
    for stage in summary["stages"].values():
        lines.append(f"| `{stage['stage']}` | `{stage['status']}` |")
    lines.extend(
        [
            "",
            "## Commands",
            "",
            "| Command | Exit | Result |",
            "|---|---:|---|",
        ]
    )
    for stage in summary["stages"].values():
        for check in stage.get("checks", []):
            if check.get("command"):
                exit_code = check.get("exit_code")
                lines.append(
                    f"| `{redact_text(str(check['command']))}` | "
                    f"`{exit_code if exit_code is not None else '-'}` | `{check.get('status', 'UNKNOWN')}` |"
                )
    lines.extend(
        [
            "",
            "## Readiness",
            "",
            f"- `LOCAL_WORKFLOW_READY={summary['local_workflow_ready']}`",
            f"- `PACKAGE_READY={summary['package_ready']}`",
            f"- `EXTERNAL_RELEASE_READY={summary['external_release_ready']}`",
            "",
            "## Blockers",
            "",
        ]
    )
    lines.extend(f"- `{blocker}`" for blocker in summary["blockers"])
    lines.extend(
        [
            "",
            "## External operations",
            "",
            "- `deployment=NOT_RUN`",
            "- `SMTP=NOT_RUN`",
            "- `SendGrid=NOT_RUN`",
            "- `Terraform mutation=NOT_RUN`",
            "- `public URL verification=NOT_RUN`",
            "- `live VPN mutation=NOT_RUN`",
        ]
    )
    return "\n".join(lines) + "\n"
