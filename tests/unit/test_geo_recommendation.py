from datetime import datetime

import pytest

from models.vpn_server import VPNServer
from models.vpn_server_rtt_sample import VPNServerRTTSample


def _seed_server(
    db,
    *,
    server_id: str,
    region: str,
    latency_ms: float,
    current_connections: int = 0,
    max_connections: int = 1000,
    health_status: str = "healthy",
) -> VPNServer:
    server = VPNServer(
        server_id=server_id,
        location="Test",
        country="Testland",
        country_code="TT",
        city="Test City",
        region=region,
        hcloud_location="ash",
        public_ip="203.0.113.100",
        endpoint="203.0.113.100:51820",
        wg_public_key="dGVzdC1zZXJ2ZXItcHVibGljLWtleS1iYXNlNjQ=",
        wg_private_key_encrypted="encrypted-test-key",
        status="active",
        health_status=health_status,
        hcloud_server_state="running",
        max_connections=max_connections,
        current_connections=current_connections,
        performance_score=90.0,
        latency_ms=latency_ms,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _seed_rtt_samples(db, *, server: VPNServer, values: list[float]) -> None:
    for value in values:
        db.add(
            VPNServerRTTSample(
                vpn_server_id=server.id,
                observed_at=datetime.utcnow(),
                rtt_ms=float(value),
                source="test",
            )
        )
    db.commit()


def test_recommended_server_prefers_rolling_rtt_over_server_latency(client, auth_headers, db, monkeypatch):
    """
    The geo recommendation must use rolling RTT history when enough samples exist,
    even if VPNServer.latency_ms is stale/noisy.
    """
    # Force rollup to be used (5 samples minimum).
    monkeypatch.setenv("SECUREWAVE_GEO_RECO_RTT_MIN_SAMPLES", "5")
    monkeypatch.setenv("SECUREWAVE_GEO_RECO_RTT_WINDOW_SECONDS", str(60 * 60))

    slow_but_good = _seed_server(db, server_id="us-east-1-001", region="Americas", latency_ms=200.0)
    fast_but_bad = _seed_server(db, server_id="eu-west-1-001", region="Europe", latency_ms=30.0)

    _seed_rtt_samples(db, server=slow_but_good, values=[20, 21, 22, 23, 24])
    _seed_rtt_samples(db, server=fast_but_bad, values=[140, 145, 150, 155, 160])

    resp = client.get(
        "/api/vpn/recommended-server?region=barbados&include_candidates=true",
        headers=auth_headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["recommended_server_id"] == "us-east-1-001"
    assert body["baselines"]["source"] in {"geo_latency_probe", "env_fallback"}


def test_recommended_server_uses_geo_latency_probe_outputs(client, auth_headers, db, monkeypatch, tmp_path):
    server = _seed_server(db, server_id="us-east-1-001", region="Americas", latency_ms=40.0)
    _seed_rtt_samples(db, server=server, values=[40, 41, 42, 43, 44])

    report = tmp_path / "geo_latency_report.json"
    report.write_text(
        """{
  "harness": "geo_latency_probe",
  "generated_at": "2026-02-13T00:00:00Z",
  "summary": [
    {"region": "barbados", "avg_ms": 101.0},
    {"region": "europe", "avg_ms": 140.0}
  ]
}
""",
        encoding="utf-8",
    )
    monkeypatch.setenv("SECUREWAVE_GEO_LATENCY_REPORT_PATH", str(report))
    monkeypatch.setenv("SECUREWAVE_GEO_RECO_RTT_MIN_SAMPLES", "5")
    monkeypatch.setenv("SECUREWAVE_GEO_RECO_RTT_WINDOW_SECONDS", str(60 * 60))

    resp = client.get("/api/vpn/recommended-server?include_candidates=false", headers=auth_headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["baselines"]["source"] == "geo_latency_probe"
    assert body["baselines"]["barbados_ms"] == pytest.approx(101.0)
    assert body["baselines"]["europe_ms"] == pytest.approx(140.0)

