from pathlib import Path
from subprocess import CompletedProcess

import pytest

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


def test_runtime_tool_contract_includes_nftables_inspection():
    assert "nft" in verifier.REQUIRED_TOOLS


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
    strongswan_routing = bundle / "packaging/linux/securewave-strongswan-routing.conf"
    installer = bundle / "scripts/install_linux_helper.sh"
    for path in (helper, contract, helperd, service, tmpfiles, strongswan_routing, installer):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x", encoding="utf-8")

    checks = {check.name: check for check in verifier.check_build_helper_payload()}

    assert checks["build:helper_payload"].ok
    assert checks["build:helperd_payload"].ok
    assert checks["build:helper_service_payload"].ok
    assert checks["build:helper_tmpfiles_payload"].ok
    assert checks["build:helper_contract_payload"].ok
    assert checks["build:strongswan_routing_payload"].ok
    assert checks["build:helper_installer_payload"].ok
    assert all(str(bundle) in check.detail for check in checks.values())


def test_installed_strongswan_routing_config_must_match_source(monkeypatch, tmp_path):
    source = tmp_path / "source.conf"
    installed = tmp_path / "installed.conf"
    source.write_text("fwmark = !0xdc\n", encoding="utf-8")
    installed.write_text("fwmark = !0xdc\n", encoding="utf-8")
    monkeypatch.setattr(verifier, "STRONGSWAN_ROUTING_SOURCE_PATH", source)
    monkeypatch.setattr(verifier, "STRONGSWAN_ROUTING_CONFIG_PATH", installed)

    assert verifier.check_strongswan_routing_install().ok

    installed.write_text("fwmark = 0x99\n", encoding="utf-8")
    check = verifier.check_strongswan_routing_install()
    assert not check.ok
    assert "differ" in check.detail


def test_residue_checks_fail_on_securewave_leftovers(monkeypatch):
    outputs = {
        ("ip", "-o", "link", "show"): CompletedProcess(
            args=[],
            returncode=0,
            stdout=(
                "7: sw-wg: <POINTOPOINT>\n"
                "8: tun12: <POINTOPOINT>\n"
                "9: nm-xfrm-7@NONE: <POINTOPOINT>\n"
                "10: tun-securewave: <POINTOPOINT>\n"
            ),
            stderr="",
        ),
        ("ip", "route", "show"): CompletedProcess(
            args=[],
            returncode=0,
            stdout=(
                "default dev sw-wg table 51820\n"
                "0.0.0.0/1 dev tun12\n"
                "128.0.0.0/1 dev nm-xfrm-7\n"
            ),
            stderr="",
        ),
        ("ip", "-4", "rule", "show"): CompletedProcess(
            args=[],
            returncode=0,
            stdout=(
                "220: not from all fwmark 0xdc lookup 220\n"
                "32765: from all lookup 51820\n"
            ),
            stderr="",
        ),
        ("ip", "-6", "rule", "show"): CompletedProcess(
            args=[], returncode=0, stdout="", stderr=""
        ),
        ("ip", "-4", "route", "show", "table", "51820"): CompletedProcess(
            args=[], returncode=0, stdout="default dev sw-wg\n", stderr=""
        ),
        ("ip", "-6", "route", "show", "table", "51820"): CompletedProcess(
            args=[], returncode=0, stdout="", stderr=""
        ),
        ("ip", "-4", "route", "show", "table", "220"): CompletedProcess(
            args=[],
            returncode=0,
            stdout="203.0.113.0/24 via 192.0.2.1 dev enp0s1\n",
            stderr="",
        ),
        ("ip", "-6", "route", "show", "table", "220"): CompletedProcess(
            args=[], returncode=0, stdout="", stderr=""
        ),
        ("pgrep", "-af", "openvpn"): CompletedProcess(
            args=[], returncode=0, stdout="123 openvpn --config /tmp/securewave.ovpn\n", stderr=""
        ),
        ("nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"): CompletedProcess(
            args=[], returncode=0, stdout="SecureWave-IKEv2:vpn\n", stderr=""
        ),
        ("nmcli", "-t", "-f", "GENERAL.DEVICE,IP4.DNS,IP6.DNS", "device", "show"): CompletedProcess(
            args=[],
            returncode=0,
            stdout=(
                "GENERAL.DEVICE:tun12\nIP4.DNS[1]:redacted\n"
                "GENERAL.DEVICE:nm-xfrm-7\nIP6.DNS[1]:redacted\n"
                "GENERAL.DEVICE:tun-securewave\nIP4.DNS[1]:redacted\n"
            ),
            stderr="",
        ),
    }

    def fake_run(argv):
        return outputs[tuple(argv)]

    monkeypatch.setattr(verifier, "_run", fake_run)
    def fake_helper_request(fields):
        if fields == {"op": "wireguard.status"}:
            return {
                "ok": "true",
                "contract": "13",
                "status": "connected",
                "firewall_inspection_ok": "true",
                "nft_table_present": "true",
                "iptables_rule_present": "true",
                "ip6tables_rule_present": "true",
                "firewall_residue_present": "true",
            }
        if fields == {"op": "firewall.adblock_status"}:
            return {"ok": "true", "contract": "13", "present": "true"}
        if fields == {"op": "ikev2.status"}:
            return {
                "ok": "true",
                "contract": "13",
                "status": "connected",
                "connection_inspection_ok": "true",
                "connection_present": "true",
                "nm_active": "true",
                "xfrm_state_inspection_ok": "true",
                "xfrm_state_present": "true",
                "xfrm_esp_present": "true",
                "xfrm_policy_inspection_ok": "true",
                "xfrm_policy_present": "true",
            }
        raise AssertionError(fields)

    monkeypatch.setattr(verifier, "helper_request", fake_helper_request)

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:wireguard_firewall"].ok
    assert not checks["residue:wireguard_interface"].ok
    assert not checks["residue:tun0_interface"].ok
    assert not checks["residue:tunnel_routes"].ok
    assert not checks["residue:wireguard_policy_rules"].ok
    assert not checks["residue:wireguard_policy_routes"].ok
    assert not checks["residue:ikev2_pref_220_loop"].ok
    assert not checks["residue:ikev2_table_220_routes"].ok
    assert not checks["residue:adblock_chain"].ok
    assert "rules redacted" in checks["residue:adblock_chain"].detail
    assert not checks["residue:openvpn_process"].ok
    assert not checks["residue:ikev2_sa"].ok
    assert not checks["residue:ikev2_nm_connection"].ok
    assert not checks["residue:vpn_dns"].ok
    assert "3 tunnel interfaces" in checks["residue:vpn_dns"].detail


