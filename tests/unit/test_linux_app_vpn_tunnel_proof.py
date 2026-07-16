import argparse
import json
import signal
from pathlib import Path

import pytest

from scripts import linux_app_vpn_tunnel_proof as proof


TEST_API_BASE = "https://staging.example.test/api"


def _passing_network_gates(monkeypatch):
    monkeypatch.setattr(
        proof,
        "_data_plane_evidence",
        lambda deadline=None: {"ok": True, "selected_ip": "1.1.1.1", "attempts": []},
    )
    monkeypatch.setattr(
        proof,
        "_dns_evidence",
        lambda protocol, deadline=None: {
            "ok": True,
            "hostname": "example.com",
            "interface": f"test-{protocol}",
            "attempts": [],
        },
    )
    monkeypatch.setattr(
        proof,
        "_exit_ip_evidence",
        lambda pre_connect_exit_ip, deadline=None: {
            "ok": True,
            "pre_connect_observed": True,
            "connected_observed": True,
            "changed": True,
        },
    )
    monkeypatch.setattr(
        proof,
        "_ipv6_protection_evidence",
        lambda protocol, pre_connect_ipv6_exit_ip, deadline=None: {
            "ok": True,
            "mode": "block",
            "pre_connect_observed": True,
            "connected_observed": False,
        },
    )
    monkeypatch.setattr(
        proof,
        "_ikev2_routing_rule_evidence",
        lambda deadline=None: {"ok": True, "bad_rules": [], "ip_rules": {}},
    )


def test_wireguard_evidence_requires_sw_wg_route(monkeypatch):
    _passing_network_gates(monkeypatch)

    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "sw-wg"]:
            return proof.CommandResult(0, "10: sw-wg: <POINTOPOINT>\n", "")
        if argv == ["ip", "-4", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 dev sw-wg src 10.8.0.2\n", "")
        if argv == ["ip", "-6", "route", "get", "2606:4700:4700::1111"]:
            return proof.CommandResult(0, "2606:4700:4700::1111 dev sw-wg\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True}
    )
    monkeypatch.setattr(
        proof,
        "_wireguard_counter_evidence",
        lambda deadline=None: {
            "ok": True,
            "peer_rows": 1,
            "rx_bytes": 12,
            "tx_bytes": 34,
            "total_bytes": 46,
        },
    )
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": {
                "ok": "true",
                "contract": "13",
                "status": "connected",
                "interface": proof.WIREGUARD_INTERFACE,
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
            },
        },
    )

    assert (
        proof._evidence_for("wireguard", "https://api.example.test/api")["ok"] is True
    )


def test_openvpn_evidence_requires_tun_route_and_connected_helper_status(monkeypatch):
    _passing_network_gates(monkeypatch)
    helper_calls = []

    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "-o", "link", "show"]:
            return proof.CommandResult(
                0, f"11: {proof.OPENVPN_INTERFACE}: <POINTOPOINT>\n", ""
            )
        if argv == ["ip", "-4", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(
                0,
                f"1.1.1.1 dev {proof.OPENVPN_INTERFACE} src 10.9.0.2\n",
                "",
            )
        if argv == ["ip", "-6", "route", "get", "2606:4700:4700::1111"]:
            return proof.CommandResult(
                0,
                f"2606:4700:4700::1111 dev {proof.OPENVPN_INTERFACE}\n",
                "",
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: (
            helper_calls.append(fields)
            or {
                "ok": True,
                "response": {
                    "ok": "true",
                    "contract": "13",
                    "status": "connected",
                    "interface": proof.OPENVPN_INTERFACE,
                    "process_present": "true",
                    "initialization_complete": "true",
                    "interface_present": "true",
                    "route_present": "true",
                    "ipv4_route_present": "true",
                    "ipv6_route_present": "true",
                    "ipv6_block_configured": "true",
                    "ipv6_mode": "block",
                    "dns_configured": "true",
                    "counters_available": "true",
                    "rx_bytes": "12",
                    "tx_bytes": "34",
                },
            }
        ),
    )
    monkeypatch.setattr(
        proof,
        "_openvpn_log_evidence",
        lambda: {"ok": True, "interface": proof.OPENVPN_INTERFACE},
    )
    monkeypatch.setattr(
        proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True}
    )

    assert proof._evidence_for("openvpn", "https://api.example.test/api")["ok"] is True
    assert helper_calls == [
        {
            "op": "openvpn.status",
            "config_path": proof._state_path("securewave.ovpn"),
            "pid_path": proof._state_path("securewave-openvpn.pid"),
            "log_path": proof._state_path("securewave-openvpn.log"),
        }
    ]


def test_ikev2_evidence_requires_nm_vpn_route_dns_and_xfrm_state(monkeypatch):
    _passing_network_gates(monkeypatch)

    def fake_run(argv, *, timeout=15):
        if argv[:5] == ["nmcli", "-t", "-f", "NAME,TYPE", "connection"]:
            return proof.CommandResult(0, "SecureWave-IKEv2:vpn\n", "")
        if argv[:5] == [
            "nmcli",
            "-t",
            "-f",
            "IP4.DNS,IP6.DNS",
            "connection",
        ]:
            return proof.CommandResult(
                0,
                "IP4.DNS[1]:94.140.14.14\n",
                "",
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": _ikev2_status_response(),
        },
    )
    monkeypatch.setattr(
        proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True}
    )

    assert proof._evidence_for("ikev2", "https://api.example.test/api")["ok"] is True


def test_wireguard_cleanup_removes_securewave_link(monkeypatch):
    calls = []

    def fake_helper_request(fields):
        calls.append(fields)
        return {"ok": "true", "contract": "13", "status": "disconnected"}

    monkeypatch.setattr(proof, "_helper_request", fake_helper_request)

    actions = proof._cleanup_protocol_residue("wireguard")

    assert actions[0]["protocol"] == "wireguard"
    assert calls == [
        {"op": "wireguard.cleanup", "config_path": proof._state_path("sw-wg.conf")}
    ]
    assert actions[0]["ok"] is True


def test_openvpn_cleanup_is_safe_on_a_fresh_install(monkeypatch, tmp_path):
    monkeypatch.setattr(
        proof,
        "_state_path",
        lambda filename: str(tmp_path / filename),
    )
    monkeypatch.setattr(
        proof,
        "_helper_request",
        lambda fields: (_ for _ in ()).throw(AssertionError(fields)),
    )

    actions = proof._cleanup_protocol_residue("openvpn")

    assert actions == [
        {
            "protocol": "openvpn",
            "request": None,
            "response": {
                "ok": "true",
                "contract": "13",
                "status": "disconnected",
                "message": "No OpenVPN runtime config exists; cleanup is unnecessary.",
            },
            "ok": True,
            "skipped": True,
        }
    ]


