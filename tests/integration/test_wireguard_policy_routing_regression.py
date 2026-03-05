from services.server_bootstrap import ensure_default_servers


def test_linux_wireguard_profile_keeps_policy_routing_guards(client, auth_headers, db):
    from models.vpn_server import VPNServer

    ensure_default_servers(db)
    server = db.query(VPNServer).filter(VPNServer.server_id == "de-nue-1").first()
    assert server is not None
    server.health_status = "healthy"
    db.add(server)
    db.commit()

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={
            "device_name": "Regression Linux Box",
            "device_type": "linux",
            "protocol": "wireguard",
            "server_id": "de-nue-1",
        },
    )

    assert response.status_code == 200, response.text
    config = response.json().get("wireguard_config", "")

    expected_fragments = (
        "wg set %i fwmark 51820",
        "ip rule add not fwmark 51820 table 51820 priority 32764",
        "ip rule add table main suppress_prefixlength 0 priority 32765",
        "ip route add default dev %i table 51820",
        "ip route flush table 51820",
    )
    missing = [fragment for fragment in expected_fragments if fragment not in config]

    assert not missing, (
        "WireGuard Linux policy-routing regression: missing required routing "
        f"lines in generated profile: {missing}"
    )