def _clean_disconnected_wireguard_status(**overrides):
    response = {
        "ok": "true",
        "contract": "13",
        "status": "disconnected",
        "firewall_inspection_ok": "true",
        "nft_table_present": "false",
        "iptables_rule_present": "false",
        "ip6tables_rule_present": "false",
        "firewall_residue_present": "false",
    }
    response.update(overrides)
    return response


def _clean_disconnected_ikev2_status(**overrides):
    response = {
        "ok": "true",
        "contract": "13",
        "status": "disconnected",
        "connection_inspection_ok": "true",
        "connection_present": "false",
        "nm_active": "false",
        "xfrm_state_inspection_ok": "true",
        "xfrm_state_present": "false",
        "xfrm_esp_present": "false",
        "xfrm_policy_inspection_ok": "true",
        "xfrm_policy_present": "false",
    }
    response.update(overrides)
    return response


def _mock_clean_disconnected_runtime(
    monkeypatch,
    ikev2_status,
    *,
    wireguard_status=None,
):
    wireguard_status = (
        _clean_disconnected_wireguard_status()
        if wireguard_status is None
        else wireguard_status
    )

    def fake_run(argv):
        return CompletedProcess(args=argv, returncode=0, stdout="", stderr="")

    def fake_helper_request(fields):
        if fields == {"op": "wireguard.status"}:
            return wireguard_status
        if fields == {"op": "firewall.adblock_status"}:
            return {"ok": "true", "contract": "13", "present": "false"}
        if fields == {"op": "ikev2.status"}:
            return ikev2_status
        raise AssertionError(fields)

    monkeypatch.setattr(verifier, "_run", fake_run)
    monkeypatch.setattr(verifier, "helper_request", fake_helper_request)


def test_residue_privileged_checks_accept_clean_wireguard_and_ikev2_status(monkeypatch):
    _mock_clean_disconnected_runtime(
        monkeypatch,
        _clean_disconnected_ikev2_status(),
    )

    checks = {check.name: check for check in verifier.check_residue()}

    assert checks["residue:wireguard_firewall"].ok
    assert checks["residue:ikev2_sa"].ok