def test_evidence_fails_when_route_uses_physical_interface(monkeypatch):
    _passing_network_gates(monkeypatch)

    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "sw-wg"]:
            return proof.CommandResult(0, "10: sw-wg: <POINTOPOINT>\n", "")
        if argv == ["ip", "-4", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 via 192.168.64.1 dev enp0s1\n", "")
        if argv == ["ip", "-6", "route", "get", "2606:4700:4700::1111"]:
            return proof.CommandResult(0, "2606:4700:4700::1111 dev enp0s1\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True}
    )
    monkeypatch.setattr(
        proof,
        "_wireguard_counter_evidence",
        lambda deadline=None: {
            "ok": True,
            "peer_rows": 1,
            "rx_bytes": 12,
            "tx_bytes": 34,
            "total_bytes": 46,
        },
    )

    assert (
        proof._evidence_for("wireguard", "https://api.example.test/api")["ok"] is False
    )


def test_hold_evidence_passes_with_data_dns_exit_ip_and_ikev2_rule(monkeypatch):
    calls = []

    def fake_run(argv, *, timeout=15):
        calls.append(list(argv))
        if argv[:6] == ["curl", "-4", "--noproxy", "*", "-m", "5"]:
            return proof.CommandResult(0, "200\n", "")
        if argv[:7] == [
            "curl",
            "-4",
            "--noproxy",
            "*",
            "-m",
            "8",
            "-fsS",
        ]:
            return proof.CommandResult(0, "138.199.204.139\n", "")
        if argv[:7] == [
            "curl",
            "-6",
            "--noproxy",
            "*",
            "-m",
            "8",
            "-fsS",
        ]:
            return proof.CommandResult(6, "", "IPv6 egress blocked")
        if argv in (
            ["ip", "-4", "-N", "rule", "show"],
            ["ip", "-6", "-N", "rule", "show"],
        ):
            return proof.CommandResult(
                0, "210: not from all fwmark 0xdc lookup 210\n", ""
            )
        if argv[:5] == ["nmcli", "-t", "-f", "NAME,TYPE", "connection"]:
            return proof.CommandResult(0, "SecureWave-IKEv2:vpn\n", "")
        if argv[:5] == [
            "nmcli",
            "-t",
            "-f",
            "IP4.DNS,IP6.DNS",
            "connection",
        ]:
            return proof.CommandResult(
                0, "IP4.DNS[1]:1.1.1.1\n", ""
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_dns_evidence",
        lambda protocol, deadline=None: (
            calls.append(["dns", protocol])
            or {
                "ok": True,
                "hostname": "example.com",
                "interface": proof.IKEV2_INTERFACE,
                "attempts": [],
            }
        ),
    )
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": _ikev2_status_response(),
        },
    )
    monkeypatch.setattr(
        proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True}
    )

    evidence = proof._evidence_for(
        "ikev2",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
        pre_connect_ipv6_exit_ip={
            "ok": True,
            "ip": "2001:db8::10",
            "attempts": [],
        },
    )

    assert evidence["ok"] is True
    assert evidence["data_plane"]["selected_ip"] == "1.1.1.1"
    assert evidence["dns"]["hostname"] == "example.com"
    assert evidence["exit_ip"] == {
        "ok": True,
        "pre_connect_observed": True,
        "connected_observed": True,
        "changed": True,
    }
    assert "92.105.134.148" not in json.dumps(evidence)
    assert "138.199.204.139" not in json.dumps(evidence)
    assert evidence["ikev2_routing_rule"]["ok"] is True

    data_plane_index = next(
        i
        for i, call in enumerate(calls)
        if call[:6] == ["curl", "-4", "--noproxy", "*", "-m", "5"]
    )
    dns_index = next(i for i, call in enumerate(calls) if call == ["dns", "ikev2"])
    exit_ip_index = next(
        i
        for i, call in enumerate(calls)
        if call[:7]
        == ["curl", "-4", "--noproxy", "*", "-m", "8", "-fsS"]
    )
    rule_index = next(
        i
        for i, call in enumerate(calls)
        if call == ["ip", "-4", "-N", "rule", "show"]
    )
    assert data_plane_index < dns_index < exit_ip_index < rule_index


def test_hold_evidence_fails_when_data_plane_is_dead(monkeypatch):
    calls = []

    def fake_run(argv, *, timeout=15):
        calls.append(list(argv))
        if argv[:6] == ["curl", "-4", "--noproxy", "*", "-m", "5"]:
            return proof.CommandResult(28, "000\n", "Connection timed out")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._evidence_for(
        "wireguard",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
    )

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "data_plane_unreachable"
    assert len(evidence["data_plane"]["attempts"]) == 2
    assert all(call[:1] != ["dig"] for call in calls)


def test_hold_evidence_fails_when_dns_only_is_broken(monkeypatch):
    calls = []

    def fake_run(argv, *, timeout=15):
        calls.append(list(argv))
        if argv[:6] == ["curl", "-4", "--noproxy", "*", "-m", "5"]:
            return proof.CommandResult(0, "200\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_dns_evidence",
        lambda protocol, deadline=None: {
            "ok": False,
            "error_kind": "dns_broken_or_outside_tunnel",
            "interface": proof.OPENVPN_INTERFACE,
            "attempts": [{"ok": False}, {"ok": False}],
        },
    )

    evidence = proof._evidence_for(
        "openvpn",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
    )

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "dns_broken_in_tunnel"
    assert len(evidence["dns"]["attempts"]) == 2
    assert all(
        call[:7]
        != ["curl", "-4", "--noproxy", "*", "-m", "8", "-fsS"]
        for call in calls
    )


def test_dns_evidence_uses_exact_tunnel_link_and_positive_counter_deltas(
    monkeypatch,
):
    interface = proof.IKEV2_INTERFACE
    calls = []

    def fake_run(argv, *, timeout=15):
        calls.append(list(argv))
        if argv == ["resolvectl", "dns", interface]:
            return proof.CommandResult(0, f"Link 12 ({interface}): 94.140.14.14\n", "")
        if argv == ["resolvectl", "domain", interface]:
            return proof.CommandResult(0, f"Link 12 ({interface}): ~.\n", "")
        if argv[:2] == ["resolvectl", f"--interface={interface}"]:
            return proof.CommandResult(
                0,
                f"example.com IN A 93.184.216.34\n-- link: {interface}\n",
                "",
            )
        raise AssertionError(argv)

    snapshots = iter(
        (
            {"ok": True, "rx_bytes": 100, "tx_bytes": 200},
            {"ok": True, "rx_bytes": 101, "tx_bytes": 201},
            {"ok": True, "rx_bytes": 102, "tx_bytes": 202},
            {"ok": True, "rx_bytes": 103, "tx_bytes": 203},
        )
    )
    counter_protocols = []

    def fake_counter_snapshot(protocol, *, deadline=None):
        counter_protocols.append(protocol)
        return next(snapshots)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": _ikev2_status_response(),
        },
    )
    monkeypatch.setattr(proof, "_helper_counter_snapshot", fake_counter_snapshot)

    evidence = proof._dns_evidence("ikev2")

    assert evidence["ok"] is True
    assert evidence["interface"] == interface
    assert evidence["resolver_config"]["server_count"] == 1
    assert evidence["resolver_config"]["route_all_domains"] is True
    assert evidence["attempts"][0]["owned_response"] is True
    assert evidence["attempts"][0]["rx_delta"] == 1
    assert evidence["attempts"][0]["tx_delta"] == 1
    assert counter_protocols == ["ikev2", "ikev2", "ikev2", "ikev2"]
    assert [
        "resolvectl",
        f"--interface={interface}",
        "--cache=no",
        "--network=yes",
        "--legend=no",
        "--type=A",
        "query",
        proof.DNS_TEST_HOSTS[0],
    ] in calls


