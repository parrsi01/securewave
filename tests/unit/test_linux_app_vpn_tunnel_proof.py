from scripts import linux_app_vpn_tunnel_proof as proof


def test_wireguard_evidence_requires_sw_wg_route(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "sw-wg"]:
            return proof.CommandResult(0, "10: sw-wg: <POINTOPOINT>\n", "")
        if argv[:4] == ["ip", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 dev sw-wg src 10.8.0.2\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    assert proof._evidence_for("wireguard")["ok"] is True


def test_openvpn_evidence_requires_tun_route_and_process(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "tun0"]:
            return proof.CommandResult(0, "11: tun0: <POINTOPOINT>\n", "")
        if argv[:4] == ["ip", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 dev tun0 src 10.9.0.2\n", "")
        if argv[:2] == ["pgrep", "-af"]:
            return proof.CommandResult(0, "123 openvpn --config securewave-openvpn.ovpn\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    assert proof._evidence_for("openvpn")["ok"] is True


def test_ikev2_evidence_requires_nm_vpn_route_dns_and_xfrm_state(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:5] == ["nmcli", "-t", "-f", "NAME,TYPE", "connection"]:
            return proof.CommandResult(0, "SecureWave-IKEv2:vpn\n", "")
        if argv[:5] == ["nmcli", "-t", "-f", "IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE", "connection"]:
            return proof.CommandResult(0, "IP4.DNS[1]:94.140.14.14\n", "")
        if argv[-1:] == ["xfrm-state"]:
            return proof.CommandResult(0, "src 203.0.113.2 dst 198.51.100.2\n\tproto esp spi 0x1\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    assert proof._evidence_for("ikev2")["ok"] is True


def test_evidence_fails_when_route_uses_physical_interface(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "sw-wg"]:
            return proof.CommandResult(0, "10: sw-wg: <POINTOPOINT>\n", "")
        if argv[:4] == ["ip", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 via 192.168.64.1 dev enp0s1\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    assert proof._evidence_for("wireguard")["ok"] is False


def test_placeholder_credentials_are_detected():
    assert proof._is_placeholder("real@email.com") is True
    assert proof._is_placeholder("existing-live-password") is True
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


def test_generated_probe_credentials_are_live_registration_shape():
    email, password = proof._new_probe_credentials()

    assert email.startswith("securewave.runtime.")
    assert email.endswith("@gmail.com")
    assert password.startswith("SwRuntime")
    assert password.endswith("!A1")


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


def test_json_object_parses_dict_only():
    assert proof._json_object('{"ok": false}') == {"ok": False}
    assert proof._json_object("[1, 2, 3]") is None
    assert proof._json_object("not json") is None
