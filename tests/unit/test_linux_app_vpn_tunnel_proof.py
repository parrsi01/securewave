from scripts import linux_app_vpn_tunnel_proof as proof


def test_wireguard_evidence_requires_securewave_route(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "securewave"]:
            return proof.CommandResult(0, "10: securewave: <POINTOPOINT>\n", "")
        if argv[:4] == ["ip", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 dev securewave src 10.8.0.2\n", "")
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


def test_ikev2_evidence_requires_securewave_sa(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:2] == ["swanctl", "--list-sas"]:
            return proof.CommandResult(0, "securewave: #1, ESTABLISHED\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    assert proof._evidence_for("ikev2")["ok"] is True


def test_evidence_fails_when_route_uses_physical_interface(monkeypatch):
    def fake_run(argv, *, timeout=15):
        if argv[:4] == ["ip", "link", "show", "securewave"]:
            return proof.CommandResult(0, "10: securewave: <POINTOPOINT>\n", "")
        if argv[:4] == ["ip", "route", "get", "1.1.1.1"]:
            return proof.CommandResult(0, "1.1.1.1 via 192.168.64.1 dev enp0s1\n", "")
        raise AssertionError(argv)

    monkeypatch.setattr(proof, "_run", fake_run)

    assert proof._evidence_for("wireguard")["ok"] is False


def test_placeholder_credentials_are_detected():
    assert proof._is_placeholder("real@email.com") is True
    assert proof._is_placeholder("existing-live-password") is True
    assert proof._is_placeholder("qa@example.com") is False


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
