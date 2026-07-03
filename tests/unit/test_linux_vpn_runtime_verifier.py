from pathlib import Path
from subprocess import CompletedProcess

from scripts import linux_vpn_runtime_verifier as verifier


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
    missing = tmp_path / "securewave_app"
    monkeypatch.setattr(verifier, "BUILD_PATH", missing)

    check = verifier.check_build_artifact()

    assert not check.ok
    assert "flutter build linux --debug" in check.detail


def test_build_helper_payload_reports_bundle_payload(monkeypatch, tmp_path):
    bundle = tmp_path / "bundle"
    helper = bundle / "packaging/linux/securewave-wg-quick"
    contract = bundle / "packaging/linux/securewave-wg-quick.contract"
    helperd = bundle / "packaging/linux/securewave-helperd"
    service = bundle / "packaging/linux/securewave-helper.service"
    tmpfiles = bundle / "packaging/linux/securewave-helper.tmpfiles"
    installer = bundle / "scripts/install_linux_helper.sh"
    for path in (helper, contract, helperd, service, tmpfiles, installer):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x", encoding="utf-8")
    monkeypatch.setattr(verifier, "BUILD_BUNDLE_DIR", bundle)

    checks = {check.name: check for check in verifier.check_build_helper_payload()}

    assert checks["build:helper_payload"].ok
    assert checks["build:helperd_payload"].ok
    assert checks["build:helper_service_payload"].ok
    assert checks["build:helper_tmpfiles_payload"].ok
    assert checks["build:helper_contract_payload"].ok
    assert checks["build:helper_installer_payload"].ok


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
    assert not checks["residue:openvpn_process"].ok
    assert not checks["residue:ikev2_sa"].ok
    assert not checks["residue:ikev2_nm_connection"].ok


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
                "ok": "false",
                "code": "protocol_unavailable",
                "service_version": "1",
                "message": "IKEv2 disabled",
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


def test_installed_helper_contract_requires_ikev2_contract(monkeypatch, tmp_path):
    contract = tmp_path / "securewave-wg-quick.contract"
    contract.write_text("5\n", encoding="utf-8")
    monkeypatch.setattr(verifier, "HELPER_CONTRACT_PATH", contract)

    check = verifier.check_installed_helper_contract()

    assert not check.ok
    assert "required 9" in check.detail


def test_no_polkit_source_enforces_service_socket_model():
    checks = {check.name: check for check in verifier.check_no_polkit_source()}

    assert checks["privilege:no_packaged_polkit_rule"].ok
    assert checks["runner:no_connect_time_pkexec"].ok
