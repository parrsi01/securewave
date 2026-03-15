from models.vpn_server import VPNServer


def _create_openvpn_server(db) -> VPNServer:
    server = VPNServer(
        server_id="cred-openvpn-1",
        location="Helsinki, FI",
        country="Finland",
        country_code="FI",
        city="Helsinki",
        region="Europe",
        hcloud_location="hel1",
        public_ip="10.10.10.10",
        endpoint="10.10.10.10:51820",
        wg_public_key="dGVzdC1jcmVkLW9wZW52cG4tc2VydmVyLXB1YmxpYy1rZXk=",
        wg_private_key_encrypted="encrypted-private-key",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
        supports_wireguard=True,
        supports_openvpn=True,
        openvpn_port=1194,
        openvpn_transport="udp",
        openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----",
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _create_ikev2_server(db) -> VPNServer:
    server = VPNServer(
        server_id="cred-ikev2-1",
        location="Helsinki, FI",
        country="Finland",
        country_code="FI",
        city="Helsinki",
        region="Europe",
        hcloud_location="hel1",
        public_ip="10.10.10.11",
        endpoint="10.10.10.11:51820",
        wg_public_key="dGVzdC1jcmVkLWlrZXYyLXNlcnZlci1wdWJsaWMta2V5",
        wg_private_key_encrypted="encrypted-private-key",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
        supports_wireguard=True,
        supports_ikev2=True,
        ikev2_remote_id="vpn.securewave.test",
        ikev2_ca_cert_pem="-----BEGIN CERTIFICATE-----\nTEST_IKEV2_CA_CERT_PLACEHOLDER\n-----END CERTIFICATE-----\n",
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_openvpn_credential_provision_list_revoke_rotate(client, auth_headers, db):
    server = _create_openvpn_server(db)

    provision = client.post(
        "/api/vpn/credentials/provision",
        headers=auth_headers,
        json={
            "protocol": "openvpn",
            "device_name": "Cred Laptop",
            "device_type": "windows",
            "server_id": server.server_id,
        },
    )
    assert provision.status_code == 200, provision.text
    body = provision.json()
    cred = body["credential"]
    profile = body["profile"]
    assert cred["protocol"] == "openvpn"
    assert cred["credential_type"] == "client_certificate"
    assert cred["cert_serial"]
    assert cred["revision"] >= 1
    assert profile["type"] == "openvpn"
    assert profile["auth_method"] == "mtls"

    list_resp = client.get("/api/vpn/credentials", headers=auth_headers)
    assert list_resp.status_code == 200, list_resp.text
    listed = list_resp.json()
    assert listed["total"] >= 1
    assert any(item["id"] == cred["id"] for item in listed["credentials"])

    revoke = client.post(f"/api/vpn/credentials/{cred['id']}/revoke", headers=auth_headers)
    assert revoke.status_code == 200, revoke.text
    revoked = revoke.json()["credential"]
    assert revoked["revoked_at"]

    rotate = client.post(f"/api/vpn/credentials/{cred['id']}/rotate", headers=auth_headers)
    assert rotate.status_code == 200, rotate.text
    rotated = rotate.json()
    assert rotated["status"] == "rotated"
    assert rotated["credential"]["revision"] >= cred["revision"]
    assert rotated["profile"]["auth_method"] == "mtls"


def test_ikev2_credential_provision_returns_eap_tls_bundle(client, auth_headers, db):
    server = _create_ikev2_server(db)

    provision = client.post(
        "/api/vpn/credentials/provision",
        headers=auth_headers,
        json={
            "protocol": "ikev2",
            "device_name": "Cred Phone",
            "device_type": "windows",
            "server_id": server.server_id,
        },
    )
    assert provision.status_code == 200, provision.text
    body = provision.json()
    cred = body["credential"]
    profile = body["profile"]
    assert cred["protocol"] == "ikev2"
    assert cred["credential_type"] == "client_certificate"
    assert profile["type"] == "ikev2"
    assert profile["auth_method"] == "eap-tls"
    assert profile["client_pkcs12_base64"]
    assert profile["client_pkcs12_password"]


def test_device_revoke_endpoint_revokes_linked_credentials(client, auth_headers, db):
    from models.vpn_credential import VPNCredential
    from models.wireguard_peer import WireGuardPeer

    server = _create_openvpn_server(db)

    provision = client.post(
        "/api/vpn/credentials/provision",
        headers=auth_headers,
        json={
            "protocol": "openvpn",
            "device_name": "Revoked Laptop",
            "device_type": "windows",
            "server_id": server.server_id,
        },
    )
    assert provision.status_code == 200, provision.text
    credential = provision.json()["credential"]
    device_id = credential["device_id"]

    revoke = client.post(f"/api/vpn/devices/{device_id}/revoke", headers=auth_headers)
    assert revoke.status_code == 204, revoke.text

    peer = db.query(WireGuardPeer).filter(WireGuardPeer.id == device_id).first()
    assert peer is not None
    assert peer.is_revoked is True
    assert peer.device_state == "revoked"

    record = db.query(VPNCredential).filter(VPNCredential.id == credential["id"]).first()
    assert record is not None
    assert record.revoked_at is not None
