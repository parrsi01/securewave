import sys

import pytest

from scripts import live_flutter_runtime_smoke as smoke


def _ok_profile(protocol: str) -> dict:
    if protocol == "openvpn":
        return {"profile": {"type": "openvpn", "ovpn_config": "client\nremote 10.0.0.1 1194\n"}}
    if protocol == "ikev2":
        return {
            "profile": {
                "type": "ikev2",
                "server": "10.0.0.1",
                "username": "user",
                "password": "pass",
                "ca_cert_pem": "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
            }
        }
    return {
        "wireguard_config": "wg" if protocol == "wireguard" else "",
    }


def test_live_smoke_rejects_partial_linux_protocol_availability(monkeypatch):
    def fake_request(method, url, *, token=None, payload=None, timeout=20):
        if url.endswith("/health"):
            return 200, {}
        if url.endswith("/auth/register"):
            return 201, {}
        if url.endswith("/auth/login"):
            return 200, {"access_token": "token"}
        if url.endswith("/auth/me"):
            return 200, {"email": "qa@example.test"}
        if url.endswith("/user/plan"):
            return 200, {"plan": "Free"}
        if url.endswith("/vpn/protocols?device_type=linux"):
            return 200, {
                "protocols": [
                    {
                        "protocol": "wireguard",
                        "enabled": True,
                        "platform_supported": True,
                        "server_enabled": True,
                    },
                    {
                        "protocol": "openvpn",
                        "enabled": True,
                        "platform_supported": True,
                        "server_enabled": True,
                    },
                    {
                        "protocol": "ikev2",
                        "enabled": False,
                        "reason": "not_supported_on_platform",
                        "platform_supported": False,
                        "server_enabled": True,
                    },
                ]
            }
        raise AssertionError(f"unexpected request: {method} {url}")

    monkeypatch.setattr(smoke, "_json_request", fake_request)
    monkeypatch.setattr(
        sys,
        "argv",
        ["live_flutter_runtime_smoke.py", "--email", "qa@example.test", "--password", "Password1!"],
    )

    with pytest.raises(RuntimeError, match="protocol availability is not enabled"):
        smoke.main()


def test_live_smoke_requires_all_protocol_profiles_and_omits_password(monkeypatch, capsys):
    def fake_request(method, url, *, token=None, payload=None, timeout=20):
        if url.endswith("/health"):
            return 200, {}
        if url.endswith("/auth/register"):
            return 201, {}
        if url.endswith("/auth/login"):
            return 200, {"access_token": "token"}
        if url.endswith("/auth/me"):
            return 200, {"email": "qa@example.test"}
        if url.endswith("/user/plan"):
            return 200, {"plan": "Free", "used_gb": 0, "limit_gb": 5}
        if url.endswith("/vpn/protocols?device_type=linux"):
            return 200, {
                "protocols": [
                    {
                        "protocol": protocol,
                        "enabled": True,
                        "platform_supported": True,
                        "server_enabled": True,
                    }
                    for protocol in smoke.PROTOCOLS
                ]
            }
        if url.endswith("/vpn/servers?device_type=linux"):
            return 200, {
                "servers": [
                    {
                        "server_id": "de-nue-1",
                        "supported_protocols": list(smoke.PROTOCOLS),
                    }
                ]
            }
        if url.endswith("/vpn/profile"):
            return 200, _ok_profile(payload["protocol"])
        raise AssertionError(f"unexpected request: {method} {url}")

    monkeypatch.setattr(smoke, "_json_request", fake_request)
    monkeypatch.setattr(
        sys,
        "argv",
        ["live_flutter_runtime_smoke.py", "--email", "qa@example.test", "--password", "Password1!"],
    )

    assert smoke.main() == 0
    output = capsys.readouterr().out
    assert "Password1!" not in output
    assert '"ikev2": [' in output
    assert '"profile_shapes"' in output
    assert '"app_consumable_config": true' in output


