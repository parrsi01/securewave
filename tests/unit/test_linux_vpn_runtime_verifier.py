from pathlib import Path
from subprocess import CompletedProcess

from scripts import linux_vpn_runtime_verifier as verifier


def test_run_reports_an_optional_missing_tool(monkeypatch):
    def missing(*args, **kwargs):
        raise FileNotFoundError

    monkeypatch.setattr(verifier.subprocess, "run", missing)

    result = verifier._run(["swanctl", "--list-sas"])

    assert result.returncode == 127
    assert result.stdout == ""
    assert result.stderr == "swanctl is not installed"


def test_ikev2_tools_are_required_only_for_active_ikev2(monkeypatch):
    monkeypatch.setattr(verifier.shutil, "which", lambda tool: f"/usr/bin/{tool}")

    disconnected = {check.name for check in verifier.check_tools()}
    ikev2 = {check.name for check in verifier.check_tools("ikev2")}

    assert "tool:swanctl" not in disconnected
    assert "tool:ipsec" not in disconnected
    assert {"tool:swanctl", "tool:ipsec"} <= ikev2


def use_build_bundles(monkeypatch, tmp_path):
    release_bundle = tmp_path / "build/linux/arm64/release/bundle"
    debug_bundle = tmp_path / "build/linux/arm64/debug/bundle"
    monkeypatch.setattr(verifier, "BUILD_RELEASE_BUNDLE_DIR", release_bundle)
    monkeypatch.setattr(verifier, "BUILD_DEBUG_BUNDLE_DIR", debug_bundle)
    return release_bundle, debug_bundle


def test_runner_contract_covers_all_protocol_runtime_evidence():
    checks = {check.name: check for check in verifier.check_runner_contract()}

    assert checks["runner:method_channel"].ok
    assert checks["runner:helper_socket"].ok
    assert checks["runner:helper_request"].ok
    assert checks["runner:wireguard_connect_op"].ok
    assert checks["runner:wireguard_disconnect_op"].ok
    assert checks["runner:openvpn_connect_op"].ok
    assert checks["runner:openvpn_disconnect_op"].ok
    assert checks["runner:ikev2_connect_op"].ok
    assert checks["runner:ikev2_disconnect_op"].ok
    assert checks["runner:securewave_helper_contract"].ok
    assert checks["runner:no_implicit_mock"].ok


def test_build_artifact_check_reports_missing_build(monkeypatch, tmp_path):
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
    assert str(release_bundle) in check.detail
    assert str(debug_bundle) not in check.detail


def test_build_artifact_falls_back_to_debug_bundle_when_release_missing(monkeypatch, tmp_path):
    _, debug_bundle = use_build_bundles(monkeypatch, tmp_path)
    debug_app = debug_bundle / "securewave_app"
    debug_app.parent.mkdir(parents=True, exist_ok=True)
    debug_app.write_text("x", encoding="utf-8")

    check = verifier.check_build_artifact()

    assert check.ok
    assert str(debug_app) in check.detail
    assert str(debug_bundle) in check.detail


def test_build_helper_payload_reports_bundle_payload(monkeypatch, tmp_path):
    bundle, _ = use_build_bundles(monkeypatch, tmp_path)
    helper = bundle / "packaging/linux/securewave-wg-quick"
    contract = bundle / "packaging/linux/securewave-wg-quick.contract"
    helperd = bundle / "packaging/linux/securewave-helperd"
    service = bundle / "packaging/linux/securewave-helper.service"
    tmpfiles = bundle / "packaging/linux/securewave-helper.tmpfiles"
    installer = bundle / "scripts/install_linux_helper.sh"
    for path in (helper, contract, helperd, service, tmpfiles, installer):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x", encoding="utf-8")

    checks = {check.name: check for check in verifier.check_build_helper_payload()}

    assert checks["build:helper_payload"].ok
    assert checks["build:helperd_payload"].ok
    assert checks["build:helper_service_payload"].ok
    assert checks["build:helper_tmpfiles_payload"].ok
    assert checks["build:helper_contract_payload"].ok
    assert checks["build:helper_installer_payload"].ok
    assert all(str(bundle) in check.detail for check in checks.values())