@pytest.mark.parametrize(
    ("dns_output", "domain_output"),
    (
        (
            f"Link 7 ({proof.OPENVPN_INTERFACE}):\n",
            f"Link 7 ({proof.OPENVPN_INTERFACE}): ~.\n",
        ),
        (
            f"Link 7 ({proof.OPENVPN_INTERFACE}): 1.1.1.1\n",
            f"Link 7 ({proof.OPENVPN_INTERFACE}): corp.example\n",
        ),
    ),
)
def test_dns_evidence_requires_server_and_route_all_domain(
    monkeypatch, dns_output, domain_output
):
    monkeypatch.setattr(
        proof,
        "_dns_interface_evidence",
        lambda protocol, deadline=None: {
            "ok": True,
            "interface": proof.OPENVPN_INTERFACE,
        },
    )

    def fake_run(argv, *, timeout=15):
        if argv == ["resolvectl", "dns", proof.OPENVPN_INTERFACE]:
            return proof.CommandResult(0, dns_output, "")
        if argv == ["resolvectl", "domain", proof.OPENVPN_INTERFACE]:
            return proof.CommandResult(0, domain_output, "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._dns_evidence("openvpn")

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "dns_resolver_not_owned_by_tunnel"
    assert evidence["resolver_config"]["ok"] is False


def test_dns_evidence_rejects_successful_query_reported_on_another_link(monkeypatch):
    interface = proof.OPENVPN_INTERFACE
    monkeypatch.setattr(
        proof,
        "_dns_interface_evidence",
        lambda protocol, deadline=None: {"ok": True, "interface": interface},
    )
    snapshot_values = iter(
        value
        for index in range(len(proof.DNS_TEST_HOSTS))
        for value in (
            {"ok": True, "rx_bytes": index * 10, "tx_bytes": index * 10},
            {"ok": True, "rx_bytes": index * 10 + 1, "tx_bytes": index * 10 + 1},
        )
    )
    monkeypatch.setattr(
        proof,
        "_helper_counter_snapshot",
        lambda protocol, deadline=None: next(snapshot_values),
    )

    def fake_run(argv, *, timeout=15):
        if argv == ["resolvectl", "dns", interface]:
            return proof.CommandResult(0, f"Link 7 ({interface}): 1.1.1.1\n", "")
        if argv == ["resolvectl", "domain", interface]:
            return proof.CommandResult(0, f"Link 7 ({interface}): ~.\n", "")
        if argv[:2] == ["resolvectl", f"--interface={interface}"]:
            return proof.CommandResult(0, "example.com IN A 93.184.216.34\n-- link: enp0s1\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._dns_evidence("openvpn")

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "dns_broken_or_outside_tunnel"
    assert len(evidence["attempts"]) == len(proof.DNS_TEST_HOSTS)
    assert all(attempt["owned_response"] is False for attempt in evidence["attempts"])


def test_dns_evidence_requires_positive_rx_and_tx_counter_deltas(monkeypatch):
    interface = "sw-wg"
    monkeypatch.setattr(
        proof,
        "_helper_counter_snapshot",
        lambda protocol, deadline=None: {
            "ok": True,
            "rx_bytes": 100,
            "tx_bytes": 200,
        },
    )

    def fake_run(argv, *, timeout=15):
        if argv == ["resolvectl", "dns", interface]:
            return proof.CommandResult(0, f"Link 7 ({interface}): 1.1.1.1\n", "")
        if argv == ["resolvectl", "domain", interface]:
            return proof.CommandResult(0, f"Link 7 ({interface}): ~.\n", "")
        if argv[:2] == ["resolvectl", f"--interface={interface}"]:
            return proof.CommandResult(
                0,
                f"example.com IN A 93.184.216.34\n-- link: {interface}\n",
                "",
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._dns_evidence("wireguard")

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "dns_broken_or_outside_tunnel"
    assert all(attempt["rx_delta"] == 0 for attempt in evidence["attempts"])
    assert all(attempt["tx_delta"] == 0 for attempt in evidence["attempts"])


def test_hold_evidence_fails_when_exit_ip_is_unchanged(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:6] == ["curl", "-4", "--noproxy", "*", "-m", "5"]:
            return proof.CommandResult(0, "200\n", "")
        if argv[:7] == [
            "curl",
            "-4",
            "--noproxy",
            "*",
            "-m",
            "8",
            "-fsS",
        ]:
            return proof.CommandResult(0, "92.105.134.148\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_dns_evidence",
        lambda protocol, deadline=None: {
            "ok": True,
            "interface": "sw-wg",
            "attempts": [],
        },
    )
    monkeypatch.setattr(
        proof,
        "_ipv6_protection_evidence",
        lambda protocol, pre_connect_ipv6_exit_ip, deadline=None: {
            "ok": True,
            "mode": "block",
            "pre_connect_observed": True,
            "connected_observed": False,
        },
    )

    evidence = proof._evidence_for(
        "wireguard",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
    )

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "exit_ip_unchanged"
    assert evidence["exit_ip"]["pre_connect_observed"] is True
    assert evidence["exit_ip"]["connected_observed"] is True
    assert evidence["exit_ip"]["changed"] is False
    serialized = json.dumps(evidence["exit_ip"])
    assert "92.105.134.148" not in serialized
    assert '"stdout"' not in serialized


def test_hold_evidence_fails_on_bad_ikev2_charon_nm_rule(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:6] == ["curl", "-4", "--noproxy", "*", "-m", "5"]:
            return proof.CommandResult(0, "200\n", "")
        if argv[:7] == [
            "curl",
            "-4",
            "--noproxy",
            "*",
            "-m",
            "8",
            "-fsS",
        ]:
            return proof.CommandResult(0, "138.199.204.139\n", "")
        if argv == ["ip", "-4", "-N", "rule", "show"]:
            return proof.CommandResult(0, "210: from all lookup 210\n", "")
        if argv == ["ip", "-6", "-N", "rule", "show"]:
            return proof.CommandResult(
                0, "210: not from all fwmark 0xdc lookup 210\n", ""
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_dns_evidence",
        lambda protocol, deadline=None: {
            "ok": True,
            "interface": proof.IKEV2_INTERFACE,
            "attempts": [],
        },
    )

    monkeypatch.setattr(
        proof,
        "_ipv6_protection_evidence",
        lambda protocol, pre_connect_ipv6_exit_ip, deadline=None: {
            "ok": True,
            "mode": "block",
            "pre_connect_observed": True,
            "connected_observed": False,
        },
    )

    evidence = proof._evidence_for(
        "ikev2",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
    )

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "ikev2_routing_loop_rule"
    assert evidence["ikev2_routing_rule"]["bad_rules"] == [
        "ipv4: 210: from all lookup 210"
    ]


def test_placeholder_credentials_are_detected():
    assert proof._is_placeholder("real@email.com") is True
    assert proof._is_placeholder("existing-live-password") is True
    assert proof._is_placeholder("your@email.com") is True
    assert proof._is_placeholder("your-password") is True
    assert proof._is_placeholder("your-real-test-account@example.com") is True
    assert proof._is_placeholder("your-real-test-password") is True
    assert proof._is_placeholder("qa@example.com") is False


def test_env_default_accepts_test_account_aliases(monkeypatch):
    monkeypatch.delenv("SECUREWAVE_RUNTIME_PROBE_EMAIL", raising=False)
    monkeypatch.setenv("SECUREWAVE_TEST_EMAIL", "qa@example.com")

    assert (
        proof._env_default(
            "SECUREWAVE_TEST_EMAIL",
            "SECUREWAVE_RUNTIME_PROBE_EMAIL",
        )
        == "qa@example.com"
    )


def test_env_default_prefers_demo_account_alias(monkeypatch):
    monkeypatch.setenv("DEMO_EMAIL", "demo@example.com")
    monkeypatch.setenv("SECUREWAVE_TEST_EMAIL", "qa@example.com")

    assert (
        proof._env_default(
            "DEMO_EMAIL",
            "SECUREWAVE_TEST_EMAIL",
            "SECUREWAVE_RUNTIME_PROBE_EMAIL",
        )
        == "demo@example.com"
    )


def test_credential_file_supplies_stable_account_aliases(tmp_path):
    auth_file = tmp_path / "live.env"
    auth_file.write_text(
        """
        # Stable certification account.
        export DEMO_EMAIL="demo@example.com"
        DEMO_PASSWORD='SwRuntimeSecret!A1'
        IGNORED_KEY=ignored
        """,
        encoding="utf-8",
    )

    values = proof._parse_env_file(auth_file)

    assert (
        proof._file_default(
            values,
            "DEMO_EMAIL",
            "SECUREWAVE_TEST_EMAIL",
        )
        == "demo@example.com"
    )
    assert (
        proof._file_default(
            values,
            "DEMO_PASSWORD",
            "SECUREWAVE_TEST_PASSWORD",
        )
        == "SwRuntimeSecret!A1"
    )
    assert "IGNORED_KEY" not in values


def test_redact_email_keeps_domain_only():
    assert proof._redact_email("demo@example.com") == "d***@example.com"
    assert proof._redact_email("not-an-email") == "configured"


def test_default_api_base_requires_explicit_environment_value(monkeypatch):
    monkeypatch.delenv("SECUREWAVE_API_BASE_URL", raising=False)

    assert proof._default_api_base() is None


def test_default_api_base_accepts_explicit_staging_and_loopback_only(monkeypatch):
    monkeypatch.delenv("SECUREWAVE_ALLOW_PRODUCTION_PROOF", raising=False)
    monkeypatch.setenv("SECUREWAVE_API_BASE_URL", TEST_API_BASE)

    assert proof._default_api_base() == TEST_API_BASE
    assert proof._canonical_api_base(
        "http://127.0.0.1:9443/api"
    ) == "http://127.0.0.1:9443/api"
    with pytest.raises(argparse.ArgumentTypeError, match="production API"):
        proof._canonical_api_base("https://api.securewaveapp.com/api")


def test_production_api_base_requires_explicit_live_proof_authorization(monkeypatch):
    monkeypatch.setenv("SECUREWAVE_ALLOW_PRODUCTION_PROOF", "true")

    assert proof._canonical_api_base(
        "https://api.securewaveapp.com/api/"
    ) == "https://api.securewaveapp.com/api"


def test_backend_health_probe_disables_inherited_proxies(monkeypatch):
    opened = []

    class FakeResponse:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, traceback):
            return False

        def read(self, size=-1):
            return b'{"status":"healthy"}'

        def getcode(self):
            return self.status

    class FakeOpener:
        def open(self, request, timeout):
            opened.append((request.full_url, timeout))
            return FakeResponse()

    def fake_build_opener(handler):
        assert isinstance(handler, proof.urllib.request.ProxyHandler)
        assert handler.proxies == {}
        return FakeOpener()

    monkeypatch.setattr(proof.urllib.request, "build_opener", fake_build_opener)
    monkeypatch.setattr(
        proof.urllib.request,
        "urlopen",
        lambda *args, **kwargs: pytest.fail("direct urlopen must not be used"),
    )

    evidence = proof._backend_health_evidence(TEST_API_BASE, timeout=3)

    assert evidence["ok"] is True
    assert opened == [(f"{TEST_API_BASE}/health", 3)]


def test_release_probe_command_executes_prebuilt_binary_without_flutter_args():
    probe_binary = Path("/tmp/release/bundle/securewave_app")
    command = proof._build_probe_command(probe_binary)

    assert command == [str(probe_binary)]
    assert all("flutter" not in argument for argument in command)
    assert all("dart-define" not in argument for argument in command)


def test_build_environment_strips_all_probe_credentials(monkeypatch):
    for name in (
        "DEMO_EMAIL",
        "DEMO_PASSWORD",
        "SECUREWAVE_TEST_EMAIL",
        "SECUREWAVE_TEST_PASSWORD",
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
        "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
        "SECUREWAVE_CERT_AUTH_FILE",
        "SECUREWAVE_LIVE_ACCOUNT_FILE",
    ):
        monkeypatch.setenv(name, f"secret-{name}")
    monkeypatch.setenv("PATH", "/usr/bin")

    environment = proof._sanitized_build_environment()

    assert environment["PATH"] == "/usr/bin"
    assert all(name not in environment for name in proof.BUILD_ENVIRONMENT_BLOCKLIST)


def test_probe_values_are_passed_in_minimal_runtime_environment(monkeypatch):
    monkeypatch.setenv("PARENT_MARKER", "must-not-leak")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "must-not-leak")
    environment = proof._build_probe_environment(
        protocol="wireguard",
        email="qa@example.com",
        password="runtime-secret",
        auth_mode="login",
        server_id="server-1",
        hold_seconds=12,
        api_base=TEST_API_BASE,
        use_mock_api="false",
    )

    assert "PARENT_MARKER" not in environment
    assert "AWS_SECRET_ACCESS_KEY" not in environment
    assert environment["SECUREWAVE_RUNTIME_PROBE_EMAIL"] == "qa@example.com"
    assert environment["SECUREWAVE_RUNTIME_PROBE_PASSWORD"] == "runtime-secret"
    assert environment["SECUREWAVE_RUNTIME_PROBE_PROTOCOL"] == "wireguard"
    assert environment["SECUREWAVE_RUNTIME_PROBE_SERVER_ID"] == "server-1"
    assert environment["SECUREWAVE_API_BASE_URL"] == TEST_API_BASE
    assert "runtime-secret" not in " ".join(
        proof._build_probe_command(Path("/tmp/securewave_app"))
    )


def test_release_probe_build_uses_fixed_release_target(monkeypatch, tmp_path):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((list(argv), kwargs))
        return proof.subprocess.CompletedProcess(argv, 0, "", "")

    monkeypatch.setattr(proof.subprocess, "run", fake_run)

    app_root = tmp_path / "isolated" / "securewave_app"
    result = proof._build_release_probe(app_root)

    assert result.returncode == 0
    assert calls[0][0] == [
        "flutter",
        "build",
        "linux",
        "--release",
        "-t",
        proof.PROBE_TARGET,
    ]
    build_environment = calls[0][1]["env"]
    assert all(
        name not in build_environment for name in proof.BUILD_ENVIRONMENT_BLOCKLIST
    )
    assert calls[0][1]["cwd"] == app_root


def test_probe_workspace_copies_sources_without_touching_canonical_build(
    monkeypatch, tmp_path
):
    app_root = tmp_path / "canonical_app"
    (app_root / "lib").mkdir(parents=True)
    (app_root / "lib/main.dart").write_text("production", encoding="utf-8")
    (app_root / "build").mkdir()
    (app_root / "build/sentinel").write_text("do-not-copy", encoding="utf-8")
    ephemeral = app_root / "linux/flutter/ephemeral"
    ephemeral.mkdir(parents=True)
    (ephemeral / "sentinel").write_text("do-not-copy", encoding="utf-8")
    windows_ephemeral = app_root / "windows/flutter/ephemeral"
    windows_ephemeral.mkdir(parents=True)
    (windows_ephemeral / "sentinel").write_text("do-not-copy", encoding="utf-8")
    monkeypatch.setattr(proof, "APP_ROOT", app_root)

    isolated_app_root = proof._prepare_probe_workspace()
    try:
        assert isolated_app_root != app_root
        assert (isolated_app_root / "lib/main.dart").read_text(encoding="utf-8") == (
            "production"
        )
        assert not (isolated_app_root / "build").exists()
        assert not (isolated_app_root / "linux/flutter/ephemeral").exists()
        assert not (isolated_app_root / "windows/flutter/ephemeral").exists()
        assert (app_root / "build/sentinel").read_text(encoding="utf-8") == (
            "do-not-copy"
        )
    finally:
        cleanup = proof._remove_probe_workspace(isolated_app_root)
    assert cleanup == {"ok": True, "removed": True}


def test_failed_release_build_evidence_keeps_exact_command_and_full_output():
    stdout = "\n".join(f"stdout-{index}" for index in range(100))
    stderr = "\n".join(f"stderr-{index}" for index in range(100))

    evidence = proof._build_result_evidence(proof.CommandResult(1, stdout, stderr))

    assert evidence["command"] == proof._release_probe_build_command()
    assert evidence["returncode"] == 1
    assert evidence["stdout"] == stdout
    assert evidence["stderr"] == stderr
    assert "stdout_tail" not in evidence


def test_missing_probe_credentials_fail_before_runtime_registration():
    error = proof._credential_error(None, "secret")

    assert error is not None
    assert "existing live account credentials are required" in error
    assert "DEMO_EMAIL/DEMO_PASSWORD" in error


def test_placeholder_probe_credentials_fail_before_runtime_registration():
    error = proof._credential_error("real@email.com", "real-password")

    assert error is not None
    assert "placeholder live account credentials" in error


def test_real_probe_credentials_are_accepted():
    assert proof._credential_error("qa@example.com", "SwRuntimeSecret!A1") is None


def test_auth_failure_detection_stops_repeated_registration_attempts():
    result = {
        "probe_events": [
            {
                "event": "runtime_probe_error",
                "error": "DioException bad response: status code of 429",
                "stack": "#1 ApiClient.register",
            }
        ]
    }

    assert proof._has_auth_failure(result) is True


def test_non_auth_runtime_error_is_not_auth_failure():
    result = {
        "probe_events": [
            {
                "event": "runtime_probe_error",
                "error": "OpenVPN process started but no tunnel route was detected.",
                "stack": "#1 ChannelVpnService.connect",
            }
        ]
    }

    assert proof._has_auth_failure(result) is False


def test_probe_runtime_error_becomes_terminal_evidence():
    event = {
        "event": "runtime_probe_error",
        "error": "OpenVPN process started but no tunnel route was detected.",
    }

    evidence = proof._probe_error_evidence(event)

    assert evidence["ok"] is False
    assert (
        evidence["error"] == "OpenVPN process started but no tunnel route was detected."
    )
    assert evidence["event"] == event


def test_json_object_parses_dict_only():
    assert proof._json_object('{"ok": false}') == {"ok": False}
    assert proof._json_object("[1, 2, 3]") is None
    assert proof._json_object("not json") is None


def test_verifier_success_requires_zero_exit_and_explicit_json_true():
    result = proof.CommandResult(0, '{"ok": true, "checks": []}', "")

    assert proof._verifier_succeeded(result) is True


@pytest.mark.parametrize(
    "result",
    (
        proof.CommandResult(1, '{"ok": true}', "verifier failed"),
        proof.CommandResult(0, '{"ok": false}', ""),
        proof.CommandResult(0, '{"ok": null}', ""),
        proof.CommandResult(0, '{"ok": 1}', ""),
        proof.CommandResult(0, "not json", ""),
        proof.CommandResult(0, "[true]", ""),
        proof.CommandResult(0, "", ""),
    ),
)
def test_verifier_success_rejects_nonzero_malformed_or_contradictory_results(result):
    assert proof._verifier_succeeded(result) is False


def test_helper_responses_fail_closed_below_contract_13():
    assert proof._helper_response_ok({"ok": "true", "contract": "13"}) is True
    assert proof._helper_response_ok({"ok": "true", "contract": "12"}) is False
    assert proof._helper_response_ok({"ok": "true"}) is False
    assert proof._helper_response_ok({"ok": "true", "contract": "invalid"}) is False
    assert proof._helper_response_ok({"ok": "false", "contract": "13"}) is False


def test_exit_ip_evidence_exposes_only_observation_and_change(monkeypatch):
    pre_connect = {
        "ok": True,
        "ip": "192.0.2.10",
        "attempts": [
            {
                "result": {
                    "returncode": 0,
                    "stdout": "192.0.2.10\n",
                    "stderr": "",
                }
            }
        ],
    }
    monkeypatch.setattr(
        proof,
        "_exit_ip_lookup",
        lambda deadline=None: {
            "ok": True,
            "ip": "198.51.100.20",
            "attempts": [
                {
                    "result": {
                        "returncode": 0,
                        "stdout": "198.51.100.20\n",
                        "stderr": "",
                    }
                }
            ],
        },
    )

    evidence = proof._exit_ip_evidence(pre_connect)

    assert evidence["ok"] is True
    assert evidence["pre_connect_observed"] is True
    assert evidence["connected_observed"] is True
    assert evidence["changed"] is True
    serialized = json.dumps(evidence)
    assert "192.0.2.10" not in serialized
    assert "198.51.100.20" not in serialized
    assert '"stdout"' not in serialized


def test_wireguard_counters_require_positive_parsed_transfer_rows(monkeypatch):
    public_key = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG="
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": {
                "ok": "true",
                "contract": "13",
                "code": "ok",
                "stdout": f"{public_key}\t12\t34\n",
            },
        },
    )

    counters = proof._wireguard_counter_evidence()

    assert counters == {
        "ok": True,
        "available": True,
        "peer_rows": 1,
        "rx_bytes": 12,
        "tx_bytes": 34,
        "total_bytes": 46,
        "helper": {"contract": "13", "code": "ok"},
    }
    serialized = json.dumps(counters)
    assert public_key not in serialized
    assert "stdout" not in serialized


