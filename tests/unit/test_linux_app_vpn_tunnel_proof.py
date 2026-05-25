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