def test_residue_checks_fail_on_securewave_leftovers(monkeypatch):
    outputs = {
        ("ip", "link", "show", "sw-wg"): CompletedProcess(
            args=[], returncode=0, stdout="7: sw-wg: <POINTOPOINT>\n", stderr=""
        ),
        ("ip", "link", "show", "tun0"): CompletedProcess(
            args=[], returncode=0, stdout="8: tun0: <POINTOPOINT>\n", stderr=""
        ),
        ("ip", "route", "show"): CompletedProcess(
            args=[],
            returncode=0,
            stdout="default dev sw-wg table 51820\n0.0.0.0/1 dev tun0\n128.0.0.0/1 dev tun0\n",
            stderr="",
        ),
        ("ip", "rule", "show"): CompletedProcess(
            args=[], returncode=0, stdout="32765: from all lookup 51820\n", stderr=""
        ),
        ("ip", "-4", "route", "show", "table", "51820"): CompletedProcess(
            args=[], returncode=0, stdout="default dev sw-wg\n", stderr=""
        ),
        ("ip", "-6", "route", "show", "table", "51820"): CompletedProcess(
            args=[], returncode=0, stdout="", stderr=""
        ),
        ("pgrep", "-af", "openvpn"): CompletedProcess(
            args=[], returncode=0, stdout="123 openvpn --config /tmp/securewave.ovpn\n", stderr=""
        ),
        ("swanctl", "--list-sas"): CompletedProcess(
            args=[], returncode=0, stdout="securewave: #1, ESTABLISHED\n", stderr=""
        ),
        ("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"): CompletedProcess(
            args=[], returncode=0, stdout="SecureWave-IKEv2:vpn\n", stderr=""
        ),
        ("nmcli", "-t", "-f", "GENERAL.DEVICE,IP4.DNS,IP6.DNS", "device", "show"): CompletedProcess(
            args=[], returncode=0, stdout="GENERAL.DEVICE:sw-wg\nIP4.DNS[1]:redacted\n", stderr=""
        ),
    }

    def fake_run(argv):
        return outputs[tuple(argv)]

    monkeypatch.setattr(verifier, "_run", fake_run)

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:wireguard_interface"].ok
    assert not checks["residue:tun0_interface"].ok
    assert not checks["residue:tunnel_routes"].ok
    assert not checks["residue:wireguard_policy_rules"].ok
    assert not checks["residue:wireguard_policy_routes"].ok
    assert checks["residue:ikev2_pref_220_loop"].ok
    assert not checks["residue:openvpn_process"].ok
    assert not checks["residue:ikev2_sa"].ok
    assert not checks["residue:ikev2_nm_connection"].ok
    assert not checks["residue:vpn_dns"].ok


def test_verifier_paths_stay_inside_repo():
    assert verifier.RUNNER_PATH == Path("securewave_app/linux/runner/my_application.cc").resolve()


def test_helper_ipc_reports_promptless_service_probe(monkeypatch):
    def fake_helper_request(fields, timeout=5.0):
        op = fields["op"]
        if op == "probe" and fields["protocol"] == "wireguard":
            return {"ok": "true", "service_version": "1", "message": "OK"}
        if op == "probe" and fields["protocol"] == "openvpn":
            return {"ok": "false", "code": "tool_missing", "service_version": "1", "message": "missing"}
        if op == "probe" and fields["protocol"] == "ikev2":
            return {
                "ok": "true",
                "service_version": "1",
                "message": "OK",
            }
        if op == "shell":
            return {
                "ok": "false",
                "code": "invalid_operation",
                "service_version": "1",
                "message": "no",
            }
        raise AssertionError(fields)

    monkeypatch.setattr(verifier, "helper_request", fake_helper_request)

    checks = {check.name: check for check in verifier.check_helper_ipc()}

    assert checks["privilege:helper_probe:wireguard"].ok
    assert checks["privilege:helper_probe:openvpn"].ok
    assert checks["privilege:helper_probe:ikev2"].ok
    assert checks["privilege:helper_invalid_op_fails_closed"].ok