@pytest.mark.parametrize(
    ("stdout", "rx_bytes", "tx_bytes"),
    (
        ("peer-key\t0\t34\n", 0, 34),
        ("peer-key\t12\t0\n", 12, 0),
    ),
)
def test_wireguard_counters_reject_one_direction_only_transfers(
    monkeypatch, stdout, rx_bytes, tx_bytes
):
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": {"ok": "true", "contract": "13", "stdout": stdout},
        },
    )

    counters = proof._wireguard_counter_evidence()

    assert counters["ok"] is False
    assert counters["rx_bytes"] == rx_bytes
    assert counters["tx_bytes"] == tx_bytes
    assert counters["total_bytes"] == rx_bytes + tx_bytes


@pytest.mark.parametrize(
    "stdout",
    (
        "peer-key\t0\t0\n",
        "peer-key\tnot-a-number\t12\n",
        "peer-key\t12\n",
        "",
    ),
)
def test_wireguard_counters_fail_closed_on_zero_or_malformed_rows(monkeypatch, stdout):
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": {"ok": "true", "contract": "13", "stdout": stdout},
        },
    )

    counters = proof._wireguard_counter_evidence()

    assert counters["ok"] is False
    assert "stdout" not in json.dumps(counters)


@pytest.mark.parametrize(
    ("field", "value"),
    (("status", "disconnected"), ("dns_configured", "false")),
)
def test_openvpn_evidence_fails_on_disconnected_or_unconfigured_dns(
    monkeypatch, field, value
):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "-o", "link", "show"]:
            return proof.CommandResult(
                0, f"11: {proof.OPENVPN_INTERFACE}: <POINTOPOINT>\n", ""
            )
        if argv == ["ip", "-4", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(
                0,
                f"1.1.1.1 dev {proof.OPENVPN_INTERFACE} src 10.9.0.2\n",
                "",
            )
        if argv == ["ip", "-6", "route", "get", "2606:4700:4700::1111"]:
            return proof.CommandResult(
                0,
                f"2606:4700:4700::1111 dev {proof.OPENVPN_INTERFACE}\n",
                "",
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    helper_response = {
        "ok": "true",
        "contract": "13",
        "status": "connected",
        "interface": proof.OPENVPN_INTERFACE,
        "process_present": "true",
        "initialization_complete": "true",
        "interface_present": "true",
        "route_present": "true",
        "ipv4_route_present": "true",
        "ipv6_route_present": "true",
        "ipv6_block_configured": "true",
        "ipv6_mode": "block",
        "dns_configured": "true",
        "counters_available": "true",
        "rx_bytes": "12",
        "tx_bytes": "34",
    }
    helper_response[field] = value
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {"ok": True, "response": helper_response},
    )
    monkeypatch.setattr(
        proof,
        "_openvpn_log_evidence",
        lambda: {"ok": True, "interface": proof.OPENVPN_INTERFACE},
    )
    monkeypatch.setattr(
        proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True}
    )

    evidence = proof._runtime_evidence_for("openvpn", "https://api.example.test/api")

    assert evidence["ok"] is False


