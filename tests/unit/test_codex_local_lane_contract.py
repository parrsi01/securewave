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
    assert 'subparsers.add_parser("release-arm64")' in controller
    assert "arbitrary command" not in controller.lower()
