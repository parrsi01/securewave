from __future__ import annotations

from datetime import datetime

from models.user import User
from models.vpn_metric import VPNMetric
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.hashing_service import hash_password
from tests.helpers.auth import auth_headers_for_user


def _seed_server(
    db,
    *,
    server_id: str,
    endpoint_ip: str,
    latency_ms: float,
    health_status: str = "healthy",
) -> VPNServer:
    server = VPNServer(
        server_id=server_id,
        location="Ashburn",
        country="United States",
        country_code="US",
        city="Ashburn",
        region="Americas",
        hcloud_location="ash",
        public_ip=endpoint_ip,
        endpoint=f"{endpoint_ip}:51820",
        wg_public_key="dGVzdC1iYWNrZW5kLW1hdHJpeC1zZXJ2ZXIta2V5LTAxMjM0NTY=",
        wg_private_key_encrypted="encrypted-private-key",
        allowed_ips="0.0.0.0/0, ::/0",
        status="active",
        health_status=health_status,
        hcloud_server_state="running",
        max_connections=1000,
        current_connections=0,
        performance_score=99.0,
        latency_ms=latency_ms,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _create_user(db, *, email: str) -> User:
    user = User(
        email=email,
        hashed_password=hash_password("MatrixPass123!"),
        email_verified=True,
        is_active=True,
        is_admin=False,
        subscription_status="active",
        created_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def test_vpn_metric_submission_persists_and_aggregates(
    client,
    auth_headers,
    admin_auth_headers,
    db,
    test_vpn_server,
):
    payloads = [
        {
            "server_id": test_vpn_server.server_id,
            "device_id": 101,
            "handshake_time_ms": 120.0,
            "latency_ms": 35.0,
            "packet_loss_pct": 1.5,
            "throughput_mbps": 88.0,
            "protocol": "wireguard",
        },
        {
            "server_id": test_vpn_server.server_id,
            "device_id": 101,
            "handshake_time_ms": 180.0,
            "latency_ms": 45.0,
            "packet_loss_pct": 2.5,
            "throughput_mbps": 92.0,
            "protocol": "wireguard",
        },
    ]

    for payload in payloads:
        response = client.post("/api/vpn/metrics", json=payload, headers=auth_headers)
        assert response.status_code == 201, response.text
        assert response.json()["status"] == "ok"

    stored = (
        db.query(VPNMetric)
        .filter(VPNMetric.server_id == test_vpn_server.server_id)
        .order_by(VPNMetric.id.asc())
        .all()
    )
    assert len(stored) == 2
    assert stored[0].latency_ms == 35.0
    assert stored[1].latency_ms == 45.0

    denied = client.get("/api/admin/vpn-metrics", headers=auth_headers)
    assert denied.status_code == 403

    aggregate = client.get(
        "/api/admin/vpn-metrics",
        params={"server_id": test_vpn_server.server_id, "hours": 24},
        headers=admin_auth_headers,
    )
    assert aggregate.status_code == 200, aggregate.text
    body = aggregate.json()
    assert body["window_hours"] == 24
    assert len(body["servers"]) == 1
    row = body["servers"][0]
    assert row["server_id"] == test_vpn_server.server_id
    assert row["sample_count"] == 2
    assert row["avg_latency_ms"] == 40.0
    assert row["avg_handshake_ms"] == 150.0
    assert row["avg_packet_loss_pct"] == 2.0


def test_diagnostics_telemetry_submission_appears_in_debug_session(client, auth_headers):
    response = client.post(
        "/api/diagnostics/telemetry",
        json={
            "latency_ms": 28.0,
            "packet_loss": 0.2,
            "jitter_ms": 1.2,
            "uptime_seconds": 600,
            "bytes_sent": 1024,
            "bytes_received": 4096,
            "server_id": "diag-ash-1",
            "connection_quality": "excellent",
        },
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "accepted"

    debug = client.get("/api/diagnostics/debug/session", headers=auth_headers)
    assert debug.status_code == 200, debug.text
    payload = debug.json()
    assert payload["telemetry_store_size"] >= 1
    latest = payload["recent_telemetry"][-1]
    assert latest["server_id"] == "diag-ash-1"
    assert latest["latency_ms"] == 28.0

    summary = client.get("/api/diagnostics/summary", headers=auth_headers)
    assert summary.status_code == 200, summary.text
    assert summary.json()["telemetry_enabled"] is True


def test_profile_requests_assign_unique_cidrs_across_multiple_users(client, db):
    server = _seed_server(
        db,
        server_id="cidr-load-ash-1",
        endpoint_ip="198.51.100.41",
        latency_ms=25.0,
    )

    users = [
        _create_user(db, email=f"profile-cidr-{index}@example.com")
        for index in range(4)
    ]

    peer_ids: list[int] = []
    for index, user in enumerate(users, start=1):
        response = client.post(
            "/api/vpn/profile",
            json={
                "device_name": f"CIDR Device {index}",
                "device_type": "linux",
                "server_id": server.server_id,
                "protocol": "wireguard",
            },
            headers=auth_headers_for_user(user),
        )
        assert response.status_code == 200, response.text
        peer_ids.append(int(response.json()["device_id"]))

    peers = (
        db.query(WireGuardPeer)
        .filter(WireGuardPeer.id.in_(peer_ids))
        .order_by(WireGuardPeer.id.asc())
        .all()
    )
    assert len(peers) == 4
    cidrs = [peer.ipv4_address for peer in peers]
    assert all(addr.endswith("/32") for addr in cidrs)
    assert len(set(cidrs)) == len(cidrs)


def test_recommended_server_excludes_unhealthy_nodes(client, auth_headers, db, monkeypatch):
    monkeypatch.setenv("SECUREWAVE_GEO_RECO_RTT_MIN_SAMPLES", "9999")
    monkeypatch.setenv("SECUREWAVE_GEO_RECO_RTT_WINDOW_SECONDS", str(60 * 60))

    healthy = _seed_server(
        db,
        server_id="healthy-latency-1",
        endpoint_ip="198.51.100.51",
        latency_ms=55.0,
        health_status="healthy",
    )
    _seed_server(
        db,
        server_id="unhealthy-fast-1",
        endpoint_ip="198.51.100.52",
        latency_ms=5.0,
        health_status="unhealthy",
    )

    response = client.get(
        "/api/vpn/recommended-server?include_candidates=true",
        headers=auth_headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["recommended_server_id"] == healthy.server_id
    candidates = body.get("candidates") or []
    assert all(item["server_id"] != "unhealthy-fast-1" for item in candidates)