@pytest.mark.parametrize(
    ("route_interface", "log_interface", "helper_interface"),
    (
        ("tun-other", proof.OPENVPN_INTERFACE, proof.OPENVPN_INTERFACE),
        (proof.OPENVPN_INTERFACE, "tun-other", proof.OPENVPN_INTERFACE),
        (proof.OPENVPN_INTERFACE, proof.OPENVPN_INTERFACE, "tun-other"),
    ),
)
def test_openvpn_evidence_requires_one_exact_interface_across_all_sources(
    monkeypatch, route_interface, log_interface, helper_interface
):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "-o", "link", "show"]:
            return proof.CommandResult(
                0, f"11: {proof.OPENVPN_INTERFACE}: <POINTOPOINT>\n", ""
            )
        if argv == ["ip", "-4", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(
                0, f"1.1.1.1 dev {route_interface} src 10.9.0.2\n", ""
            )
        if argv == ["ip", "-6", "route", "get", "2606:4700:4700::1111"]:
            return proof.CommandResult(
                0,
                f"2606:4700:4700::1111 dev {route_interface}\n",
                "",
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": {
                "ok": "true",
                "contract": "13",
                "status": "connected",
                "interface": helper_interface,
                "process_present": "true",
                "initialization_complete": "true",
                "interface_present": "true",
                "route_present": "true",
                "ipv4_route_present": "true",
                "ipv6_route_present": "true",
                "ipv6_block_configured": "true",
                "ipv6_mode": "block",
                "dns_configured": "true",
                "counters_available": "true",
                "rx_bytes": "12",
                "tx_bytes": "34",
            },
        },
    )
    monkeypatch.setattr(
        proof,
        "_openvpn_log_evidence",
        lambda: {"ok": True, "interface": log_interface},
    )
    monkeypatch.setattr(
        proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True}
    )

    evidence = proof._runtime_evidence_for("openvpn", "https://api.example.test/api")

    assert evidence["ok"] is False


def _ikev2_status_response(**overrides):
    response = {
        "ok": "true",
        "contract": "13",
        "status": "connected",
        "connection_inspection_ok": "true",
        "connection_present": "true",
        "nm_active": "true",
        "interface_name_configured": "true",
        "interface_inspection_ok": "true",
        "interface_present": "true",
        "interface": proof.IKEV2_INTERFACE,
        "xfrm_interface": "true",
        "xfrm_if_id_present": "true",
        "xfrm_if_id_persisted": "true",
        "ownership_inspection_ok": "true",
        "route_inspection_ok": "true",
        "route_present": "true",
        "ipv4_full_route_present": "true",
        "ipv6_full_route_present": "true",
        "ipv6_mode": "block",
        "ipv6_block_inspection_ok": "true",
        "ipv6_block_present": "true",
        "route_conflict_present": "false",
        "dns_present": "true",
        "xfrm_state_inspection_ok": "true",
        "xfrm_state_present": "true",
        "xfrm_esp_present": "true",
        "xfrm_policy_inspection_ok": "true",
        "xfrm_policy_present": "true",
        "xfrm_pair_present": "true",
        "endpoint_bypass_inspection_ok": "true",
        "endpoint_bypass_present": "true",
        "routing_rule_inspection_ok": "true",
        "routing_rules_safe": "true",
        "routing_loop_rule_present": "false",
        "legacy_routing_loop_rule_present": "false",
        "counters_available": "true",
        "rx_bytes": "12",
        "tx_bytes": "34",
    }
    response.update(overrides)
    return response


def _mock_ikev2_runtime(monkeypatch, *, dns_output, helper_response):
    def fake_run(argv, *, timeout=15):
        if argv[:5] == ["nmcli", "-t", "-f", "NAME,TYPE", "connection"]:
            return proof.CommandResult(0, "SecureWave-IKEv2:vpn\n", "")
        if argv[:5] == [
            "nmcli",
            "-t",
            "-f",
            "IP4.DNS,IP6.DNS",
            "connection",
        ]:
            return proof.CommandResult(0, dns_output, "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {"ok": True, "response": helper_response},
    )
    monkeypatch.setattr(
        proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True}
    )


