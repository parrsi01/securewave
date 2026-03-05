def test_canonical_vpn_router_endpoints_are_mounted(
    client, auth_headers, test_subscription, test_vpn_server
):

    servers = client.get("/api/vpn/servers", headers=auth_headers)
    assert servers.status_code == 200, servers.text

    regions = client.get("/api/vpn/regions", headers=auth_headers)
    assert regions.status_code == 200, regions.text

    # /api/vpn/profile is a POST-only control-plane endpoint in the canonical router.
    profile = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={
            "device_name": "Router Mount Test",
            "device_type": "linux",
            "server_id": test_vpn_server.server_id,
            "protocol": "wireguard",
        },
    )
    assert profile.status_code == 200, profile.text

    schema = client.get("/api/openapi.json")
    assert schema.status_code == 200, schema.text
    paths = schema.json()["paths"]
    assert "/api/vpn/meter/start" in paths
    assert "/api/vpn/meter/stop" in paths
    assert "/api/vpn/meter/usage/{user_id}" in paths
    assert "/api/vpn/shaping/start" in paths
    assert "/api/vpn/shaping/stop" in paths
