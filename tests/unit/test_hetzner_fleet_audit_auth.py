import json
import subprocess

from infrastructure.hetzner import audit_vpn_fleet


def test_inventory_uses_api_when_token_is_present(monkeypatch):
    calls = []

    def fake_paginated(token, path, key):
        calls.append((token, path, key))
        return [{"id": 1}]

    monkeypatch.setattr(audit_vpn_fleet, "_hcloud_paginated", fake_paginated)

    servers, firewalls, source = audit_vpn_fleet._load_hcloud_inventory("token")

    assert servers == [{"id": 1}]
    assert firewalls == [{"id": 1}]
    assert source == "api_token"
    assert calls == [
        ("token", "/servers", "servers"),
        ("token", "/firewalls", "firewalls"),
    ]


def test_inventory_falls_back_to_authenticated_hcloud_context(monkeypatch):
    server = {
        "id": 1,
        "name": "securewave-prod",
        "datacenter": None,
        "location": {"name": "nbg1", "city": "Nuremberg", "country": "DE"},
    }
    firewall = {"id": 2, "name": "securewave-fw", "rules": []}
    responses = {
        "server": [server],
        "firewall": [firewall],
    }

    monkeypatch.setattr(audit_vpn_fleet.shutil, "which", lambda command: "/usr/bin/hcloud")

    def fake_run(command, **kwargs):
        assert command[0] == "hcloud"
        assert kwargs == {"check": True, "capture_output": True, "text": True}
        return subprocess.CompletedProcess(
            command,
            0,
            stdout=json.dumps(responses[command[1]]),
            stderr="",
        )

    monkeypatch.setattr(audit_vpn_fleet.subprocess, "run", fake_run)

    servers, firewalls, source = audit_vpn_fleet._load_hcloud_inventory("")

    assert source == "hcloud_context"
    assert servers[0]["datacenter"]["location"]["name"] == "nbg1"
    assert firewalls == [firewall]


def test_invalid_hcloud_context_fails_without_printing_credentials(monkeypatch):
    monkeypatch.setattr(audit_vpn_fleet.shutil, "which", lambda command: "/usr/bin/hcloud")
    monkeypatch.setattr(
        audit_vpn_fleet.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args[0],
            1,
            stdout="",
            stderr="authentication failed",
        ),
    )

    try:
        audit_vpn_fleet._load_hcloud_inventory("")
    except SystemExit as exc:
        assert "HETZNER_API_TOKEN" in str(exc)
        assert "hcloud CLI context" in str(exc)
        assert "authentication failed" not in str(exc)
    else:
        raise AssertionError("missing authentication must fail closed")