def test_helper_ipc_rejects_disabled_ikev2_probe(monkeypatch):
    def fake_helper_request(fields, timeout=5.0):
        if fields["op"] == "probe":
            return {
                "ok": "false",
                "code": "protocol_unavailable",
                "service_version": "1",
                "message": "IKEv2 disabled",
            }
        return {
            "ok": "false",
            "code": "invalid_operation",
            "service_version": "1",
            "message": "no",
        }

    monkeypatch.setattr(verifier, "helper_request", fake_helper_request)

    checks = {check.name: check for check in verifier.check_helper_ipc()}

    assert not checks["privilege:helper_probe:ikev2"].ok


def test_installed_helper_contract_requires_ikev2_contract(monkeypatch, tmp_path):
    contract = tmp_path / "securewave-wg-quick.contract"
    contract.write_text("5\n", encoding="utf-8")
    monkeypatch.setattr(verifier, "HELPER_CONTRACT_PATH", contract)

    check = verifier.check_installed_helper_contract()

    assert not check.ok
    assert "required 10" in check.detail


def test_no_polkit_source_enforces_service_socket_model():
    checks = {check.name: check for check in verifier.check_no_polkit_source()}

    assert checks["privilege:no_packaged_polkit_rule"].ok
    assert checks["runner:no_connect_time_pkexec"].ok


def test_active_ikev2_requires_route_dns_xfrm_and_no_pref220_loop(monkeypatch):
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields, timeout=5.0: {
            "ok": "true",
            "status": "connected",
            "route_or_dns_present": "true",
            "xfrm_esp_present": "true",
            "routing_loop_rule_present": "false",
            "counters_available": "true",
        },
    )

    def fake_run(argv):
        if "GENERAL.DEVICES" in argv:
            return CompletedProcess(args=argv, returncode=0, stdout="nm-xfrm-1\n", stderr="")
        if "IP4.DNS,IP6.DNS" in argv:
            return CompletedProcess(args=argv, returncode=0, stdout="redacted\n", stderr="")
        raise AssertionError(argv)

    monkeypatch.setattr(verifier, "_run", fake_run)

    checks = {check.name: check for check in verifier.check_active_runtime("ikev2")}

    assert checks["runtime:ikev2:status"].ok
    assert checks["runtime:ikev2:route"].ok
    assert checks["runtime:ikev2:safety"].ok
    assert checks["runtime:ikev2:dns"].ok
    assert checks["runtime:ikev2:counters"].ok


def test_active_ikev2_fails_closed_on_pref220_loop(monkeypatch):
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields, timeout=5.0: {
            "ok": "true",
            "status": "disconnected",
            "route_or_dns_present": "true",
            "xfrm_esp_present": "true",
            "routing_loop_rule_present": "true",
            "counters_available": "true",
        },
    )
    monkeypatch.setattr(
        verifier,
        "_run",
        lambda argv: CompletedProcess(args=argv, returncode=0, stdout="", stderr=""),
    )

    checks = {check.name: check for check in verifier.check_active_runtime("ikev2")}

    assert not checks["runtime:ikev2:status"].ok
    assert not checks["runtime:ikev2:safety"].ok
    assert not checks["runtime:ikev2:dns"].ok


def test_external_probes_compare_ips_without_exposing_values(monkeypatch, tmp_path):
    baseline = tmp_path / "baseline-ip.txt"
    baseline.write_text("203.0.113.1\n", encoding="utf-8")

    class Response:
        def __init__(self, body: bytes, status: int = 200):
            self.body = body
            self.status = status

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, traceback):
            return False

        def read(self, limit: int) -> bytes:
            return self.body[:limit]

    responses = iter([Response(b"203.0.113.2"), Response(b"ok")])
    monkeypatch.setattr(verifier.urllib.request, "urlopen", lambda *args, **kwargs: next(responses))

    checks = verifier.check_external_data_plane(
        baseline,
        "https://exit.example.invalid/",
        "https://data.example.invalid/",
    )

    assert all(check.ok for check in checks)
    assert all("203.0.113" not in check.detail for check in checks)