@pytest.mark.parametrize(
    "override",
    (
        {"status": "disconnected"},
        {"connection_inspection_ok": "false"},
        {"connection_present": "false"},
        {"nm_active": "false"},
        {"interface_name_configured": "false"},
        {"interface_inspection_ok": "false"},
        {"interface_present": "false"},
        {"interface": "enp0s1"},
        {"xfrm_interface": "false"},
        {"xfrm_if_id_present": "false"},
        {"xfrm_if_id_persisted": "false"},
        {"ownership_inspection_ok": "false"},
        {"route_inspection_ok": "false"},
        {"route_present": "false"},
        {"ipv4_full_route_present": "false"},
        {"route_conflict_present": "true"},
        {"dns_present": "false"},
        {"xfrm_state_inspection_ok": "false"},
        {"xfrm_state_present": "false"},
        {"xfrm_esp_present": "false"},
        {"xfrm_policy_inspection_ok": "false"},
        {"xfrm_policy_present": "false"},
        {"xfrm_pair_present": "false"},
        {"endpoint_bypass_inspection_ok": "false"},
        {"endpoint_bypass_present": "false"},
        {"routing_loop_rule_present": "true"},
        {"legacy_routing_loop_rule_present": "true"},
        {"counters_available": "false"},
        {"rx_bytes": "0", "tx_bytes": "0"},
    ),
)
def test_ikev2_runtime_fails_closed_on_incomplete_helper_evidence(
    monkeypatch, override
):
    _mock_ikev2_runtime(
        monkeypatch,
        dns_output="IP4.DNS[1]:1.1.1.1\n",
        helper_response=_ikev2_status_response(**override),
    )

    evidence = proof._runtime_evidence_for("ikev2", "https://api.example.test/api")

    assert evidence["ok"] is False


@pytest.mark.parametrize(
    ("dns_output", "helper_override"),
    (
        ("", {}),
        ("IP4.DNS[1]:1.1.1.1\n", {"route_present": "false"}),
    ),
)
def test_ikev2_runtime_requires_owned_kernel_route_and_dns(
    monkeypatch, dns_output, helper_override
):
    _mock_ikev2_runtime(
        monkeypatch,
        dns_output=dns_output,
        helper_response=_ikev2_status_response(**helper_override),
    )

    evidence = proof._runtime_evidence_for("ikev2", "https://api.example.test/api")

    assert evidence["ok"] is False


