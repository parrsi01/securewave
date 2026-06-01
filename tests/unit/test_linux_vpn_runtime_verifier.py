from pathlib import Path
from subprocess import CompletedProcess, TimeoutExpired

from scripts import linux_vpn_runtime_verifier as verifier


def test_runner_contract_covers_all_protocol_runtime_evidence():
    checks = {check.name: check for check in verifier.check_runner_contract()}

    assert checks["runner:wireguard"].ok
    assert checks["runner:wireguard_route_evidence"].ok
    assert checks["runner:openvpn"].ok
    assert checks["runner:openvpn_helper_start"].ok
    assert checks["runner:openvpn_helper_stop"].ok
    assert checks["runner:ikev2"].ok
    assert checks["runner:openvpn_tunnel_evidence"].ok
    assert checks["runner:ikev2_sa_evidence"].ok


def test_build_artifact_check_reports_missing_build(monkeypatch, tmp_path):
    missing = tmp_path / "securewave_app"
    monkeypatch.setattr(verifier, "BUILD_PATH", missing)

    check = verifier.check_build_artifact()

    assert not check.ok
    assert "flutter build linux --debug" in check.detail


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
        ("pgrep", "-af", "securewave-openvpn|openvpn.*securewave"): CompletedProcess(
            args=[], returncode=0, stdout="123 openvpn --daemon securewave-openvpn\n", stderr=""
        ),
        ("swanctl", "--list-sas"): CompletedProcess(
            args=[], returncode=0, stdout="securewave: #1, ESTABLISHED\n", stderr=""
        ),
    }

    def fake_run(argv):
        return outputs[tuple(argv)]

    monkeypatch.setattr(verifier, "_run", fake_run)

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:wireguard_interface"].ok
    assert not checks["residue:tun0_interface"].ok
    assert not checks["residue:tunnel_routes"].ok
    assert not checks["residue:openvpn_process"].ok
    assert not checks["residue:ikev2_sa"].ok


def test_verifier_paths_stay_inside_repo():
    assert verifier.RUNNER_PATH == Path("securewave_app/linux/runner/my_application.cc").resolve()


def test_privilege_check_reports_pkexec_timeout(monkeypatch):
    monkeypatch.setattr(verifier.shutil, "which", lambda tool: "/usr/bin/pkexec")
    monkeypatch.setattr(verifier.os, "geteuid", lambda: 1000)

    def fake_run(*args, **kwargs):
        raise TimeoutExpired(cmd=["pkexec", "/usr/bin/true"], timeout=5)

    monkeypatch.setattr(verifier.subprocess, "run", fake_run)

    check = verifier.check_privilege_elevation()

    assert not check.ok
    assert "pkexec authorization timed out" in check.detail
