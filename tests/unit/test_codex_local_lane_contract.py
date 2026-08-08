import os
import subprocess
import sys
from pathlib import Path

from scripts import codex_local_e2e


ROOT = Path(__file__).resolve().parents[2]


def test_local_lane_uses_real_auth_without_mock_or_remote_email():
    source = (ROOT / "scripts/codex_local_e2e.py").read_text(encoding="utf-8")
    assert '"DEMO_MODE": "false"' in source
    assert '"WG_MOCK_MODE": "false"' in source
    assert '"EMAIL_PROVIDER": "local_capture"' in source
    assert "TemporaryDirectory" in source
    assert "api/auth/login" in source
    assert "send_verification_email" in source
    assert "EnhancedEmailService" in source
    assert "SendGrid" not in source


def test_local_e2e_uses_an_external_bytecode_cache_and_restores_process_state(
    monkeypatch, tmp_path: Path
):
    observed: dict[str, str | None] = {}
    previous_prefix = sys.pycache_prefix
    previous_environment_prefix = os.environ.get("PYTHONPYCACHEPREFIX")

    def fake_migrations(_database_url: str):
        observed["sys_prefix"] = sys.pycache_prefix
        observed["environment_prefix"] = os.environ.get("PYTHONPYCACHEPREFIX")
        return {"exit_code": 0}

    def fake_seed():
        capture_dir = Path(os.environ["SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR"])
        capture_dir.mkdir(parents=True, exist_ok=True)
        (capture_dir / "captured.json").write_text("{}\n", encoding="utf-8")
        return {"seeded": True}

    monkeypatch.setattr(codex_local_e2e, "_run_migrations", fake_migrations)
    monkeypatch.setattr(codex_local_e2e, "_seed_users", fake_seed)
    monkeypatch.setattr(
        codex_local_e2e,
        "_run_auth_contract",
        lambda: {"valid_login_status": 200},
    )

    result, evidence_path = codex_local_e2e.run_local_e2e(tmp_path)

    expected_prefix = str((tmp_path / "python-pycache").resolve())
    assert result == "LOCAL_AUTOMATION_READY"
    assert evidence_path.is_file()
    assert observed == {
        "sys_prefix": expected_prefix,
        "environment_prefix": expected_prefix,
    }
    assert sys.pycache_prefix == previous_prefix
    assert os.environ.get("PYTHONPYCACHEPREFIX") == previous_environment_prefix


def test_local_e2e_binds_migrations_to_the_active_python_interpreter(monkeypatch):
    observed: dict[str, object] = {}

    def fake_run(command, **kwargs):
        observed["command"] = command
        observed["environment"] = kwargs["env"]
        return subprocess.CompletedProcess(command, 0, "migration complete", "")

    monkeypatch.setattr(codex_local_e2e.subprocess, "run", fake_run)

    result = codex_local_e2e._run_migrations("sqlite:////tmp/codex-local.db")

    assert result["exit_code"] == 0
    assert observed["command"] == [sys.executable, "-m", "alembic", "upgrade", "head"]
    assert observed["environment"]["DATABASE_URL"] == "sqlite:////tmp/codex-local.db"


def test_codex_local_package_is_distinct_and_never_a_download_manifest_artifact():
    builder = (ROOT / "scripts/build_codex_local_deb.sh").read_text(encoding="utf-8")
    deb_builder = (ROOT / "securewave_app/scripts/build_deb.sh").read_text(encoding="utf-8")
    assert "securewave-vpn-codex-local" in deb_builder
    assert "SECUREWAVE_PACKAGE_PROFILE=codex-local" in builder
    assert "output must be outside the repository" in builder
    assert "SECUREWAVE_USE_MOCK_API=false" in deb_builder


def test_arm64_controller_is_fixed_operation_without_command_passthrough():
    controller = (ROOT / "scripts/codex_cli_controller.py").read_text(encoding="utf-8")
    assert 'subparsers.add_parser("local-e2e")' in controller
    assert 'subparsers.add_parser("local-deb")' in controller
    assert 'subparsers.add_parser("release-arm64")' in controller
    assert "arbitrary command" not in controller.lower()


def test_local_deb_builder_uses_the_pinned_linux_arm64_toolchain():
    dockerfile = (ROOT / "Dockerfile.codex-local-deb").read_text(encoding="utf-8")
    builder = (ROOT / "scripts/codex_local_deb.py").read_text(encoding="utf-8")
    assert "FROM --platform=linux/arm64" in dockerfile
    assert "ubuntu:24.04@sha256:b17516cd982bf06bdd5d5600253d12a8de017b9eb831cc052b532a0363d294f9" in dockerfile
    assert "FLUTTER_COMMIT=559ffa3f75e7402d65a8def9c28389a9b2e6fe42" in dockerfile
    assert "DOCKER_IMAGE = \"securewave-codex-local-deb:3.44.0-arm64\"" in builder
    assert "--platform=linux/arm64" in builder
    assert "codex_local_deb_container.sh" in dockerfile
    container = (ROOT / "scripts/codex_local_deb_container.sh").read_text(encoding="utf-8")
    assert "git clone --quiet --no-hardlinks --no-checkout /source /work" in container
    assert 'git -C /work checkout --quiet --detach "$source_sha"' in container
    assert 'git -C /work rev-parse "HEAD^{tree}"' in container
    assert "git -C /source archive" not in container
    assert "arbitrary" not in builder.lower()
