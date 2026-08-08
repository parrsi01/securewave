from pathlib import Path
import json

from scripts import login_provenance


ROOT = Path(__file__).resolve().parents[2]


def test_deb_release_build_passes_explicit_live_api_define():
    source = (ROOT / "securewave_app/scripts/build_deb.sh").read_text(encoding="utf-8")
    assert "--dart-define=SECUREWAVE_API_BASE_URL=" in source
    assert "--dart-define=SECUREWAVE_USE_MOCK_API=false" in source
    apps_source = (ROOT / "scripts/build_apps.sh").read_text(encoding="utf-8")
    assert "--dart-define=SECUREWAVE_API_BASE_URL=" in apps_source
    assert "--dart-define=SECUREWAVE_USE_MOCK_API=false" in apps_source


def test_codex_local_deb_builder_requires_loopback_and_external_output():
    wrapper = (ROOT / "scripts/build_codex_local_deb.sh").read_text(encoding="utf-8")
    deb_builder = (ROOT / "securewave_app/scripts/build_deb.sh").read_text(
        encoding="utf-8"
    )
    assert "--api-base" in wrapper
    assert "--output-dir" in wrapper
    assert "HTTP loopback /api" in wrapper
    assert "local package output must be outside the repository" in wrapper
    assert 'package_profile="${SECUREWAVE_PACKAGE_PROFILE:-production}"' in deb_builder
    assert "package_name=\"securewave-vpn-codex-local\"" in deb_builder
    assert "SECUREWAVE_CODEX_LOCAL=true" in wrapper


def test_deb_declares_linux_secure_storage_runtime_dependency():
    source = (ROOT / "securewave_app/scripts/build_deb.sh").read_text(
        encoding="utf-8"
    )
    assert "libsecret-1-0" in source
    assert "libgtk-3-0" in source
    assert "dpkg-deb --field \"$output_file\" Depends" in source


def test_login_diagnostic_build_requires_explicit_live_api_and_has_no_credentials():
    source = (ROOT / "scripts/build_flutter_login_diagnostic.sh").read_text(
        encoding="utf-8"
    )
    assert 'Usage: $0 --api-base <explicit-https-api-base>' in source
    assert "--dart-define=SECUREWAVE_USE_MOCK_API=false" in source
    assert "--dart-define=SECUREWAVE_DIAGNOSTICS=true" in source
    assert "SECUREWAVE_DIAGNOSTIC_PASSWORD" not in source
    assert "SMTP_PASSWORD" not in source


def test_release_config_does_not_allow_flutter_env_asset_to_override_api_define():
    source = (ROOT / "securewave_app/lib/core/config/app_config.dart").read_text(
        encoding="utf-8"
    )
    assert "if (!_isReleaseBuild)" in source
    assert "final env = !_isReleaseBuild && dotenv.isInitialized" in source
    assert "normalizeApiBaseUrl" in source


def test_login_provenance_report_is_redacted():
    report = json.dumps(login_provenance.build_report(), sort_keys=True)
    assert "https://" not in report
    assert "@" not in report
    assert "password" not in report.lower()
    assert "access_token" not in report


def test_tracked_x64_artifact_exposes_historical_template_configuration():
    artifact = login_provenance._portable_linux_artifact_record()
    assert artifact["artifact_present"] is True
    assert artifact["binary_architecture"] == "x86_64"
    assert artifact["source_commit"] == "d29866446c8ccb0dc2be146070f45a9730afd26d"
    assert artifact["embedded_api_matches_historical_template"] is True
    assert artifact["release_safety"] == "BLOCKED_EMBEDDED_API_TEMPLATE"
    assert artifact["embedded_mock_value_present"] is False


def test_known_stale_x64_tarball_is_withheld_from_download_manifest():
    manifest = json.loads((ROOT / "static/downloads/manifest.json").read_text())
    row = next(
        item
        for item in manifest["downloads"]
        if item.get("filename") == "securewave-linux-x64.tar.gz"
    )
    assert row["status"] == "coming_soon"
    assert "historical template API" in row["notes"]

    downloads_source = (ROOT / "routes/downloads.py").read_text(encoding="utf-8")
    assert '"filename": "securewave-linux-x64.tar.gz"' in downloads_source
    assert '"status": "coming_soon"' in downloads_source


def test_historical_x64_deb_is_withheld_from_download_manifest():
    manifest = json.loads((ROOT / "static/downloads/manifest.json").read_text())
    row = next(
        item
        for item in manifest["downloads"]
        if item.get("filename") == "securewave-linux-x64.deb"
    )
    assert row["status"] == "coming_soon"
    assert "current source" in row["notes"]

    downloads_source = (ROOT / "routes/downloads.py").read_text(encoding="utf-8")
    assert '"filename": "securewave-linux-x64.deb"' in downloads_source
    assert '"status": "coming_soon"' in downloads_source


def test_x64_deb_evidence_workflow_preserves_withheld_manifest_status():
    workflow = (
        ROOT / ".github/workflows/linux-x64-deb-release.yml"
    ).read_text(encoding="utf-8")
    assert 'if deb["status"] != "coming_soon":' in workflow
    assert "linux-x64-deb-status=coming_soon" in workflow


