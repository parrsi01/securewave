from __future__ import annotations

import pytest

from services.tunnel_runtime import ensure_tunnel_mode_allowed


def test_simulated_mode_rejected_in_production(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("TESTING", "false")
    monkeypatch.delenv("SECUREWAVE_ALLOW_DEV_SIMULATED_TUNNEL_MODE", raising=False)

    with pytest.raises(RuntimeError, match="forbidden in production"):
        ensure_tunnel_mode_allowed(mode="simulated")


def test_simulated_mode_rejected_without_explicit_dev_flag(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setenv("TESTING", "false")
    monkeypatch.delenv("SECUREWAVE_ALLOW_DEV_SIMULATED_TUNNEL_MODE", raising=False)

    with pytest.raises(RuntimeError, match="requires SECUREWAVE_ALLOW_DEV_SIMULATED_TUNNEL_MODE=1"):
        ensure_tunnel_mode_allowed(mode="simulated")


def test_simulated_mode_allowed_with_dev_flag(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setenv("TESTING", "false")
    monkeypatch.setenv("SECUREWAVE_ALLOW_DEV_SIMULATED_TUNNEL_MODE", "1")

    assert ensure_tunnel_mode_allowed(mode="simulated") == "simulated"


def test_simulated_mode_allowed_in_tests(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setenv("TESTING", "true")
    monkeypatch.delenv("SECUREWAVE_ALLOW_DEV_SIMULATED_TUNNEL_MODE", raising=False)

    assert ensure_tunnel_mode_allowed(mode="simulated") == "simulated"
