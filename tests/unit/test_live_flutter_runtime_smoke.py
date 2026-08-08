import sys

from scripts import live_flutter_runtime_smoke as smoke


def test_smoke_requires_an_explicit_target(monkeypatch):
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "live_flutter_runtime_smoke.py",
            "--api-base",
            "https://staging.example.test/api",
        ],
    )
    try:
        smoke.main()
    except SystemExit as exc:
        assert exc.code == 2
    else:  # pragma: no cover - argparse must reject the missing target
        raise AssertionError("smoke unexpectedly accepted an inferred target")


def test_smoke_uses_existing_account_without_registration_by_default(monkeypatch, capsys):
    calls = []

    def fake_request(method, url, **kwargs):
        path = url.split("/api", 1)[-1]
        calls.append((method, path))
        if path == "/health":
            return 200, {"status": "ok"}
        if path == "/auth/login":
            return 200, {"access_token": "runtime-token"}
        if path == "/auth/me":
            return 200, {"email_verified": True}
        if path == "/user/plan":
            return 200, {"plan": "basic", "used_gb": 0, "data_cap_gb": 5}
        if path == "/vpn/servers":
            return 200, {"servers": [{"id": "server-1"}]}
        if path == "/vpn/profile":
            return 200, {}
        raise AssertionError(f"unexpected smoke path: {path}")

    monkeypatch.setattr(smoke, "_json_request", fake_request)
    monkeypatch.setenv("SECUREWAVE_DIAGNOSTIC_EMAIL", "qa@example.test")
    monkeypatch.setenv("SECUREWAVE_DIAGNOSTIC_PASSWORD", "not-written")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "live_flutter_runtime_smoke.py",
            "--api-base",
            "https://staging.example.test/api",
            "--target-ref",
            "staging-fleet-01",
        ],
    )

    assert smoke.main() == 0
    output = capsys.readouterr().out
    assert ("POST", "/auth/register") not in calls
    assert calls.count(("POST", "/vpn/profile")) == 1
    assert "not-written" not in output
    assert "qa@example.test" not in output
    assert "staging.example.test" not in output


def test_smoke_exercises_openvpn_only_when_authenticated_readiness_is_advertised(
    monkeypatch, capsys
):
    calls = []

    def fake_request(method, url, **kwargs):
        path = url.split("/api", 1)[-1]
        calls.append((method, path))
        if path == "/health":
            return 200, {"status": "ok"}
        if path == "/auth/login":
            return 200, {"access_token": "runtime-token"}
        if path == "/auth/me":
            return 200, {"email_verified": True}
        if path == "/user/plan":
            return 200, {"plan": "basic"}
        if path == "/vpn/servers":
            return 200, {
                "servers": [
                    {
                        "server_id": "server-1",
                        "supports_openvpn": True,
                        "supported_protocols": ["wireguard", "openvpn"],
                    }
                ]
            }
        if path == "/vpn/profile":
            return 200, {}
        raise AssertionError(f"unexpected smoke path: {path}")

    monkeypatch.setattr(smoke, "_json_request", fake_request)
    monkeypatch.setenv("SECUREWAVE_DIAGNOSTIC_EMAIL", "qa@example.test")
    monkeypatch.setenv("SECUREWAVE_DIAGNOSTIC_PASSWORD", "not-written")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "live_flutter_runtime_smoke.py",
            "--api-base",
            "https://staging.example.test/api",
            "--target-ref",
            "staging-fleet-01",
        ],
    )

    assert smoke.main() == 0
    assert calls.count(("POST", "/vpn/profile")) == 2
    output = capsys.readouterr().out
    assert "ikev2" not in output.lower()
