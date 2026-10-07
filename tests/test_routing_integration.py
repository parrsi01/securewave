"""Exercise the real selector: advisory ML cannot change VPN assignments."""
import os
from types import SimpleNamespace

os.environ.setdefault("TESTING", "true")
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("ACCESS_TOKEN_SECRET", "test-only-access-token-secret")
os.environ.setdefault("ENVIRONMENT", "testing")

import pytest
from fastapi import HTTPException
from routes import vpn


def server(identifier, health="healthy", performance=100, latency=50):
    return SimpleNamespace(server_id=identifier, health_status=health,
                           performance_score=performance, latency_ms=latency)


@pytest.fixture
def fleet(monkeypatch):
    best = server("baseline", latency=10)
    alternate = server("alternate", latency=100)
    unhealthy = server("unhealthy", health="unhealthy", performance=200)
    rows = [alternate, unhealthy, best]
    monkeypatch.setattr(vpn, "_active_wireguard_servers", lambda *_: rows.copy())
    monkeypatch.setattr(vpn.VPNServerService, "get_server_by_id",
                        lambda db, identifier: next((s for s in rows if s.server_id == identifier), None))
    return best, alternate


def test_shadow_recommendation_cannot_change_assignment(monkeypatch, fleet):
    baseline, alternate = fleet
    observed = []
    def recommend(candidates, chosen, explicit=False):
        observed.append((chosen, explicit, tuple(candidates)))
        return SimpleNamespace(recommended_server_id=alternate.server_id)
    monkeypatch.setattr(vpn, "observe_selection", recommend)
    assert vpn._select_server(None, None, None) is baseline
    assert observed[0][:2] == (baseline, False)


def test_observer_exception_cannot_break_provisioning(monkeypatch, fleet):
    def broken(*args, **kwargs):
        raise RuntimeError("broken experiment")
    monkeypatch.setattr(vpn, "observe_selection", broken)
    assert vpn._select_server(None, None, None) is fleet[0]
    assert vpn._select_server(None, None, fleet[1].server_id) is fleet[1]


def test_explicit_choice_is_preserved(monkeypatch, fleet):
    calls = []
    monkeypatch.setattr(vpn, "observe_selection", lambda *args, **kwargs: calls.append(kwargs))
    assert vpn._select_server(None, None, fleet[1].server_id) is fleet[1]
    assert calls == [{"explicit": True}]


def test_invalid_or_ineligible_explicit_choice_still_rejected(monkeypatch, fleet):
    monkeypatch.setattr(vpn, "observe_selection", lambda *_args, **_kwargs: pytest.fail("observed forbidden selection"))
    monkeypatch.setattr(vpn.VPNServerService, "get_server_by_id", lambda *_: server("forbidden"))
    with pytest.raises(HTTPException) as exc:
        vpn._select_server(None, None, "forbidden")
    assert exc.value.status_code == 404


def test_empty_fleet_still_returns_unavailable(monkeypatch):
    monkeypatch.setattr(vpn, "_active_wireguard_servers", lambda *_: [])
    with pytest.raises(HTTPException) as exc:
        vpn._select_server(None, None, None)
    assert exc.value.status_code == 503


@pytest.mark.parametrize("mode", ["off", "shadow", "invalid"])
def test_actual_observer_missing_artifacts_preserves_baseline(monkeypatch, fleet, mode):
    monkeypatch.setenv("SECUREWAVE_ROUTING_SHADOW", mode)
    monkeypatch.delenv("SECUREWAVE_ROUTING_SNAPSHOT", raising=False)
    monkeypatch.delenv("SECUREWAVE_ROUTING_POLICY", raising=False)
    assert vpn._select_server(None, None, None) is fleet[0]
