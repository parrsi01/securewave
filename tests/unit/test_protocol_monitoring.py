import hashlib
from datetime import datetime

import pytest


def _server():
    # Register the related model before SQLAlchemy configures VPNServer's
    # relationship in a unit-only process.
    from models import (  # noqa: F401
        subscription,
        user,
        vpn_connection,
        wireguard_peer,
    )
    from models.vpn_server import VPNServer

    now = datetime.utcnow()
    return VPNServer(
        server_id="monitoring-test-1",
        location="test",
        country="Test",
        country_code="TS",
        city="Test",
        public_ip="203.0.113.10",
        endpoint="203.0.113.10:51820",
        wg_public_key="public-key",
        wg_private_key_encrypted="encrypted-key",
        status="active",
        supports_wireguard=True,
        health_status="healthy",
        last_health_check=now,
        max_connections=100,
        current_connections=0,
        hcloud_server_state="running",
    )


def test_protocol_evidence_records_failure_and_recovery_transitions():
    from services.protocol_availability_service import ProtocolAvailabilityService

    server = _server()
    now = datetime.utcnow()

    assert ProtocolAvailabilityService.record_evidence(
        server, "wireguard", healthy=True, observed_at=now, authenticated=True
    ) == "initial"
    assert ProtocolAvailabilityService.record_evidence(
        server,
        "wireguard",
        healthy=False,
        observed_at=now,
        failure_reason="probe_exception",
        authenticated=True,
    ) == "failed"
    assert ProtocolAvailabilityService.record_evidence(
        server, "wireguard", healthy=True, observed_at=now, authenticated=True
    ) == "recovered"

    evidence = server.protocol_runtime_evidence["wireguard"]
    assert evidence["transition"] == "recovered"
    assert "failure_reason" not in evidence
    assert "probe_exception" not in str(server.protocol_runtime_evidence)


def test_explicitly_unauthenticated_evidence_fails_closed():
    from services.protocol_availability_service import ProtocolAvailabilityService

    server = _server()
    now = datetime.utcnow()
    ProtocolAvailabilityService.record_evidence(
        server, "wireguard", healthy=True, observed_at=now, authenticated=False
    )

    readiness = ProtocolAvailabilityService(now=now).evaluate(server, "wireguard")
    assert readiness.enabled is False
    assert "protocol-specific" in readiness.reason


@pytest.mark.asyncio
async def test_runtime_evidence_persistence_rolls_back(monkeypatch):
    import services.vpn_health_monitor as monitor_module
    from services.vpn_health_monitor import VPNHealthMonitor

    class FailingSession:
        rolled_back = False

        def add(self, _server):
            return None

        def commit(self):
            raise RuntimeError("database details must not be retained")

        def rollback(self):
            self.rolled_back = True

    class FakeManager:
        async def health_check(self, _connection):
            return True, "private probe output"

    session = FailingSession()
    monkeypatch.setattr(monitor_module, "wg_mock_mode_enabled", lambda: False)
    monkeypatch.setattr(monitor_module, "get_wireguard_server_manager", lambda: FakeManager())
    monkeypatch.setattr(monitor_module, "server_connection_from_db", lambda _server: object())

    monitor = VPNHealthMonitor()
    monitor.db = session
    assert await monitor._probe_wireguard_runtime(_server()) is False
    assert session.rolled_back is True


def test_operational_diagnostics_is_admin_only_and_redacted(
    client, admin_auth_headers, auth_headers, db
):
    from models.vpn_server import VPNServer

    server = _server()
    server.protocol_runtime_evidence = {
        "wireguard": {
            "healthy": False,
            "authenticated": True,
            "observed_at": datetime.utcnow().isoformat(),
            "transition": "failed",
            "failure_reason": "probe_exception",
            "endpoint": "198.51.100.5:51820",
            "private_key": "must-not-appear",
        }
    }
    db.add(server)
    db.commit()

    denied = client.get("/api/diagnostics/operational", headers=auth_headers)
    assert denied.status_code == 403

    response = client.get(
        "/api/diagnostics/operational", headers=admin_auth_headers
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["servers"]
    serialized = str(body)
    assert "must-not-appear" not in serialized
    assert "198.51.100.5" not in serialized
    assert "monitoring-test-1" not in serialized
    state = next(
        item for item in body["servers"]
        if item["server_ref"] == hashlib.sha256(b"monitoring-test-1").hexdigest()[:12]
    )
    assert state["protocols"]["wireguard"]["transition"] == "failed"
