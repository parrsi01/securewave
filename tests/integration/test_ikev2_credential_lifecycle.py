"""IKEv2 remains fail-closed while its dedicated gateway is uncertified."""

from datetime import datetime

from fastapi import status

from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from models.ikev2_credential import Ikev2Credential


def _complete_ikev2_server(db, *, server_id: str = "ikev2-unavailable-1"):
    now = datetime.utcnow()
    server = VPNServer(
        server_id=server_id,
        location="Lifecycle City",
        country="Testland",
        country_code="TS",
        city="Lifecycle City",
        public_ip="203.0.113.122",
        endpoint="203.0.113.122",
        wg_public_key="lifecycle-server-public-key",
        wg_private_key_encrypted="encrypted-server-key",
        supports_ikev2=True,
        ikev2_remote_id="vpn.securewave.test",
        ikev2_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIBtest\n-----END CERTIFICATE-----",
        status="active",
        health_status="healthy",
        last_health_check=now,
        hcloud_server_state="running",
        max_connections=100,
        current_connections=0,
        protocol_runtime_evidence={
            "ikev2": {
                "healthy": True,
                "authenticated": True,
                "observed_at": now.isoformat(),
                "data_plane_healthy": True,
                "data_plane_observed_at": now.isoformat(),
            }
        },
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def test_complete_ikev2_server_never_issues_profile_or_credential(
    client, db, auth_headers
):
    server = _complete_ikev2_server(db)

    protocols = client.get("/api/vpn/protocols?device_type=linux", headers=auth_headers)
    assert protocols.status_code == status.HTTP_200_OK, protocols.text
    row = next(item for item in protocols.json()["protocols"] if item["protocol"] == "ikev2")
    assert row["enabled"] is False
    assert row["server_enabled"] is False
    assert row["platform_supported"] is False
    assert "unavailable" in row["reason"].lower()

    response = client.post(
        "/api/vpn/profile",
        headers=auth_headers,
        json={
            "device_name": "IKEv2 Lifecycle Laptop",
            "device_type": "linux",
            "protocol": "ikev2",
            "server_id": server.server_id,
        },
    )
    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert "unavailable" in response.text.lower()
    assert db.query(Ikev2Credential).count() == 0
    assert db.query(WireGuardPeer).count() == 0


def test_ikev2_egress_verification_is_blocked_without_active_runtime(
    client, db, auth_headers
):
    server = _complete_ikev2_server(db, server_id="ikev2-egress-blocked")
    response = client.post(
        "/api/vpn/egress/verify",
        headers=auth_headers,
        json={
            "server_id": server.server_id,
            "device_id": 1,
            "protocol": "ikev2",
            "baseline_fingerprint": "a" * 64,
        },
    )
    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert "unavailable" in response.text.lower()
