def _create_fake_hetzner_server(db):
    from models.vpn_server import VPNServer

    server = VPNServer(
        server_id="securewave-real-sim-01",
        location="Ashburn, US",
        country="US",
        country_code="US",
        city="Ashburn",
        region="Americas",
        hcloud_location="ash",
        hcloud_server_id="sim",
        hcloud_server_name="securewave-real-sim-01",
        hcloud_server_type="cx33",
        hcloud_server_state="running",
        public_ip="203.0.113.10",
        endpoint="203.0.113.10:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5LXJlYWwtc2lt",
        wg_private_key_encrypted="",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_real_profile_does_not_include_demo_prefix(client, auth_headers, db):
    _create_fake_hetzner_server(db)

    resp = client.post(
        "/api/vpn/profile",
        json={"device_name": "Real Mode Device", "device_type": "android", "protocol": "wireguard"},
        headers=auth_headers,
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()

    cfg = data.get("wireguard_config") or ""
    assert "[Interface]" in cfg
    assert "[Peer]" in cfg
    assert "Endpoint = 203.0.113.10:51820" in cfg
    assert "PublicKey = dGVzdC1wdWJsaWMta2V5LXJlYWwtc2lt" in cfg

    # In real mode we must not mislabel the profile as demo.
    assert "SecureWave VPN DEMO CONFIG" not in cfg

    # AUTO_REGISTER_PEERS is disabled in tests_real; profile should still be issued.
    assert data.get("peer_registered") is False

    # Ensure it looks like a WireGuard config, not arbitrary JSON.
    assert "PrivateKey =" in cfg
