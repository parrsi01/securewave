from pathlib import Path
from subprocess import CompletedProcess

from scripts import linux_vpn_runtime_verifier as verifier


def use_build_bundles(monkeypatch, tmp_path):
    release_bundle = tmp_path / "build/linux/arm64/release/bundle"
    debug_bundle = tmp_path / "build/linux/arm64/debug/bundle"
    monkeypatch.setattr(verifier, "BUILD_RELEASE_BUNDLE_DIR", release_bundle)
    monkeypatch.setattr(verifier, "BUILD_DEBUG_BUNDLE_DIR", debug_bundle)
    return release_bundle, debug_bundle


def test_runner_contract_covers_only_wireguard_runtime():
    checks = {check.name: check for check in verifier.check_runner_contract()}

    assert checks["runner:method_channel"].ok
    assert checks["runner:helper_socket"].ok
    assert checks["runner:helper_request"].ok
    assert checks["runner:wireguard_connect_op"].ok
    assert checks["runner:wireguard_disconnect_op"].ok
    assert checks["runner:wireguard_protocol_gate"].ok
    assert checks["runner:securewave_helper_contract"].ok
    assert checks["runner:no_connect_time_pkexec"].ok


def test_runtime_tool_contract_is_wireguard_only():
    assert verifier.REQUIRED_TOOLS == (
        "wg-quick",
        "wg",
        "ip",
        "iptables",
        "nft",
        "resolvectl",
    )


def test_build_artifact_reports_missing_build(monkeypatch, tmp_path):
    _, debug_bundle = use_build_bundles(monkeypatch, tmp_path)

    check = verifier.check_build_artifact()

    assert not check.ok
    assert str(debug_bundle) in check.detail
    assert "flutter build linux --release" in check.detail


def test_build_artifact_prefers_release_bundle_when_present(monkeypatch, tmp_path):
    release_bundle, debug_bundle = use_build_bundles(monkeypatch, tmp_path)
    release_app = release_bundle / "securewave_app"
    debug_app = debug_bundle / "securewave_app"
    for app in (release_app, debug_app):
        app.parent.mkdir(parents=True, exist_ok=True)
        app.write_text("x", encoding="utf-8")

    check = verifier.check_build_artifact()

    assert check.ok
    assert str(release_app) in check.detail
    assert str(debug_bundle) not in check.detail


def test_build_artifact_falls_back_to_debug_bundle_when_release_missing(monkeypatch, tmp_path):
    _, debug_bundle = use_build_bundles(monkeypatch, tmp_path)
    debug_app = debug_bundle / "securewave_app"
    debug_app.parent.mkdir(parents=True, exist_ok=True)
    debug_app.write_text("x", encoding="utf-8")

    check = verifier.check_build_artifact()

    assert check.ok
    assert str(debug_app) in check.detail


def test_build_helper_payload_reports_wireguard_payload(monkeypatch, tmp_path):
    bundle, _ = use_build_bundles(monkeypatch, tmp_path)
    paths = (
        bundle / "packaging/linux/securewave-wg-quick",
        bundle / "packaging/linux/securewave-helperd",
        bundle / "packaging/linux/securewave-helper.service",
        bundle / "packaging/linux/securewave-helper.tmpfiles",
        bundle / "packaging/linux/securewave-wg-quick.contract",
        bundle / "scripts/install_linux_helper.sh",
    )
    for path in paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x", encoding="utf-8")

    checks = {check.name: check for check in verifier.check_build_helper_payload()}

    assert all(check.ok for check in checks.values())
    assert "build:helper_payload" in checks
    assert "build:helper_installer_payload" in checks


def _completed(argv, *, stdout="", returncode=0, stderr=""):
    return CompletedProcess(argv, returncode, stdout=stdout, stderr=stderr)


def test_active_wireguard_runtime_checks_status_routes_safety_dns_and_counters(monkeypatch):
    status = {
        "ok": "true",
        "status": "connected",
        "route_via_sw_wg": "true",
        "ipv4_route_via_sw_wg": "true",
        "ipv6_route_via_sw_wg": "true",
        "policy_rules_present": "true",
        "policy_routes_present": "true",
        "firewall_inspection_ok": "true",
        "ipv4_kill_switch_present": "true",
        "ipv6_block_present": "true",
        "ipv6_mode": "block",
        "handshake_inspection_ok": "true",
        "handshake_present": "true",
        "endpoint_inspection_ok": "true",
        "endpoint_bypass_present": "true",
        "counters_available": "true",
    }
    monkeypatch.setattr(verifier, "helper_request", lambda fields: status)

    def fake_run(argv):
        if argv[:2] == ["resolvectl", "dns"]:
            return _completed(argv, stdout="Link 7 (sw-wg) DNS Servers: 10.0.0.1\n")
        if argv[:2] == ["resolvectl", "domain"]:
            return _completed(argv, stdout="Link 7 (sw-wg) Current Scopes: DNS\n~.\n")
        raise AssertionError(f"unexpected command: {argv}")

    monkeypatch.setattr(verifier, "_run", fake_run)
    checks = verifier.check_active_runtime("wireguard")

    assert all(check.ok for check in checks), checks


def test_active_wireguard_runtime_fails_without_authenticated_handshake(monkeypatch):
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields: {"ok": "true", "status": "connected", "message": "no handshake"},
    )
    monkeypatch.setattr(
        verifier,
        "_run",
        lambda argv: _completed(argv, stdout="Link 7 (sw-wg) DNS Servers: 10.0.0.1\n~.\n"),
    )

    checks = {check.name: check for check in verifier.check_active_runtime("wireguard")}

    assert not checks["runtime:wireguard:safety"].ok
    assert not checks["runtime:wireguard:route"].ok


def test_non_wireguard_active_runtime_is_rejected():
    checks = verifier.check_active_runtime("openvpn")

    assert len(checks) == 1
    assert not checks[0].ok
    assert "WireGuard only" in checks[0].detail