def test_residue_interfaces_fail_closed_when_all_links_inspection_fails(monkeypatch):
    _mock_clean_disconnected_runtime(
        monkeypatch,
        _clean_disconnected_ikev2_status(),
    )

    def fake_run(argv):
        if argv == ["ip", "-o", "link", "show"]:
            return CompletedProcess(
                args=argv,
                returncode=2,
                stdout="",
                stderr="permission denied",
            )
        return CompletedProcess(args=argv, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(verifier, "_run", fake_run)

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:wireguard_interface"].ok
    assert checks["residue:wireguard_interface"].detail == "interface inspection failed"
    assert not checks["residue:tun0_interface"].ok
    assert checks["residue:tun0_interface"].detail == "tunnel interface inspection failed"


def test_residue_openvpn_process_fails_closed_on_pgrep_error_without_output(
    monkeypatch,
):
    _mock_clean_disconnected_runtime(
        monkeypatch,
        _clean_disconnected_ikev2_status(),
    )

    def fake_run(argv):
        if argv == ["pgrep", "-af", "openvpn"]:
            return CompletedProcess(
                args=argv,
                returncode=2,
                stdout="",
                stderr="process inspection failed",
            )
        return CompletedProcess(args=argv, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(verifier, "_run", fake_run)

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:openvpn_process"].ok
    assert checks["residue:openvpn_process"].detail == "OpenVPN process inspection failed"


@pytest.mark.parametrize(
    "override",
    (
        {"contract": "12"},
        {"status": "connected"},
        {"firewall_inspection_ok": "false"},
        {"nft_table_present": "true"},
        {"iptables_rule_present": "true"},
        {"ip6tables_rule_present": "true"},
        {"firewall_residue_present": "true"},
    ),
)
def test_residue_wireguard_firewall_fails_closed_on_inspection_or_residue(
    monkeypatch, override
):
    _mock_clean_disconnected_runtime(
        monkeypatch,
        _clean_disconnected_ikev2_status(),
        wireguard_status=_clean_disconnected_wireguard_status(**override),
    )

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:wireguard_firewall"].ok
    assert "inspection failed or owned residue remains" in checks[
        "residue:wireguard_firewall"
    ].detail


@pytest.mark.parametrize(
    "override",
    (
        {"contract": "12"},
        {"status": "connected"},
        {"connection_inspection_ok": "false"},
        {"connection_present": "true"},
        {"nm_active": "true"},
        {"xfrm_state_inspection_ok": "false"},
        {"xfrm_state_present": "true"},
        {"xfrm_esp_present": "true"},
        {"xfrm_policy_inspection_ok": "false"},
        {"xfrm_policy_present": "true"},
    ),
)
def test_residue_ikev2_kernel_check_fails_closed_on_incomplete_or_dirty_status(
    monkeypatch, override
):
    _mock_clean_disconnected_runtime(
        monkeypatch,
        _clean_disconnected_ikev2_status(**override),
    )

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:ikev2_sa"].ok
    assert "inspection failed or state/policy remains" in checks["residue:ikev2_sa"].detail


def test_residue_adblock_chain_passes_only_when_absent(monkeypatch):
    def fake_run(argv):
        return CompletedProcess(args=[], returncode=1, stdout="", stderr="unavailable")

    monkeypatch.setattr(verifier, "_run", fake_run)
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields: {
            "ok": "true",
            "contract": "13",
            "present": "false",
        },
    )

    checks = {check.name: check for check in verifier.check_residue()}

    assert checks["residue:adblock_chain"].ok
    assert checks["residue:adblock_chain"].detail == "SECUREWAVE_ADBLOCK chain absent"


def test_residue_adblock_chain_fails_closed_when_helper_cannot_inspect(monkeypatch):
    monkeypatch.setattr(
        verifier,
        "_run",
        lambda argv: CompletedProcess(
            args=[], returncode=1, stdout="", stderr="unavailable"
        ),
    )
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields: {
            "ok": "false",
            "code": "inspection_failed",
            "contract": "13",
            "message": "Unable to inspect legacy SecureWave adblock firewall state.",
        },
    )

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:adblock_chain"].ok
    assert "could not be inspected safely" in checks["residue:adblock_chain"].detail


