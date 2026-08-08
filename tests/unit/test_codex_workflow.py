import ast
import os
import subprocess
import sys
from pathlib import Path

from scripts import codex_workflow


def _identity(*, clean: bool) -> dict[str, object]:
    return {
        "repository_root": str(codex_workflow.ROOT),
        "head": "a" * 40,
        "branch": "agent/test-workflow",
        "status": "## agent/test-workflow" if clean else "## agent/test-workflow\n M app.py",
        "clean": clean,
    }


def _patch_precheck_environment(monkeypatch, *, clean: bool, docker_platform: str):
    monkeypatch.setattr(codex_workflow, "_identity", lambda: _identity(clean=clean))
    monkeypatch.setattr(
        codex_workflow.shutil,
        "which",
        lambda name: f"/usr/bin/{name}",
    )
    monkeypatch.setattr(
        codex_workflow.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args=args[0], returncode=0, stdout="https://example.invalid/securewave.git\n", stderr=""
        ),
    )

    def fake_run_command(*, label, **kwargs):
        result = {
            "command": label,
            "exit_code": 0,
            "status": "PASS",
            "evidence": {},
        }
        if label == "precheck-docker":
            result["redacted_tail"] = docker_platform
        elif label == "precheck-git-remote":
            result["redacted_tail"] = "a" * 40 + "\trefs/heads/master"
        return result

    monkeypatch.setattr(codex_workflow, "_run_command", fake_run_command)


def test_remote_failure_classification_distinguishes_network_and_auth():
    assert (
        codex_workflow.classify_remote_failure("fatal: could not resolve host: github.com")
        == "BLOCKED_REMOTE_NETWORK"
    )
    assert (
        codex_workflow.classify_remote_failure("remote: Repository not found.")
        == "BLOCKED_REMOTE_GIT_AUTH"
    )
    assert (
        codex_workflow.classify_remote_failure("fatal: not a git repository")
        == "FAIL_REMOTE_INVALID"
    )


def test_stage_status_ignores_advisory_blockers():
    checks = [
        {"status": "PASS", "blocks_stage": True},
        {
            "status": "BLOCKED",
            "blocker": "BLOCKED_EMAIL_PROVIDER_CONFIG",
            "blocks_stage": False,
        },
    ]
    assert codex_workflow._status_for_checks(checks) == "PASS"


def test_command_failure_blocks_stage_by_default():
    assert codex_workflow._status_for_checks([{"status": "FAIL"}]) == "FAIL"


def test_precheck_detects_clean_and_dirty_worktrees(monkeypatch, tmp_path: Path):
    _patch_precheck_environment(monkeypatch, clean=True, docker_platform="linux/arm64")
    clean, _ = codex_workflow._precheck(
        evidence_dir=tmp_path / "clean",
        expected_branch="agent/test-workflow",
        expected_sha="a" * 40,
    )
    assert clean["status"] == "PASS"
    assert next(item for item in clean["checks"] if item["name"] == "worktree_clean")["status"] == "PASS"

    _patch_precheck_environment(monkeypatch, clean=False, docker_platform="linux/arm64")
    dirty, _ = codex_workflow._precheck(
        evidence_dir=tmp_path / "dirty",
        expected_branch="agent/test-workflow",
        expected_sha="a" * 40,
    )
    dirty_check = next(item for item in dirty["checks"] if item["name"] == "worktree_clean")
    assert dirty_check["status"] == "BLOCKED"
    assert dirty_check["blocker"] == "BLOCKED_WORKTREE_DIRTY"


def test_precheck_gates_non_arm64_docker_for_package(monkeypatch, tmp_path: Path):
    _patch_precheck_environment(monkeypatch, clean=True, docker_platform="linux/amd64")
    precheck, evidence = codex_workflow._precheck(
        evidence_dir=tmp_path,
        expected_branch="agent/test-workflow",
        expected_sha="a" * 40,
    )
    docker_check = next(item for item in precheck["checks"] if item["name"] == "docker")
    assert docker_check["status"] == "BLOCKED"
    assert docker_check["blocker"] == "BLOCKED_ARM64_RUNTIME_REQUIRED"
    assert docker_check["blocks_package"] is True
    assert evidence["docker_server_platform"] == "linux/amd64"


