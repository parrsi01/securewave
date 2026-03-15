"""
Tests for production readiness additions:
- ADMIN_API_KEY auth on server management endpoints
- /api/metrics unified fleet endpoint
- Prometheus fleet gauges
"""
from __future__ import annotations

import os
import pytest


# ---------------------------------------------------------------------------
# ADMIN_API_KEY auth on server management
# ---------------------------------------------------------------------------


class TestAdminApiKeyAuth:
    """Verify that the X-Admin-API-Key header grants admin access."""

    def test_api_key_accepted(self, client, db):
        os.environ["ADMIN_API_KEY"] = "test-secret-key-1234"
        try:
            resp = client.get(
                "/api/admin/servers/",
                headers={"X-Admin-API-Key": "test-secret-key-1234"},
            )
            # 200 = server list returned (empty fleet is fine)
            assert resp.status_code == 200
        finally:
            del os.environ["ADMIN_API_KEY"]

    def test_wrong_api_key_rejected(self, client, db):
        os.environ["ADMIN_API_KEY"] = "correct-key"
        try:
            resp = client.get(
                "/api/admin/servers/",
                headers={"X-Admin-API-Key": "wrong-key"},
            )
            assert resp.status_code == 403
        finally:
            del os.environ["ADMIN_API_KEY"]

    def test_no_auth_rejected(self, client, db):
        # No API key, no JWT → 401
        resp = client.get("/api/admin/servers/")
        assert resp.status_code == 401

    def test_jwt_admin_still_works(self, client, db, admin_auth_headers):
        resp = client.get(
            "/api/admin/servers/",
            headers=admin_auth_headers,
        )
        assert resp.status_code == 200

    def test_jwt_non_admin_rejected(self, client, db, auth_headers):
        resp = client.get(
            "/api/admin/servers/",
            headers=auth_headers,
        )
        assert resp.status_code == 403


# ---------------------------------------------------------------------------
# /api/metrics unified endpoint
# ---------------------------------------------------------------------------


class TestApiMetricsEndpoint:
    def test_requires_auth(self, client, db):
        resp = client.get("/api/metrics")
        assert resp.status_code == 401

    def test_returns_fleet_data(self, client, db, auth_headers):
        resp = client.get("/api/metrics", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "active_sessions" in data
        assert "active_tunnels" in data
        assert "fleet" in data
        fleet = data["fleet"]
        assert "total_servers" in fleet
        assert "healthy_servers" in fleet
        assert "total_connections" in fleet
        assert "avg_load_score" in fleet
        assert "capacity_pct" in fleet

    def test_empty_fleet_returns_zeros(self, client, db, auth_headers):
        resp = client.get("/api/metrics", headers=auth_headers)
        data = resp.json()
        assert data["active_sessions"] == 0
        assert data["active_tunnels"] == 0
        assert data["fleet"]["total_servers"] == 0

    def test_with_server_data(self, client, db, auth_headers):
        from models.vpn_server import VPNServer

        server = VPNServer(
            server_id="test-srv-1",
            location="Test",
            country="Testland",
            country_code="TT",
            city="Testville",
            hcloud_location="fsn1",
            public_ip="10.0.0.1",
            endpoint="10.0.0.1:51820",
            wg_public_key="key==",
            wg_private_key_encrypted="enc",
            status="active",
            health_status="healthy",
            hcloud_server_state="running",
            max_connections=100,
            current_connections=25,
            load_score=0.3,
        )
        db.add(server)
        db.commit()

        resp = client.get("/api/metrics", headers=auth_headers)
        data = resp.json()
        assert data["fleet"]["total_servers"] == 1
        assert data["fleet"]["healthy_servers"] == 1
        assert data["fleet"]["total_connections"] == 25
        assert data["fleet"]["avg_load_score"] == 0.3
        assert data["fleet"]["capacity_pct"] == 25.0


# ---------------------------------------------------------------------------
# Prometheus fleet gauges
# ---------------------------------------------------------------------------


class TestPrometheusFleetGauges:
    def test_metrics_endpoint_includes_fleet_gauges(self, client, db):
        resp = client.get("/metrics")
        assert resp.status_code == 200
        text = resp.text
        assert "securewave_active_sessions" in text
        assert "securewave_active_tunnels" in text
        assert "securewave_fleet_total_servers" in text
        assert "securewave_fleet_healthy_servers" in text
        assert "securewave_fleet_total_connections" in text
        assert "securewave_fleet_avg_load_score" in text

    def test_fleet_gauges_reflect_data(self, client, db):
        from models.vpn_server import VPNServer

        server = VPNServer(
            server_id="prom-test",
            location="Test",
            country="Testland",
            country_code="TT",
            city="Testville",
            hcloud_location="fsn1",
            public_ip="10.0.0.2",
            endpoint="10.0.0.2:51820",
            wg_public_key="key2==",
            wg_private_key_encrypted="enc",
            status="active",
            health_status="healthy",
            hcloud_server_state="running",
            max_connections=200,
            current_connections=50,
            load_score=0.25,
        )
        db.add(server)
        db.commit()

        resp = client.get("/metrics")
        text = resp.text
        assert "securewave_fleet_total_servers 1" in text
        assert "securewave_fleet_healthy_servers 1" in text
        assert "securewave_fleet_total_connections 50" in text


# ---------------------------------------------------------------------------
# RuntimeMetrics.export_prometheus with fleet param
# ---------------------------------------------------------------------------


class TestRuntimeMetricsFleetExport:
    def test_no_fleet_omits_fleet_gauges(self):
        from services.runtime_metrics import RuntimeMetrics

        metrics = RuntimeMetrics()
        output = metrics.export_prometheus()
        assert "securewave_active_sessions" not in output

    def test_fleet_dict_adds_gauges(self):
        from services.runtime_metrics import RuntimeMetrics

        metrics = RuntimeMetrics()
        fleet = {
            "active_sessions": 42,
            "active_tunnels": 10,
            "total_servers": 3,
            "healthy_servers": 2,
            "total_connections": 150,
            "avg_load_score": 0.35,
        }
        output = metrics.export_prometheus(fleet=fleet)
        assert "securewave_active_sessions 42" in output
        assert "securewave_active_tunnels 10" in output
        assert "securewave_fleet_total_servers 3" in output
        assert "securewave_fleet_healthy_servers 2" in output
        assert "securewave_fleet_total_connections 150" in output
        assert "securewave_fleet_avg_load_score 0.35" in output
