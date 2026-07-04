from pathlib import Path
from subprocess import CompletedProcess

from scripts import linux_vpn_runtime_verifier as verifier


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
        ("iptables", "-S", "SECUREWAVE_ADBLOCK"): CompletedProcess(
            args=[], returncode=0, stdout="-N SECUREWAVE_ADBLOCK\n", stderr=""
        ),
        ("pgrep", "-x", "openvpn"): CompletedProcess(
            args=[], returncode=0, stdout="123\n", stderr=""
        ),
        ("swanctl", "--list-sas"): CompletedProcess(
            args=[], returncode=0, stdout="securewave: #1, ESTABLISHED\n", stderr=""
        ),
        ("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"): CompletedProcess(
            args=[], returncode=0, stdout="SecureWave-IKEv2:vpn\n", stderr=""
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
    assert not checks["residue:adblock_chain"].ok
    assert not checks["residue:openvpn_process"].ok
    assert not checks["residue:ikev2_sa"].ok
    assert not checks["residue:ikev2_nm_connection"].ok


def test_residue_adblock_chain_passes_when_absent(monkeypatch):
    outputs = {
        ("ip", "link", "show", "sw-wg"): CompletedProcess(
            args=[], returncode=1, stdout="", stderr="Device does not exist"
        ),
        ("ip", "link", "show", "tun0"): CompletedProcess(
            args=[], returncode=1, stdout="", stderr="Device does not exist"
        ),
        ("ip", "route", "show"): CompletedProcess(
            args=[], returncode=0, stdout="", stderr=""
        ),
        ("ip", "rule", "show"): CompletedProcess(
            args=[], returncode=0, stdout="", stderr=""
        ),
        ("ip", "-4", "route", "show", "table", "51820"): CompletedProcess(
            args=[], returncode=2, stdout="", stderr="Error: ipv4: FIB table does not exist."
        ),
        ("ip", "-6", "route", "show", "table", "51820"): CompletedProcess(
            args=[], returncode=2, stdout="", stderr="Error: ipv6: FIB table does not exist."
        ),
        ("iptables", "-S", "SECUREWAVE_ADBLOCK"): CompletedProcess(
            args=[], returncode=1, stdout="", stderr="No chain/target/match by that name."
        ),
        ("pgrep", "-x", "openvpn"): CompletedProcess(
            args=[], returncode=1, stdout="", stderr=""
        ),
        ("swanctl", "--list-sas"): CompletedProcess(
            args=[], returncode=0, stdout="", stderr=""
        ),
        ("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"): CompletedProcess(
            args=[], returncode=0, stdout="", stderr=""
        ),
    }

    def fake_run(argv):
        return outputs[tuple(argv)]

    monkeypatch.setattr(verifier, "_run", fake_run)

    checks = {check.name: check for check in verifier.check_residue()}

    assert checks["residue:adblock_chain"].ok
    assert "SECUREWAVE_ADBLOCK chain absent" in checks["residue:adblock_chain"].detail


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
    assert "required 9" in check.detail


def test_adblock_contract_requires_contract_8(monkeypatch, tmp_path):
    contract = tmp_path / "securewave-wg-quick.contract"
    contract.write_text("7\n", encoding="utf-8")
    monkeypatch.setattr(verifier, "HELPER_CONTRACT_PATH", contract)

    check = verifier.check_adblock_contract()

    assert not check.ok
    assert "required 8" in check.detail


def test_adblock_contract_accepts_contract_8(monkeypatch, tmp_path):
    contract = tmp_path / "securewave-wg-quick.contract"
    contract.write_text("8\n", encoding="utf-8")
    monkeypatch.setattr(verifier, "HELPER_CONTRACT_PATH", contract)

    check = verifier.check_adblock_contract()

    assert check.ok
    assert "installed contract 8" in check.detail


def test_no_polkit_source_enforces_service_socket_model():
    checks = {check.name: check for check in verifier.check_no_polkit_source()}

    assert checks["privilege:no_packaged_polkit_rule"].ok
    assert checks["runner:no_connect_time_pkexec"].ok