def test_deb_static_identity_helpers_are_redacted_and_architecture_aware():
    control = login_provenance._parse_deb_control(
        "Package: securewave-vpn\n"
        "Version: 4.0.0+3\n"
        "Architecture: amd64\n"
        "Depends: wireguard-tools\n"
        "Maintainer: Private Operator <operator@example.test>\n"
    )
    assert control == {
        "Package": "securewave-vpn",
        "Version": "4.0.0+3",
        "Architecture": "amd64",
        "Depends": "wireguard-tools",
    }
    assert login_provenance._elf_architecture(
        b"\x7fELF\x02\x01" + b"\x00" * 12 + (62).to_bytes(2, "little")
    ) == "x86_64"
    assert login_provenance._elf_architecture(
        b"\x7fELF\x02\x01" + b"\x00" * 12 + (183).to_bytes(2, "little")
    ) == "aarch64"


def test_keyring_dependency_facts_detect_native_linkage_without_raw_strings():
    missing = login_provenance._keyring_dependency_facts(
        depends="wireguard-tools, systemd",
        plugin_bytes=b"libsecret-1.so.0\x00Failed to unlock the keyring\x00",
    )
    assert missing == {
        "secure_storage_plugin_libsecret_linkage_present": True,
        "libsecret_runtime_dependency_declared": False,
        "keyring_runtime_dependency_status": "BLOCKED_KEYRING_DEPENDENCY_UNDECLARED",
    }

    declared = login_provenance._keyring_dependency_facts(
        depends="wireguard-tools, libsecret-1-0 (>= 0.20)",
        plugin_bytes=b"libsecret-1.so.0\x00",
    )
    assert declared["libsecret_runtime_dependency_declared"] is True
    assert declared["keyring_runtime_dependency_status"] == "PASS_KEYRING_DEPENDENCY_DECLARED"


def test_artifact_source_commit_api_facts_are_fingerprinted_and_redacted():
    facts = login_provenance._source_commit_api_facts(
        "6e0517cc379bd6f64b123297d5dc756a6453d9c1"
    )
    assert facts["classification"] == "HISTORICAL_SOURCE_FACT"
    assert facts["source_commit_present"] is True
    assert facts["build_has_explicit_api_define"] is False
    assert facts["build_has_explicit_mock_off_define"] is False
    assert facts["config_loads_dotenv_without_release_guard"] is True
    assert facts["fallback_present"] is True
    assert facts["fallback_fingerprint"]
    assert "fallback_value" not in facts
    assert "https://" not in json.dumps(facts)

    storage_facts = facts["login_storage_facts"]
    assert storage_facts["login_calls_api_before_local_session_work"] is True
    assert storage_facts["historical_login_reads_owner_before_state_clear"] is True
    assert storage_facts["session_memory_authentication_precedes_persistence"] is True
    assert storage_facts["session_persists_before_memory_authentication"] is False


def test_current_login_storage_facts_capture_keyring_order_without_values():
    report = login_provenance.build_report()
    facts = report["current_auth_storage_facts"]
    assert facts["login_calls_api_before_local_session_work"] is True
    assert facts["login_clears_vpn_state_before_session"] is True
    assert facts["session_persists_before_memory_authentication"] is True
    assert facts["session_memory_authentication_precedes_persistence"] is False
    assert facts["session_handles_storage_failure"] is True
    serialized = json.dumps(facts, sort_keys=True)
    assert "https://" not in serialized
    assert "access_token" not in serialized


def test_runtime_log_reports_keyring_signal_without_raw_log(monkeypatch, tmp_path: Path):
    log_path = tmp_path / "application-launch.log"
    log_path.write_text(
        "libsecret_error: Failed to unlock the keyring for user@example.test\n"
        "password=must-not-be-recorded\n",
        encoding="utf-8",
    )
    record = login_provenance._runtime_log_record(log_path)
    assert record["runtime_result"] == "KEYRING_ACCESS_FAILURE_OBSERVED"
    assert record["keyring_unlock_failure_observed"] is True
    assert "user@example.test" not in json.dumps(record)
    assert "must-not-be-recorded" not in json.dumps(record)


def test_installed_runtime_record_matches_fixed_package_paths(tmp_path: Path):
    payload = {
        "usr/bin/securewave-vpn": b"wrapper",
        "usr/lib/securewave/securewave_app": b"app",
    }
    installed_root = tmp_path / "installed"
    for relative, content in payload.items():
        destination = installed_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)

    record = login_provenance._installed_runtime_record(installed_root, payload)

    assert record["comparison"] == "INSTALLED_FILES_MATCH_PACKAGE"
    assert record["classification"] == "CURRENT_RUNTIME_FACT"
    assert all(item["sha256_match"] for item in record["files"])
    assert all("installed_root" not in item for item in record["files"])


def test_installed_runtime_record_detects_fixed_path_mismatch(tmp_path: Path):
    payload = {
        "usr/bin/securewave-vpn": b"wrapper",
        "usr/lib/securewave/securewave_app": b"app",
    }
    installed_root = tmp_path / "installed"
    for relative, content in payload.items():
        destination = installed_root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content + (b"-changed" if relative.endswith("securewave_app") else b""))

    record = login_provenance._installed_runtime_record(installed_root, payload)

    assert record["comparison"] == "INSTALLED_FILES_DO_NOT_MATCH_PACKAGE"
    assert record["classification"] == "CURRENT_RUNTIME_FACT"
    assert any(not item["sha256_match"] for item in record["files"])
