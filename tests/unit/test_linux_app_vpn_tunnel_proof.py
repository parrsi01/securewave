from scripts import linux_app_vpn_tunnel_proof as proof


def _passing_network_gates(monkeypatch):
    monkeypatch.setattr(
        proof,
        "_data_plane_evidence",
        lambda deadline=None: {"ok": True, "selected_ip": "1.1.1.1", "attempts": []},
    )
    monkeypatch.setattr(
        proof,
        "_dns_evidence",
        lambda deadline=None: {"ok": True, "hostname": "example.com", "attempts": []},
    )
    monkeypatch.setattr(
        proof,
        "_exit_ip_evidence",
        lambda pre_connect_exit_ip, deadline=None: {
            "ok": True,
            "pre_connect_ip": "92.105.134.148",
            "connected_ip": "138.199.204.139",
            "pre_connect": {"ok": True, "ip": "92.105.134.148"},
            "connected": {"ok": True, "ip": "138.199.204.139"},
        },
    )
    monkeypatch.setattr(
        proof,
        "_ikev2_routing_rule_evidence",
        lambda deadline=None: {"ok": True, "bad_rules": [], "ip_rule": {}},
    )


def test_wireguard_evidence_requires_sw_wg_route(monkeypatch):
    _passing_network_gates(monkeypatch)

    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "sw-wg"]:
            return proof.CommandResult(0, "10: sw-wg: <POINTOPOINT>\n", "")
        if argv[:4] == ["ip", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 dev sw-wg src 10.8.0.2\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True})
    monkeypatch.setattr(
        proof,
        "_wireguard_counter_evidence",
        lambda: {"ok": True, "response": {"stdout": "peer 12 34"}},
    )

    assert proof._evidence_for("wireguard", "https://api.example.test/api")["ok"] is True


def test_openvpn_evidence_requires_tun_route_and_process(monkeypatch):
    _passing_network_gates(monkeypatch)

    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "-o", "link", "show"]:
            return proof.CommandResult(0, "11: tun0: <POINTOPOINT>\n", "")
        if argv[:4] == ["ip", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 dev tun0 src 10.9.0.2\n", "")
        if argv[:2] == ["pgrep", "-x"]:
            return proof.CommandResult(0, "123\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(proof, "_openvpn_log_evidence", lambda: {"ok": True})
    monkeypatch.setattr(proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True})

    assert proof._evidence_for("openvpn", "https://api.example.test/api")["ok"] is True


def test_ikev2_evidence_requires_nm_vpn_route_dns_and_xfrm_state(monkeypatch):
    _passing_network_gates(monkeypatch)

    def fake_run(argv, *, timeout=15):
        if argv[:5] == ["nmcli", "-t", "-f", "NAME,TYPE", "connection"]:
            return proof.CommandResult(0, "SecureWave-IKEv2:vpn\n", "")
        if argv[:5] == ["nmcli", "-t", "-f", "IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE", "connection"]:
            return proof.CommandResult(0, "IP4.DNS[1]:94.140.14.14\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": {"ok": "true", "status": "connected"},
        },
    )
    monkeypatch.setattr(proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True})

    assert proof._evidence_for("ikev2", "https://api.example.test/api")["ok"] is True


def test_wireguard_cleanup_removes_securewave_link(monkeypatch):
    calls = []

    def fake_helper_request(fields):
        calls.append(fields)
        return {"ok": "true", "status": "disconnected"}

    monkeypatch.setattr(proof, "_helper_request", fake_helper_request)

    actions = proof._cleanup_protocol_residue("wireguard")

    assert actions[0]["protocol"] == "wireguard"
    assert calls == [
        {"op": "wireguard.cleanup", "config_path": proof._state_path("sw-wg.conf")}
    ]


def test_evidence_fails_when_route_uses_physical_interface(monkeypatch):
    _passing_network_gates(monkeypatch)

    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "sw-wg"]:
            return proof.CommandResult(0, "10: sw-wg: <POINTOPOINT>\n", "")
        if argv[:4] == ["ip", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 via 192.168.64.1 dev enp0s1\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True})
    monkeypatch.setattr(
        proof,
        "_wireguard_counter_evidence",
        lambda: {"ok": True, "response": {"stdout": "peer 12 34"}},
    )

    assert proof._evidence_for("wireguard", "https://api.example.test/api")["ok"] is False