def test_residue_adblock_chain_rejects_old_or_missing_helper_contract(monkeypatch):
    monkeypatch.setattr(
        verifier,
        "_run",
        lambda argv: CompletedProcess(
            args=[], returncode=1, stdout="", stderr="unavailable"
        ),
    )
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields: {"ok": "true", "contract": "11", "present": "false"},
    )

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:adblock_chain"].ok
    assert "could not be inspected safely" in checks["residue:adblock_chain"].detail


def test_residue_rejects_even_safe_active_ipv6_pref_220_rule_when_disconnected(
    monkeypatch,
):
    def fake_run(argv):
        command = tuple(argv)
        if command == ("ip", "-4", "rule", "show"):
            return CompletedProcess(args=argv, returncode=0, stdout="", stderr="")
        if command == ("ip", "-6", "rule", "show"):
            return CompletedProcess(
                args=argv,
                returncode=0,
                stdout="220:\tfrom all not fwmark 0xdc/0xffffffff table 220\n",
                stderr="",
            )
        if command[:2] == ("ip", "link"):
            return CompletedProcess(args=argv, returncode=1, stdout="", stderr="missing")
        if command in {
            ("ip", "-4", "route", "show", "table", "51820"),
            ("ip", "-6", "route", "show", "table", "51820"),
            ("ip", "-4", "route", "show", "table", "220"),
            ("ip", "-6", "route", "show", "table", "220"),
        }:
            return CompletedProcess(args=argv, returncode=0, stdout="", stderr="")
        return CompletedProcess(args=argv, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(verifier, "_run", fake_run)
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields: {"ok": "true", "contract": "13", "present": "false"},
    )

    checks = {check.name: check for check in verifier.check_residue()}

    assert not checks["residue:ikev2_pref_220_loop"].ok
    assert "-6" in checks["residue:ikev2_pref_220_loop"].detail


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
    assert "required 13" in check.detail


def test_no_polkit_source_enforces_service_socket_model():
    checks = {check.name: check for check in verifier.check_no_polkit_source()}

    assert checks["privilege:no_packaged_polkit_rule"].ok
    assert checks["runner:no_connect_time_pkexec"].ok


def _active_wireguard_status(**overrides):
    response = {
        "ok": "true",
        "status": "connected",
        "route_via_sw_wg": "true",
        "policy_rules_present": "true",
        "policy_routes_present": "true",
        "firewall_inspection_ok": "true",
        "counters_available": "true",
    }
    response.update(overrides)
    return response


def _active_wireguard_dns_run(argv):
    if argv == ["resolvectl", "dns", verifier.WIREGUARD_INTERFACE]:
        return CompletedProcess(
            args=argv,
            returncode=0,
            stdout="Link 8 (sw-wg): redacted\n",
            stderr="",
        )
    if argv == ["resolvectl", "domain", verifier.WIREGUARD_INTERFACE]:
        return CompletedProcess(
            args=argv,
            returncode=0,
            stdout="Link 8 (sw-wg): ~.\n",
            stderr="",
        )
    raise AssertionError(argv)


def test_active_wireguard_requires_policy_routes_rules_and_firewall_inspection(
    monkeypatch,
):
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields, timeout=5.0: _active_wireguard_status(),
    )
    monkeypatch.setattr(verifier, "_run", _active_wireguard_dns_run)

    checks = {
        check.name: check for check in verifier.check_active_runtime("wireguard")
    }

    assert checks["runtime:wireguard:status"].ok
    assert checks["runtime:wireguard:route"].ok
    assert checks["runtime:wireguard:safety"].ok
    assert checks["runtime:wireguard:dns"].ok
    assert checks["runtime:wireguard:counters"].ok


@pytest.mark.parametrize(
    "override",
    (
        {"policy_rules_present": "false"},
        {"policy_routes_present": "false"},
        {"firewall_inspection_ok": "false"},
    ),
)
def test_active_wireguard_fails_closed_on_missing_safety_evidence(
    monkeypatch, override
):
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields, timeout=5.0: _active_wireguard_status(**override),
    )
    monkeypatch.setattr(verifier, "_run", _active_wireguard_dns_run)

    checks = {
        check.name: check for check in verifier.check_active_runtime("wireguard")
    }

    assert not checks["runtime:wireguard:safety"].ok