def test_package_requires_clean_worktree_and_does_not_call_builder(monkeypatch, tmp_path: Path):
    precheck = {
        "checks": [
            {
                "name": "worktree_clean",
                "status": "BLOCKED",
                "blocker": "BLOCKED_WORKTREE_DIRTY",
                "blocks_package": True,
            }
        ]
    }
    monkeypatch.setattr(
        codex_workflow,
        "_controller_child",
        lambda **kwargs: (_ for _ in ()).throw(AssertionError("builder must be gated")),
    )
    package = codex_workflow._package(
        tmp_path,
        api_base="http://127.0.0.1:18080/api",
        local_validate={"status": "PASS"},
        local_e2e={"status": "PASS"},
        precheck=precheck,
    )
    assert package["status"] == "BLOCKED"
    assert package["checks"][0]["blocker"] == "BLOCKED_WORKTREE_DIRTY"


def test_package_uses_existing_controller_after_clean_gate(monkeypatch, tmp_path: Path):
    calls = []

    def fake_controller_child(**kwargs):
        calls.append(kwargs)
        return {
            "command": "local-deb",
            "status": "PASS",
            "exit_code": 0,
            "evidence": {},
            "controller_stdout": ["CONTROLLER_RESULT=LOCAL_PACKAGE_READY"],
            "controller_stderr": [],
        }

    monkeypatch.setattr(codex_workflow, "_controller_child", fake_controller_child)
    package = codex_workflow._package(
        tmp_path,
        api_base="http://127.0.0.1:18080/api",
        local_validate={"status": "PASS"},
        local_e2e={"status": "PASS"},
        precheck={
            "checks": [
                {"name": "worktree_clean", "status": "PASS", "blocks_package": True},
                {"name": "docker", "status": "PASS", "blocks_package": True},
            ]
        },
    )
    assert package["status"] == "PASS"
    assert calls[0]["operation"] == "local-deb"


