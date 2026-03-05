from __future__ import annotations

import routes.vpn as vpn_routes


class _StubTrafficManager:
    def __init__(self) -> None:
        self._stopped = False

    def start_meter(self, *, user_id, protocol, session_id=None, iface_hint=None) -> dict:
        return {
            "session_id": session_id or "stub-session",
            "user_id": int(user_id),
            "protocol": protocol,
            "iface": iface_hint or "stub0",
        }

    def stop_meter(self, session_id: str) -> dict:
        if self._stopped:
            return {"session_id": session_id, "stopped": False}
        self._stopped = True
        return {"session_id": session_id, "stopped": True}

    def current_session_usage(self, user_id: int, protocol=None) -> dict:
        return {
            "session_id": "stub-session",
            "protocol": protocol or "wireguard",
            "iface": "stub0",
            "rx_bytes": 10,
            "tx_bytes": 20,
        }

    def last_session_usage(self, user_id: int) -> dict:
        return {"session_id": "stub-session", "stopped": True}


class _StubTrafficShaper:
    def __init__(self) -> None:
        self._removed = False

    def apply_for_session(self, user_id: int, protocol: str, tier: str, session_id: str, iface_hint=None) -> dict:
        return {
            "session_id": session_id or "stub-shape",
            "user_id": int(user_id),
            "protocol": protocol,
            "tier": tier,
            "iface": iface_hint or "stub0",
            "shaped": False,
            "blocked": False,
        }

    def remove_for_session(self, session_id: str) -> dict:
        if self._removed:
            return {"session_id": session_id, "removed": False}
        self._removed = True
        return {"session_id": session_id, "removed": True, "shaped": False, "iface": "stub0"}


def test_meter_endpoints_return_503_when_manager_dependency_is_unavailable(client, monkeypatch):
    def _boom():
        raise RuntimeError("traffic manager missing")

    monkeypatch.setattr(vpn_routes, "get_traffic_manager", _boom)

    start = client.post("/api/vpn/meter/start", json={"user_id": 1, "protocol": "wireguard"})
    assert start.status_code == 503, start.text
    assert start.json()["error"]["code"] == "traffic_manager_unavailable"

    stop = client.post("/api/vpn/meter/stop", json={"session_id": "missing"})
    assert stop.status_code == 503, stop.text
    assert stop.json()["error"]["code"] == "traffic_manager_unavailable"

    usage = client.get("/api/vpn/meter/usage/1")
    assert usage.status_code == 503, usage.text
    assert usage.json()["error"]["code"] == "traffic_manager_unavailable"


def test_shaping_endpoints_return_503_when_shaper_dependency_is_unavailable(client, monkeypatch):
    def _boom():
        raise RuntimeError("traffic shaper missing")

    monkeypatch.setattr(vpn_routes, "get_traffic_shaper", _boom)

    start = client.post(
        "/api/vpn/shaping/start",
        json={"user_id": 1, "protocol": "wireguard", "tier": "free"},
    )
    assert start.status_code == 503, start.text
    assert start.json()["error"]["code"] == "traffic_shaper_unavailable"

    stop = client.post("/api/vpn/shaping/stop", json={"session_id": "missing"})
    assert stop.status_code == 503, stop.text
    assert stop.json()["error"]["code"] == "traffic_shaper_unavailable"


def test_meter_and_shaping_endpoints_succeed_with_minimal_stub_dependencies(client, monkeypatch):
    manager = _StubTrafficManager()
    shaper = _StubTrafficShaper()

    monkeypatch.setattr(vpn_routes, "get_traffic_manager", lambda: manager)
    monkeypatch.setattr(vpn_routes, "get_traffic_shaper", lambda: shaper)

    meter_start = client.post(
        "/api/vpn/meter/start",
        json={"user_id": 1, "protocol": "wireguard", "session_id": "stub-session"},
    )
    assert meter_start.status_code == 200, meter_start.text

    meter_usage = client.get("/api/vpn/meter/usage/1")
    assert meter_usage.status_code == 200, meter_usage.text
    usage_payload = meter_usage.json()
    assert usage_payload["current_session_usage"]["session_id"] == "stub-session"

    meter_stop = client.post("/api/vpn/meter/stop", json={"session_id": "stub-session"})
    assert meter_stop.status_code == 200, meter_stop.text
    assert meter_stop.json()["stopped"] is True

    shaping_start = client.post(
        "/api/vpn/shaping/start",
        json={"user_id": 1, "protocol": "wireguard", "tier": "free", "session_id": "stub-shape"},
    )
    assert shaping_start.status_code == 200, shaping_start.text

    shaping_stop = client.post("/api/vpn/shaping/stop", json={"session_id": "stub-shape"})
    assert shaping_stop.status_code == 200, shaping_stop.text
    assert shaping_stop.json()["removed"] is True