def test_live_smoke_rejects_200_profile_without_app_consumable_config(monkeypatch):
    def fake_request(method, url, *, token=None, payload=None, timeout=20):
        if url.endswith("/health"):
            return 200, {}
        if url.endswith("/auth/register"):
            return 201, {}
        if url.endswith("/auth/login"):
            return 200, {"access_token": "token"}
        if url.endswith("/auth/me"):
            return 200, {"email": "qa@example.test"}
        if url.endswith("/user/plan"):
            return 200, {"plan": "Free"}
        if url.endswith("/vpn/protocols?device_type=linux"):
            return 200, {
                "protocols": [
                    {
                        "protocol": protocol,
                        "enabled": True,
                        "platform_supported": True,
                        "server_enabled": True,
                    }
                    for protocol in smoke.PROTOCOLS
                ]
            }
        if url.endswith("/vpn/servers?device_type=linux"):
            return 200, {
                "servers": [
                    {
                        "server_id": "de-nue-1",
                        "supported_protocols": list(smoke.PROTOCOLS),
                    }
                ]
            }
        if url.endswith("/vpn/profile"):
            return 200, {"profile": {"type": payload["protocol"]}}
        raise AssertionError(f"unexpected request: {method} {url}")

    monkeypatch.setattr(smoke, "_json_request", fake_request)
    monkeypatch.setattr(
        sys,
        "argv",
        ["live_flutter_runtime_smoke.py", "--email", "qa@example.test", "--password", "Password1!"],
    )

    with pytest.raises(RuntimeError, match="app-consumable runtime config"):
        smoke.main()


def test_live_smoke_does_not_login_generated_account_after_registration_rate_limit(monkeypatch):
    calls = []

    def fake_request(method, url, *, token=None, payload=None, timeout=20):
        calls.append(url)
        if url.endswith("/health"):
            return 200, {}
        if url.endswith("/auth/register"):
            return 429, {"detail": "rate limited"}
        if url.endswith("/auth/login"):
            raise AssertionError("generated account was never registered")
        raise AssertionError(f"unexpected request: {method} {url}")

    monkeypatch.setattr(smoke, "_json_request", fake_request)
    monkeypatch.setattr(sys, "argv", ["live_flutter_runtime_smoke.py"])

    with pytest.raises(RuntimeError, match="registration rate limit active"):
        smoke.main()
    assert not any(url.endswith("/auth/login") for url in calls)


def test_live_smoke_can_login_existing_account_after_registration_rate_limit(monkeypatch):
    def fake_request(method, url, *, token=None, payload=None, timeout=20):
        if url.endswith("/health"):
            return 200, {}
        if url.endswith("/auth/register"):
            return 429, {"detail": "rate limited"}
        if url.endswith("/auth/login"):
            return 200, {"access_token": "token"}
        if url.endswith("/auth/me"):
            return 200, {"email": "qa@example.test"}
        if url.endswith("/user/plan"):
            return 200, {"plan": "Free"}
        if url.endswith("/vpn/protocols?device_type=linux"):
            return 200, {
                "protocols": [
                    {
                        "protocol": protocol,
                        "enabled": True,
                        "platform_supported": True,
                        "server_enabled": True,
                    }
                    for protocol in smoke.PROTOCOLS
                ]
            }
        if url.endswith("/vpn/servers?device_type=linux"):
            return 200, {
                "servers": [
                    {
                        "server_id": "de-nue-1",
                        "supported_protocols": list(smoke.PROTOCOLS),
                    }
                ]
            }
        if url.endswith("/vpn/profile"):
            return 200, _ok_profile(payload["protocol"])
        raise AssertionError(f"unexpected request: {method} {url}")

    monkeypatch.setattr(smoke, "_json_request", fake_request)
    monkeypatch.setattr(
        sys,
        "argv",
        ["live_flutter_runtime_smoke.py", "--email", "qa@example.test", "--password", "Password1!"],
    )

    assert smoke.main() == 0