def test_package_does_not_run_after_local_e2e_failure(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(
        codex_workflow,
        "_controller_child",
        lambda **kwargs: (_ for _ in ()).throw(AssertionError("builder must be gated")),
    )
    package = codex_workflow._package(
        tmp_path,
        api_base="http://127.0.0.1:18080/api",
        local_validate={"status": "PASS"},
        local_e2e={
            "status": "BLOCKED",
            "checks": [{"blocker": "BLOCKED_LOCAL_E2E_TIMEOUT"}],
        },
        precheck={"checks": [{"name": "docker", "status": "PASS", "blocks_package": True}]},
    )
    assert package["status"] == "NOT_RUN"
    assert package["checks"][0]["blocker"] == "BLOCKED_LOCAL_E2E_TIMEOUT"


def test_local_validate_runs_all_bounded_contract_commands(monkeypatch, tmp_path: Path):
    calls = []

    def fake_run_command(*, label, **kwargs):
        calls.append(label)
        return {"command": label, "status": "PASS", "exit_code": 0, "evidence": {}}

    monkeypatch.setattr(codex_workflow, "_run_command", fake_run_command)
    validation = codex_workflow._local_validate(tmp_path)
    assert validation["status"] == "PASS"
    assert calls == [
        "validate-git-diff",
        "validate-python-compile",
        "validate-shell-syntax",
        "validate-release-guards",
        "validate-website",
        "validate-focused-pytest",
    ]


def test_local_e2e_uses_existing_controller_and_respects_validation_gate(monkeypatch, tmp_path: Path):
    calls = []

    def fake_controller_child(**kwargs):
        calls.append(kwargs)
        return {
            "command": "local-e2e",
            "status": "PASS",
            "exit_code": 0,
            "evidence": {},
            "controller_stdout": ["CONTROLLER_RESULT=LOCAL_AUTOMATION_READY"],
            "controller_stderr": [],
        }

    monkeypatch.setattr(codex_workflow, "_controller_child", fake_controller_child)
    e2e = codex_workflow._local_e2e(tmp_path, {"status": "PASS"})
    assert e2e["status"] == "PASS"
    assert calls[0]["operation"] == "local-e2e"

    gated = codex_workflow._local_e2e(tmp_path, {"status": "FAIL"})
    assert gated["status"] == "NOT_RUN"
    assert gated["checks"][0]["blocker"] == "BLOCKED_LOCAL_VALIDATE_FAILED"


def test_release_readiness_reports_missing_external_inputs():
    passed = {"status": "PASS", "checks": []}
    readiness = codex_workflow._release_readiness(
        precheck=passed,
        local_validate=passed,
        local_e2e=passed,
        package=passed,
        release_packet=None,
        staging_packet=None,
        approval_file=None,
    )
    assert readiness["status"] == "BLOCKED"
    assert {
        check["blocker"] for check in readiness["checks"] if check.get("blocker")
    } == {
        "BLOCKED_RELEASE_PACKET_MISSING",
        "BLOCKED_STAGING_PACKET_MISSING",
        "BLOCKED_APPROVAL_MISSING",
    }


def test_external_stages_are_explicitly_non_mutating():
    for name in ("EXTERNAL_CANARY", "DEPLOY"):
        stage = codex_workflow._external_stage(name)
        assert stage["status"] == "NOT_RUN"
        assert stage["mutation"] == "NOT_RUN"
        assert stage["checks"][0]["blocker"] == "BLOCKED_EXTERNAL_APPROVAL_REQUIRED"


def test_environment_presence_never_exposes_values(monkeypatch):
    monkeypatch.setenv("SENDGRID_API_KEY", "secret-value")
    status = codex_workflow._presence(("SENDGRID_API_KEY", "FROM_EMAIL"))
    assert status == {"SENDGRID_API_KEY": "PRESENT", "FROM_EMAIL": "MISSING"}
    assert "secret-value" not in str(status)


def test_optional_startup_dependencies_are_deferred():
    code = (
        "import sys; "
        "import services.paypal_service, services.vpn_optimizer, "
        "services.xgb_qos, services.xgb_risk; "
        "assert 'numpy' not in sys.modules; "
        "assert 'requests' not in sys.modules; "
        "assert 'qrcode' not in sys.modules"
    )
    completed = subprocess.run(
        [sys.executable, "-c", code],
        cwd=codex_workflow.ROOT,
        env={
            **os.environ,
            "PYDANTIC_DISABLE_PLUGINS": "1",
            "PYTEST_DISABLE_PLUGIN_AUTOLOAD": "1",
        },
        capture_output=True,
        text=True,
        check=False,
        timeout=20,
    )
    assert completed.returncode == 0, completed.stderr

    for relative_path in (
        "services/auth_service.py",
        "services/vpn_peer_manager.py",
        "services/wireguard_service.py",
    ):
        tree = ast.parse(
            (codex_workflow.ROOT / relative_path).read_text(encoding="utf-8"),
            filename=relative_path,
        )
        qrcode_imports = []

        class ImportVisitor(ast.NodeVisitor):
            def __init__(self):
                self.function_depth = 0

            def visit_FunctionDef(self, node):
                self.function_depth += 1
                self.generic_visit(node)
                self.function_depth -= 1

            visit_AsyncFunctionDef = visit_FunctionDef

            def visit_Import(self, node):
                if any(alias.name == "qrcode" for alias in node.names):
                    qrcode_imports.append(self.function_depth)
                self.generic_visit(node)

            def visit_ImportFrom(self, node):
                if node.module == "qrcode":
                    qrcode_imports.append(self.function_depth)
                self.generic_visit(node)

        ImportVisitor().visit(tree)
        assert qrcode_imports, f"{relative_path} must retain its QR import"
        assert all(depth > 0 for depth in qrcode_imports), (
            f"{relative_path} must defer QR imports until a call path"
        )
