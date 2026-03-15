from models.vpn_metric import VPNMetric


def test_submit_vpn_metric_persists_database_record(client, auth_headers, test_user, db):
    response = client.post(
        "/api/vpn/metrics",
        headers=auth_headers,
        json={
            "server_id": "us-east-1-001",
            "device_id": 7,
            "handshake_time_ms": 135.0,
            "latency_ms": 42.5,
            "packet_loss_pct": 0.5,
            "throughput_mbps": 88.4,
            "protocol": "wireguard",
        },
    )
    assert response.status_code == 201, response.text
    payload = response.json()
    assert payload["status"] == "ok"

    metric = db.query(VPNMetric).filter(VPNMetric.id == payload["metric_id"]).first()
    assert metric is not None
    assert metric.user_id == test_user.id
    assert metric.server_id == "us-east-1-001"
    assert metric.device_id == 7
    assert metric.handshake_time_ms == 135.0
    assert metric.latency_ms == 42.5
    assert metric.packet_loss_pct == 0.5
    assert metric.throughput_mbps == 88.4


def test_admin_metrics_aggregation_requires_admin_and_returns_rollups(
    client, auth_headers, admin_auth_headers, test_user, db
):
    samples = [
        {
            "server_id": "us-east-1-001",
            "handshake_time_ms": 100.0,
            "latency_ms": 40.0,
            "packet_loss_pct": 1.0,
            "throughput_mbps": 90.0,
        },
        {
            "server_id": "us-east-1-001",
            "handshake_time_ms": 200.0,
            "latency_ms": 60.0,
            "packet_loss_pct": 3.0,
            "throughput_mbps": 70.0,
        },
        {
            "server_id": "eu-west-1-001",
            "handshake_time_ms": 300.0,
            "latency_ms": 80.0,
            "packet_loss_pct": 5.0,
            "throughput_mbps": 50.0,
        },
    ]
    for sample in samples:
        response = client.post("/api/vpn/metrics", headers=auth_headers, json=sample)
        assert response.status_code == 201, response.text

    forbidden = client.get("/api/admin/vpn-metrics", headers=auth_headers)
    assert forbidden.status_code == 403

    aggregated = client.get("/api/admin/vpn-metrics?hours=24", headers=admin_auth_headers)
    assert aggregated.status_code == 200, aggregated.text
    payload = aggregated.json()

    rows = {row["server_id"]: row for row in payload["servers"]}
    assert payload["window_hours"] == 24
    assert rows["us-east-1-001"]["sample_count"] == 2
    assert rows["us-east-1-001"]["avg_handshake_ms"] == 150.0
    assert rows["us-east-1-001"]["avg_latency_ms"] == 50.0
    assert rows["us-east-1-001"]["avg_packet_loss_pct"] == 2.0
    assert rows["us-east-1-001"]["avg_throughput_mbps"] == 80.0
    assert rows["eu-west-1-001"]["sample_count"] == 1
    assert rows["eu-west-1-001"]["avg_latency_ms"] == 80.0


def test_submit_vpn_metric_rejects_invalid_payload(client, auth_headers):
    response = client.post(
        "/api/vpn/metrics",
        headers=auth_headers,
        json={
            "server_id": "us-east-1-001",
            "latency_ms": 20000,
        },
    )
    assert response.status_code == 422