def test_ikev2_charon_nm_rule_tripwire_checks_ipv4_and_ipv6(monkeypatch):
    calls = []

    def fake_run(argv, *, timeout=15):
        calls.append(list(argv))
        if argv == ["ip", "-4", "-N", "rule", "show"]:
            return proof.CommandResult(
                0, "210: not from all fwmark 0xdc lookup 210\n", ""
            )
        if argv == ["ip", "-6", "-N", "rule", "show"]:
            return proof.CommandResult(0, "210: from all lookup 210\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._ikev2_routing_rule_evidence()

    assert evidence["ok"] is False
    assert evidence["bad_rules"] == ["ipv6: 210: from all lookup 210"]
    assert calls == [
        ["ip", "-4", "-N", "rule", "show"],
        ["ip", "-6", "-N", "rule", "show"],
    ]


@pytest.mark.parametrize(
    "rule",
    (
        "210: not from all fwmark 0xdc lookup 210",
        "210: from all not fwmark 0xdc/0xffffffff table 210",
    ),
)
def test_ikev2_charon_nm_rule_accepts_expected_negated_mark_print_forms(
    monkeypatch, rule
):
    monkeypatch.setattr(
        proof,
        "_run",
        lambda argv, timeout=15: proof.CommandResult(0, f"{rule}\n", ""),
    )

    evidence = proof._ikev2_routing_rule_evidence()

    assert evidence["ok"] is True
    assert evidence["bad_rules"] == []
    assert evidence["safe_rule_counts"] == {"ipv4": 1, "ipv6": 1}


@pytest.mark.parametrize("output", ("", "210: not from all fwmark 0xdc lookup 210\n" * 2))
def test_ikev2_charon_nm_rule_requires_exactly_one_per_family(monkeypatch, output):
    monkeypatch.setattr(
        proof,
        "_run",
        lambda argv, timeout=15: proof.CommandResult(0, output, ""),
    )

    evidence = proof._ikev2_routing_rule_evidence()

    assert evidence["ok"] is False
    assert evidence["bad_rules"]


@pytest.mark.parametrize(
    "rule",
    (
        "210: from all fwmark 0xdc lookup 210",
        "210: not from all fwmark 0xdd lookup 210",
        "210: from 192.0.2.0/24 fwmark 0xdc lookup 210",
        "211: not from all fwmark 0xdc lookup 210",
    ),
)
def test_ikev2_charon_nm_rule_rejects_non_negated_wrong_mark_or_foreign_selector(
    monkeypatch, rule
):
    def fake_run(argv, *, timeout=15):
        if argv == ["ip", "-4", "-N", "rule", "show"]:
            return proof.CommandResult(0, f"{rule}\n", "")
        if argv == ["ip", "-6", "-N", "rule", "show"]:
            return proof.CommandResult(
                0, "210: not from all fwmark 0xdc lookup 210\n", ""
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._ikev2_routing_rule_evidence()

    assert evidence["ok"] is False
    assert evidence["bad_rules"] == [f"ipv4: {rule}"]


def _valid_probe_events(protocol="ikev2"):
    return [
        {
            "event": "connect_result",
            "status": "connected",
            "protocol": protocol,
            "last_profile_fetch_ok": True,
            "last_tunnel_start_ok": True,
            "probe_elapsed_ms": 1000,
        },
        {
            "event": "holding_for_evidence",
            "protocol": protocol,
            "hold_seconds": 60,
            "probe_elapsed_ms": 1500,
        },
        {
            "event": "disconnect_result",
            "status": "disconnected",
            "protocol": protocol,
            "probe_elapsed_ms": 61500,
        },
    ]


def test_probe_event_evidence_requires_complete_ordered_state_proof():
    assert proof._probe_event_evidence(_valid_probe_events(), "ikev2", 60)["ok"] is True

    missing_profile = _valid_probe_events()
    missing_profile[0]["last_profile_fetch_ok"] = False
    result = proof._probe_event_evidence(missing_profile, "ikev2", 60)
    assert result["ok"] is False
    assert "successful profile fetch" in " ".join(result["errors"])

    wrong_disconnect = _valid_probe_events()
    wrong_disconnect[2]["status"] = "error"
    result = proof._probe_event_evidence(wrong_disconnect, "ikev2", 60)
    assert result["ok"] is False
    assert "disconnected" in " ".join(result["errors"])


def test_probe_event_evidence_rejects_wrong_protocol_and_missing_hold():
    wrong_protocol = _valid_probe_events("wireguard")
    result = proof._probe_event_evidence(wrong_protocol, "openvpn", 60)
    assert result["ok"] is False

    no_hold = [
        event
        for event in _valid_probe_events()
        if event["event"] != "holding_for_evidence"
    ]
    result = proof._probe_event_evidence(no_hold, "ikev2", 60)
    assert result["ok"] is False
    assert "observed 0" in " ".join(result["errors"])


def test_probe_event_evidence_requires_exact_advertised_hold_duration():
    events = _valid_probe_events()
    events[1]["hold_seconds"] = 59

    result = proof._probe_event_evidence(events, "ikev2", 60)

    assert result["ok"] is False
    assert "hold" in " ".join(result["errors"]).lower()


def test_probe_event_evidence_rejects_short_observed_hold_interval():
    events = _valid_probe_events()
    events[2]["probe_elapsed_ms"] = 61499

    result = proof._probe_event_evidence(events, "ikev2", 60)

    assert result["ok"] is False
    assert "elapsed" in " ".join(result["errors"]).lower()


def test_late_hold_evidence_window_runs_near_end_of_sixty_second_hold():
    due_at, deadline = proof._late_hold_evidence_window(100.0, 60)

    assert due_at == 145.0
    assert deadline == 159.0


def test_positive_durations_are_required():
    assert proof._positive_int("60") == 60
    with pytest.raises(argparse.ArgumentTypeError):
        proof._positive_int("0")
    with pytest.raises(argparse.ArgumentTypeError):
        proof._positive_int("-1")


def test_certification_auth_mode_requires_existing_account_login():
    assert proof._login_auth_mode("login") == "login"
    with pytest.raises(argparse.ArgumentTypeError):
        proof._login_auth_mode("register")
    with pytest.raises(argparse.ArgumentTypeError):
        proof._login_auth_mode("auto")


@pytest.mark.parametrize(
    ("auth_mode", "use_mock_api", "error_fragment"),
    (
        ("register", "false", "stable existing account"),
        ("login", "true", "cannot certify a VPN data plane"),
    ),
)
def test_probe_environment_builder_rejects_register_and_mock_mode(
    auth_mode, use_mock_api, error_fragment
):
    with pytest.raises(argparse.ArgumentTypeError, match=error_fragment):
        proof._build_probe_environment(
            protocol="wireguard",
            email="qa@example.com",
            password="runtime-secret",
            auth_mode=auth_mode,
            server_id=None,
            hold_seconds=60,
            api_base="https://api.example.test/api",
            use_mock_api=use_mock_api,
        )


@pytest.mark.parametrize(
    ("name", "value"),
    (
        ("SECUREWAVE_RUNTIME_PROBE_AUTH_MODE", "register"),
        ("SECUREWAVE_USE_MOCK_API", "true"),
    ),
)
def test_environment_defaults_reject_register_and_mock_mode(monkeypatch, name, value):
    monkeypatch.setenv("SECUREWAVE_RUNTIME_PROBE_AUTH_MODE", "login")
    monkeypatch.setenv("SECUREWAVE_USE_MOCK_API", "false")
    monkeypatch.setenv(name, value)
    monkeypatch.setattr(proof.sys, "argv", ["linux_app_vpn_tunnel_proof.py"])

    with pytest.raises(SystemExit) as exc_info:
        proof.main()

    assert exc_info.value.code == 2


def test_runtime_probe_reads_environment_and_awaits_state_initialization():
    source = (proof.APP_ROOT / proof.PROBE_TARGET).read_text(encoding="utf-8")

    assert "Platform.environment" in source
    assert "String.fromEnvironment" not in source
    assert "auth.register" not in source
    assert "await auth.login" in source
    assert "await notifier.ensureInitialized();" in source
    assert "connectedState.lastProfileFetchOk != true" in source
    assert "connectedState.lastTunnelStartOk != true" in source
    assert "_printProbeEvent('disconnect_result'" in source
    assert "probe_elapsed_ms" in source


def test_binary_stdout_chunk_consumes_connect_and_holding_events_immediately():
    events = _valid_probe_events("wireguard")[:2]
    chunk = b"".join((json.dumps(event) + "\n").encode() for event in events)
    output = []
    recorded_events = []

    pending, consumed = proof._consume_probe_stdout(
        b"",
        chunk,
        output,
        recorded_events,
        email="qa@example.com",
        password="runtime-secret",
    )

    assert pending == b""
    assert [event["event"] for event in consumed] == [
        "connect_result",
        "holding_for_evidence",
    ]
    assert recorded_events == events


@pytest.mark.parametrize("password", ("connected", "true"))
def test_probe_event_control_values_survive_token_matching_password_redaction(password):
    raw_event = _valid_probe_events("wireguard")[0]
    raw_line = json.dumps(raw_event)
    output = []
    recorded_events = []

    event = proof._record_probe_output_line(
        raw_line,
        output,
        recorded_events,
        email="qa@example.com",
        password=password,
    )

    assert event == raw_event
    assert recorded_events == [raw_event]
    assert password not in output[0]


def _run_protocol_with_timed_hold(
    monkeypatch,
    *,
    late_result,
    disconnect_before_due=False,
):
    clock = {"now": 100.0}
    timeline = []
    events = _valid_probe_events("wireguard")
    holding_payload = b"".join(
        (json.dumps(event) + "\n").encode() for event in events[:2]
    )
    disconnect_payload = (json.dumps(events[2]) + "\n").encode()
    chunks = (
        [holding_payload + disconnect_payload]
        if disconnect_before_due
        else [holding_payload, disconnect_payload]
    )
    state = {"done": False, "select_calls": 0}

    class FakeStdout:
        def fileno(self):
            return 123

    class FakeProcess:
        def __init__(self):
            self.stdout = FakeStdout()
            self.returncode = 0

        def poll(self):
            return self.returncode if state["done"] else None

        def wait(self, timeout=None):
            return self.returncode

        def kill(self):
            self.returncode = -9

        def terminate(self):
            self.returncode = -15

    process = FakeProcess()

    def fake_select(reads, writes, errors, timeout=0):
        state["select_calls"] += 1
        if disconnect_before_due or state["select_calls"] == 1:
            return reads, [], []
        if state["select_calls"] == 2:
            clock["now"] = 145.0
            timeline.append("late_due")
            return [], [], []
        return reads, [], []

    def fake_read(file_descriptor, size):
        assert file_descriptor == 123
        if not chunks:
            return b""
        chunk = chunks.pop(0)
        if b'"event": "holding_for_evidence"' in chunk:
            timeline.append("read_holding")
        if b'"event": "disconnect_result"' in chunk:
            timeline.append("read_disconnect")
            state["done"] = True
        return chunk

    evidence_calls = []

    def fake_evidence(protocol, api_base, **kwargs):
        stage = "initial" if not evidence_calls else "late"
        evidence_calls.append(
            {
                "stage": stage,
                "observed_at": clock["now"],
                "deadline": kwargs["evidence_deadline"],
            }
        )
        timeline.append(f"evidence_{stage}")
        if stage == "initial":
            return {"ok": True, "stage": stage}
        return late_result

    monkeypatch.setattr(proof.time, "monotonic", lambda: clock["now"])
    monkeypatch.setattr(proof.subprocess, "Popen", lambda *args, **kwargs: process)
    monkeypatch.setattr(proof.select, "select", fake_select)
    monkeypatch.setattr(proof.os, "read", fake_read)
    monkeypatch.setattr(
        proof,
        "_exit_ip_lookup",
        lambda deadline=None: {
            "ok": True,
            "ip": "192.0.2.10",
            "url": "https://example.test/ip",
            "attempts": [],
        },
    )
    monkeypatch.setattr(
        proof,
        "_ipv6_exit_ip_lookup",
        lambda deadline=None: {
            "ok": True,
            "ip": "2001:db8::10",
            "url": "https://example.test/ipv6",
            "attempts": [],
        },
    )
    monkeypatch.setattr(proof, "_evidence_for", fake_evidence)
    monkeypatch.setattr(
        proof,
        "_verifier",
        lambda: proof.CommandResult(0, '{"ok": true}', ""),
    )

    result = proof.run_protocol(
        probe_binary=Path("/tmp/release/bundle/securewave_app"),
        protocol="wireguard",
        email="qa@example.com",
        password="runtime-secret",
        auth_mode="login",
        server_id=None,
        hold_seconds=60,
        evidence_timeout=180,
        api_base=TEST_API_BASE,
        use_mock_api="false",
    )
    return result, evidence_calls, timeline


def test_run_protocol_collects_initial_and_late_full_evidence_before_disconnect(
    monkeypatch,
):
    result, evidence_calls, timeline = _run_protocol_with_timed_hold(
        monkeypatch,
        late_result={"ok": True, "stage": "late"},
    )

    assert result["ok"] is True
    assert result["evidence"] == {"ok": True, "stage": "initial"}
    assert result["late_hold_evidence"] == {"ok": True, "stage": "late"}
    assert evidence_calls == [
        {"stage": "initial", "observed_at": 100.0, "deadline": 280.0},
        {"stage": "late", "observed_at": 145.0, "deadline": 159.0},
    ]
    assert timeline.index("evidence_initial") < timeline.index("late_due")
    assert timeline.index("evidence_late") < timeline.index("read_disconnect")


@pytest.mark.parametrize(
    ("disconnect_before_due", "late_result"),
    (
        (True, {"ok": True, "stage": "unused"}),
        (False, {"ok": False, "error": "late data plane failed"}),
    ),
)
def test_run_protocol_fails_closed_when_late_hold_evidence_is_missing_or_fails(
    monkeypatch, disconnect_before_due, late_result
):
    result, evidence_calls, _timeline = _run_protocol_with_timed_hold(
        monkeypatch,
        late_result=late_result,
        disconnect_before_due=disconnect_before_due,
    )

    assert result["evidence"]["ok"] is True
    assert result["event_evidence"]["ok"] is True
    assert result["post_disconnect_checks"] == {"ok": True}
    assert result["post_disconnect_verifier"]["returncode"] == 0
    assert result["ok"] is False
    if disconnect_before_due:
        assert len(evidence_calls) == 1
        assert result["late_hold_evidence"] is None
    else:
        assert len(evidence_calls) == 2
        assert result["late_hold_evidence"] == late_result


def test_run_protocol_fails_when_post_disconnect_verifier_fails(monkeypatch):
    payload = b"".join(
        (json.dumps(event) + "\n").encode()
        for event in _valid_probe_events("wireguard")
    )
    chunks = [payload]
    read_chunks = []

    class FakeStdout:
        def fileno(self):
            return 123

    class FakeProcess:
        def __init__(self):
            self.stdout = FakeStdout()
            self.returncode = 0

        def poll(self):
            return None if chunks else self.returncode

        def wait(self, timeout=None):
            return self.returncode

        def kill(self):
            self.returncode = -9

        def terminate(self):
            self.returncode = -15

    process = FakeProcess()
    monkeypatch.setattr(proof.subprocess, "Popen", lambda *args, **kwargs: process)

    def fake_read(file_descriptor, size):
        assert file_descriptor == 123
        chunk = chunks.pop(0) if chunks else b""
        read_chunks.append(chunk)
        return chunk

    monkeypatch.setattr(proof.os, "read", fake_read)
    monkeypatch.setattr(
        proof.select,
        "select",
        lambda reads, writes, errors, timeout=0: (
            reads if chunks else [],
            [],
            [],
        ),
    )
    monkeypatch.setattr(
        proof,
        "_exit_ip_lookup",
        lambda deadline=None: {
            "ok": True,
            "ip": "192.0.2.10",
            "url": "https://example.test/ip",
            "attempts": [],
        },
    )
    monkeypatch.setattr(
        proof,
        "_ipv6_exit_ip_lookup",
        lambda deadline=None: {
            "ok": True,
            "ip": "2001:db8::10",
            "url": "https://example.test/ipv6",
            "attempts": [],
        },
    )
    monkeypatch.setattr(
        proof,
        "_evidence_for",
        lambda protocol, api_base, **kwargs: {"ok": True},
    )
    monkeypatch.setattr(
        proof,
        "_verifier",
        lambda: proof.CommandResult(1, '{"ok": false}', "residue remains"),
    )

    result = proof.run_protocol(
        probe_binary=Path("/tmp/release/bundle/securewave_app"),
        protocol="wireguard",
        email="qa@example.com",
        password="runtime-secret",
        auth_mode="login",
        server_id=None,
        hold_seconds=60,
        evidence_timeout=180,
        api_base=TEST_API_BASE,
        use_mock_api="false",
    )

    assert result["returncode"] == 0
    assert result["event_evidence"]["ok"] is True
    assert result["evidence"]["ok"] is True
    assert result["post_disconnect_verifier"]["returncode"] == 1
    assert result["ok"] is False
    assert read_chunks[0] == payload
    assert b'"event": "connect_result"' in read_chunks[0]
    assert b'"event": "holding_for_evidence"' in read_chunks[0]
    serialized = json.dumps(result)
    assert "192.0.2.10" not in serialized
    assert "runtime-secret" not in serialized


def _prepare_main_test(monkeypatch, tmp_path, protocols):
    monkeypatch.setenv("DEMO_EMAIL", "qa@example.com")
    monkeypatch.setenv("DEMO_PASSWORD", "SwRuntimeSecret!A1")
    monkeypatch.setattr(proof, "_credential_file_path", lambda path: None)
    monkeypatch.setattr(
        proof,
        "_required_tools_evidence",
        lambda: {"ok": True, "resolved": {}, "missing": []},
    )
    cleanup_calls = []

    def fake_cleanup(protocol):
        cleanup_calls.append(protocol)
        return [{"protocol": protocol, "ok": True}]

    verifier_calls = []

    def fake_verifier():
        verifier_calls.append(True)
        return proof.CommandResult(0, '{"ok": true}', "")

    monkeypatch.setattr(proof, "_cleanup_protocol_residue", fake_cleanup)
    monkeypatch.setattr(proof, "_verifier", fake_verifier)
    probe_app_root = tmp_path / "probe-workspace" / "securewave_app"
    probe_app_root.mkdir(parents=True)
    probe_binary = probe_app_root / "build" / "securewave_app"
    probe_binary.parent.mkdir(parents=True)
    probe_binary.write_text("probe", encoding="utf-8")
    probe_binary.chmod(0o700)
    workspace_calls = {"prepare": 0, "build": [], "binary": [], "remove": []}

    def fake_prepare_workspace():
        workspace_calls["prepare"] += 1
        return probe_app_root

    def fake_build_release(app_root):
        workspace_calls["build"].append(app_root)
        return proof.CommandResult(0, "", "")

    def fake_probe_binary(app_root):
        workspace_calls["binary"].append(app_root)
        return probe_binary

    def fake_remove_workspace(app_root):
        workspace_calls["remove"].append(app_root)
        return {"ok": True, "removed": True}

    monkeypatch.setattr(proof, "_prepare_probe_workspace", fake_prepare_workspace)
    monkeypatch.setattr(proof, "_build_release_probe", fake_build_release)
    monkeypatch.setattr(proof, "_probe_binary_path", fake_probe_binary)
    monkeypatch.setattr(proof, "_remove_probe_workspace", fake_remove_workspace)
    argv = [
        "linux_app_vpn_tunnel_proof.py",
        "--json",
        "--api-base",
        TEST_API_BASE,
    ]
    for protocol in protocols:
        argv.extend(["--protocol", protocol])
    monkeypatch.setattr(proof.sys, "argv", argv)
    return cleanup_calls, verifier_calls, workspace_calls, probe_app_root


def test_explicit_single_protocol_invocation_runs_exactly_once(
    monkeypatch, tmp_path, capsys
):
    cleanup_calls, verifier_calls, workspace_calls, probe_app_root = _prepare_main_test(
        monkeypatch, tmp_path, ["ikev2"]
    )
    run_calls = []

    def fake_run_protocol(**kwargs):
        run_calls.append(kwargs["protocol"])
        return {"protocol": kwargs["protocol"], "ok": True}

    monkeypatch.setattr(proof, "run_protocol", fake_run_protocol)

    assert proof.main() == 0
    assert run_calls == ["ikev2"]
    assert cleanup_calls == list(proof.SUPPORTED_PROTOCOLS) * 2
    assert len(verifier_calls) == 2
    assert workspace_calls == {
        "prepare": 1,
        "build": [probe_app_root],
        "binary": [probe_app_root],
        "remove": [probe_app_root],
    }
    assert '"ok": true' in capsys.readouterr().out


def test_protocol_failure_stops_sequence_and_finally_cleans_all(monkeypatch, tmp_path):
    cleanup_calls, verifier_calls, workspace_calls, probe_app_root = _prepare_main_test(
        monkeypatch, tmp_path, ["wireguard", "openvpn", "ikev2"]
    )
    run_calls = []

    def fake_run_protocol(**kwargs):
        run_calls.append(kwargs["protocol"])
        return {"protocol": kwargs["protocol"], "ok": False}

    monkeypatch.setattr(proof, "run_protocol", fake_run_protocol)

    assert proof.main() == 1
    assert run_calls == ["wireguard"]
    assert cleanup_calls == [
        "wireguard",
        "openvpn",
        "ikev2",
        "wireguard",
        "openvpn",
        "ikev2",
    ]
    assert len(verifier_calls) == 2
    assert workspace_calls["remove"] == [probe_app_root]


def test_sigterm_during_final_cleanup_defers_failure_until_all_finalizers_finish(
    monkeypatch, tmp_path, capsys
):
    protocols = ["wireguard", "openvpn", "ikev2"]
    _, verifier_calls, workspace_calls, probe_app_root = _prepare_main_test(
        monkeypatch, tmp_path, protocols
    )
    cleanup_calls = []

    def signal_during_first_final_cleanup(protocol):
        cleanup_calls.append(protocol)
        if len(cleanup_calls) == len(protocols) + 1:
            signal.raise_signal(signal.SIGTERM)
        return [{"protocol": protocol, "ok": True}]

    monkeypatch.setattr(
        proof, "_cleanup_protocol_residue", signal_during_first_final_cleanup
    )
    monkeypatch.setattr(
        proof,
        "run_protocol",
        lambda **kwargs: {"protocol": kwargs["protocol"], "ok": True},
    )

    returncode = proof.main()
    payload = json.loads(capsys.readouterr().out)

    assert returncode == 1
    assert cleanup_calls == protocols + protocols
    assert len(verifier_calls) == 2
    assert workspace_calls["remove"] == [probe_app_root]
    assert payload["ok"] is False
    assert payload["error"] == "proof interrupted during final cleanup by SIGTERM"
    assert [result["protocol"] for result in payload["results"]] == protocols
    assert all(result["ok"] is True for result in payload["results"])
    assert [action["protocol"] for action in payload["cleanup_actions"]] == protocols
    assert payload["cleanup_checks"]["ok"] is True
    assert payload["probe_workspace_cleanup"] == {"ok": True, "removed": True}
