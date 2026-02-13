def test_api_metrics_system_returns_expected_fields(client, auth_headers, db):
    resp = client.get("/api/metrics/system", headers=auth_headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert "timestamp" in body
    assert "runtime" in body
    assert "wireguard_peers" in body

    system = (body.get("runtime") or {}).get("system") or {}
    assert "process_memory_mb" in system
    assert "process_open_fds" in system
    assert "process_threads" in system
    assert "wg_processes" in system
    assert "zombie_processes" in system

    peers = body["wireguard_peers"]
    assert "zombie" in peers