def _active_ikev2_status(**overrides):
    response = {
        "ok": "true",
        "status": "connected",
        "connection_inspection_ok": "true",
        "connection_present": "true",
        "nm_active": "true",
        "route_present": "true",
        "dns_present": "true",
        "xfrm_state_inspection_ok": "true",
        "xfrm_state_present": "true",
        "xfrm_esp_present": "true",
        "xfrm_policy_inspection_ok": "true",
        "xfrm_policy_present": "true",
        "routing_loop_rule_present": "false",
        "counters_available": "true",
    }
    response.update(overrides)
    return response


def _active_tunnel_dns_run(argv):
    if "GENERAL.DEVICES" in argv:
        return CompletedProcess(args=argv, returncode=0, stdout="nm-xfrm-1\n", stderr="")
    if argv == ["resolvectl", "dns", "nm-xfrm-1"]:
        return CompletedProcess(
            args=argv,
            returncode=0,
            stdout="Link 9 (nm-xfrm-1): redacted\n",
            stderr="",
        )
    if argv == ["resolvectl", "domain", "nm-xfrm-1"]:
        return CompletedProcess(
            args=argv,
            returncode=0,
            stdout="Link 9 (nm-xfrm-1): ~.\n",
            stderr="",
        )
    raise AssertionError(argv)


def test_active_ikev2_requires_route_dns_xfrm_and_no_pref220_loop(monkeypatch):
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields, timeout=5.0: _active_ikev2_status(),
    )
    monkeypatch.setattr(verifier, "_run", _active_tunnel_dns_run)

    checks = {check.name: check for check in verifier.check_active_runtime("ikev2")}

    assert checks["runtime:ikev2:status"].ok
    assert checks["runtime:ikev2:route"].ok
    assert checks["runtime:ikev2:safety"].ok
    assert checks["runtime:ikev2:dns"].ok
    assert checks["runtime:ikev2:counters"].ok


@pytest.mark.parametrize(
    "override",
    (
        {"route_present": "false"},
        {"dns_present": "false"},
        {"connection_inspection_ok": "false"},
        {"connection_present": "false"},
        {"nm_active": "false"},
        {"xfrm_state_inspection_ok": "false"},
        {"xfrm_state_present": "false"},
        {"xfrm_policy_inspection_ok": "false"},
        {"xfrm_policy_present": "false"},
    ),
)
def test_active_ikev2_fails_closed_on_missing_route_dns_or_xfrm_evidence(
    monkeypatch, override
):
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields, timeout=5.0: _active_ikev2_status(**override),
    )
    monkeypatch.setattr(verifier, "_run", _active_tunnel_dns_run)

    checks = {check.name: check for check in verifier.check_active_runtime("ikev2")}

    assert not checks["runtime:ikev2:route"].ok


def test_active_ikev2_fails_closed_on_pref220_loop(monkeypatch):
    monkeypatch.setattr(
        verifier,
        "helper_request",
        lambda fields, timeout=5.0: _active_ikev2_status(
            status="disconnected",
            routing_loop_rule_present="true",
        ),
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
    build_calls = []
    open_calls = []

    class Opener:
        def open(self, url, *, timeout):
            open_calls.append((url, timeout))
            return next(responses)

    def fake_build_opener(*handlers):
        build_calls.append(handlers)
        return Opener()

    def fail_direct_urlopen(*args, **kwargs):
        raise AssertionError("external runtime evidence must bypass inherited proxies")

    monkeypatch.setattr(verifier.urllib.request, "build_opener", fake_build_opener)
    monkeypatch.setattr(verifier.urllib.request, "urlopen", fail_direct_urlopen)

    checks = verifier.check_external_data_plane(
        baseline,
        "https://exit.example.invalid/",
        "https://data.example.invalid/",
    )

    assert all(check.ok for check in checks)
    assert all("203.0.113" not in check.detail for check in checks)
    assert len(build_calls) == 1
    assert len(build_calls[0]) == 1
    assert isinstance(build_calls[0][0], verifier.urllib.request.ProxyHandler)
    assert build_calls[0][0].proxies == {}
    assert open_calls == [
        ("https://exit.example.invalid/", 10),
        ("https://data.example.invalid/", 10),
    ]