def test_hold_evidence_passes_with_data_dns_exit_ip_and_ikev2_rule(monkeypatch):
    calls = []

    def fake_run(argv, *, timeout=15):
        calls.append(list(argv))
        if argv[:4] == ["curl", "-4", "-m", "5"]:
            return proof.CommandResult(0, "200\n", "")
        if argv[:1] == ["dig"]:
            return proof.CommandResult(0, "93.184.216.34\n", "")
        if argv[:5] == ["curl", "-4", "-m", "8", "-fsS"]:
            return proof.CommandResult(0, "138.199.204.139\n", "")
        if argv == ["ip", "rule"]:
            return proof.CommandResult(0, "220: not from all fwmark 0xdc lookup 220\n", "")
        if argv[:5] == ["nmcli", "-t", "-f", "NAME,TYPE", "connection"]:
            return proof.CommandResult(0, "SecureWave-IKEv2:vpn\n", "")
        if argv[:5] == ["nmcli", "-t", "-f", "IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE", "connection"]:
            return proof.CommandResult(0, "IP4.DNS[1]:1.1.1.1\nIP4.ROUTE[1]:dst = 0.0.0.0/0\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)
    monkeypatch.setattr(
        proof,
        "_helper_evidence",
        lambda fields, timeout=20.0: {
            "ok": True,
            "response": {"ok": "true", "status": "connected"},
        },
    )
    monkeypatch.setattr(proof, "_backend_health_evidence", lambda api_base, **kwargs: {"ok": True})

    evidence = proof._evidence_for(
        "ikev2",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
    )

    assert evidence["ok"] is True
    assert evidence["data_plane"]["selected_ip"] == "1.1.1.1"
    assert evidence["dns"]["hostname"] == "example.com"
    assert evidence["exit_ip"]["pre_connect_ip"] == "92.105.134.148"
    assert evidence["exit_ip"]["connected_ip"] == "138.199.204.139"
    assert evidence["ikev2_routing_rule"]["ok"] is True

    data_plane_index = next(i for i, call in enumerate(calls) if call[:4] == ["curl", "-4", "-m", "5"])
    dns_index = next(i for i, call in enumerate(calls) if call[:1] == ["dig"])
    exit_ip_index = next(i for i, call in enumerate(calls) if call[:5] == ["curl", "-4", "-m", "8", "-fsS"])
    rule_index = next(i for i, call in enumerate(calls) if call == ["ip", "rule"])
    assert data_plane_index < dns_index < exit_ip_index < rule_index


def test_hold_evidence_fails_when_data_plane_is_dead(monkeypatch):
    calls = []

    def fake_run(argv, *, timeout=15):
        calls.append(list(argv))
        if argv[:4] == ["curl", "-4", "-m", "5"]:
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
        if argv[:4] == ["curl", "-4", "-m", "5"]:
            return proof.CommandResult(0, "200\n", "")
        if argv[:1] == ["dig"]:
            return proof.CommandResult(9, "", "no servers could be reached")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._evidence_for(
        "openvpn",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
    )

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "dns_broken_in_tunnel"
    assert len(evidence["dns"]["attempts"]) == 2
    assert all(call[:5] != ["curl", "-4", "-m", "8", "-fsS"] for call in calls)


def test_hold_evidence_fails_when_exit_ip_is_unchanged(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["curl", "-4", "-m", "5"]:
            return proof.CommandResult(0, "200\n", "")
        if argv[:1] == ["dig"]:
            return proof.CommandResult(0, "93.184.216.34\n", "")
        if argv[:5] == ["curl", "-4", "-m", "8", "-fsS"]:
            return proof.CommandResult(0, "92.105.134.148\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._evidence_for(
        "wireguard",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
    )

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "exit_ip_unchanged"
    assert evidence["exit_ip"]["pre_connect_ip"] == "92.105.134.148"
    assert evidence["exit_ip"]["connected_ip"] == "92.105.134.148"


def test_hold_evidence_fails_on_bad_ikev2_pref_220_rule(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["curl", "-4", "-m", "5"]:
            return proof.CommandResult(0, "200\n", "")
        if argv[:1] == ["dig"]:
            return proof.CommandResult(0, "93.184.216.34\n", "")
        if argv[:5] == ["curl", "-4", "-m", "8", "-fsS"]:
            return proof.CommandResult(0, "138.199.204.139\n", "")
        if argv == ["ip", "rule"]:
            return proof.CommandResult(
                0,
                "220: from all lookup 220\n220: not from all fwmark 0xdc lookup 220\n",
                "",
            )
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    evidence = proof._evidence_for(
        "ikev2",
        "https://api.example.test/api",
        pre_connect_exit_ip={"ok": True, "ip": "92.105.134.148", "attempts": []},
    )

    assert evidence["ok"] is False
    assert evidence["error_kind"] == "ikev2_routing_loop_rule"
    assert evidence["ikev2_routing_rule"]["bad_rules"] == ["220: from all lookup 220"]


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

    assert proof._env_default(
        "SECUREWAVE_TEST_EMAIL",
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
    ) == "qa@example.com"


def test_env_default_prefers_demo_account_alias(monkeypatch):
    monkeypatch.setenv("DEMO_EMAIL", "demo@example.com")
    monkeypatch.setenv("SECUREWAVE_TEST_EMAIL", "qa@example.com")

    assert proof._env_default(
        "DEMO_EMAIL",
        "SECUREWAVE_TEST_EMAIL",
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
    ) == "demo@example.com"


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

    assert proof._file_default(
        values,
        "DEMO_EMAIL",
        "SECUREWAVE_TEST_EMAIL",
    ) == "demo@example.com"
    assert proof._file_default(
        values,
        "DEMO_PASSWORD",
        "SECUREWAVE_TEST_PASSWORD",
    ) == "SwRuntimeSecret!A1"
    assert "IGNORED_KEY" not in values


def test_redact_email_keeps_domain_only():
    assert proof._redact_email("demo@example.com") == "d***@example.com"
    assert proof._redact_email("not-an-email") == "configured"


def test_default_api_base_uses_live_api_when_env_missing(monkeypatch):
    monkeypatch.delenv("SECUREWAVE_API_BASE_URL", raising=False)

    assert proof._default_api_base() == "https://api.securewaveapp.com/api"


def test_default_api_base_prefers_explicit_env(monkeypatch):
    monkeypatch.setenv("SECUREWAVE_API_BASE_URL", "http://localhost:8000/api")

    assert proof._default_api_base() == "http://localhost:8000/api"


def test_flutter_command_includes_api_and_mock_dart_defines():
    command = proof._build_flutter_command(
        protocol="wireguard",
        email="qa@example.com",
        password="secret",
        auth_mode="login",
        server_id=None,
        hold_seconds=12,
        api_base="http://localhost:8000/api",
        use_mock_api="false",
    )

    assert "--dart-define=SECUREWAVE_API_BASE_URL=http://localhost:8000/api" in command
    assert "--dart-define=SECUREWAVE_USE_MOCK_API=false" in command
    assert "--dart-define=SECUREWAVE_RUNTIME_PROBE_PROTOCOL=wireguard" in command


def test_flutter_command_uses_default_api_base():
    command = proof._build_flutter_command(
        protocol="wireguard",
        email="qa@example.com",
        password="secret",
        auth_mode="login",
        server_id=None,
        hold_seconds=12,
        api_base=proof._default_api_base(),
        use_mock_api="false",
    )

    assert (
        "--dart-define=SECUREWAVE_API_BASE_URL=https://api.securewaveapp.com/api"
        in command
    )


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
    assert evidence["error"] == "OpenVPN process started but no tunnel route was detected."
    assert evidence["event"] == event


def test_json_object_parses_dict_only():
    assert proof._json_object('{"ok": false}') == {"ok": False}
    assert proof._json_object("[1, 2, 3]") is None
    assert proof._json_object("not json") is None
