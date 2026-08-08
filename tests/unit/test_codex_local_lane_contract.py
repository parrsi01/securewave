from pathlib import Path


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
    assert "git -C /source archive --format=tar \"$source_sha\"" in container
    assert "git write-tree" in container
    assert "git hash-object -w -t commit --stdin" in container
    assert "arbitrary" not in builder.lower()
