"""Regression coverage for scoped OpenVPN profile credentials."""

from datetime import datetime, timedelta

from fastapi import status
from fastapi.testclient import TestClient
import pytest

from database.session import get_db
from models.openvpn_credential import OpenVpnCredential
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer


pytestmark = pytest.mark.skip(
    reason="OpenVPN credential lifecycle is deferred from the Linux WireGuard beta"
)


def _ready_openvpn_server(db, *, server_id: str = "openvpn-lifecycle-1"):
    now = datetime.utcnow()
    server = VPNServer(
        server_id=server_id,
        location="Lifecycle City",
        country="Testland",
        country_code="TS",
        city="Lifecycle City",
        public_ip="203.0.113.121",
        endpoint="203.0.113.121:51820",
        wg_public_key="lifecycle-server-public-key",
        wg_private_key_encrypted="encrypted-server-key",
        supports_openvpn=True,
        openvpn_endpoint="203.0.113.121",
        openvpn_port=1194,
        openvpn_transport="udp",
        openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIBtest\n-----END CERTIFICATE-----",
        status="active",
        health_status="healthy",
        last_health_check=now,
        hcloud_server_state="running",
        max_connections=100,
        current_connections=0,
        protocol_runtime_evidence={
            "openvpn": {
                "healthy": True,
                "authenticated": True,
                "observed_at": now.isoformat(),
                "data_plane_healthy": True,
                "data_plane_observed_at": now.isoformat(),
            }
        },
        openvpn_requires_client_cert=False,
        openvpn_supports_userpass=True,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _profile(client, headers, *, force_rotate=False, device_id=None):
    payload = {
        "device_name": "OpenVPN Lifecycle Laptop",
        "device_type": "linux",
        "protocol": "openvpn",
        "force_rotate_keys": force_rotate,
    }
    if device_id is not None:
        payload["device_id"] = device_id
    return client.post("/api/vpn/profile", headers=headers, json=payload)


def _client_from_ip(db, source_ip: str):
    from main import app

    def override_db():
        yield db

    app.dependency_overrides[get_db] = override_db
    return TestClient(
        app,
        raise_server_exceptions=False,
        client=(source_ip, 50000),
    )


def test_openvpn_credentials_are_encrypted_scoped_rotated_and_metered(
    client, db, auth_headers, test_user
):
    server = _ready_openvpn_server(db)

    first = _profile(client, auth_headers)
    assert first.status_code == status.HTTP_200_OK, first.text
    first_profile = first.json()
    assert first_profile["openvpn_username"].startswith("swovpn-")
    assert first_profile["openvpn_password"]
    assert "openvpn_password" not in first_profile["openvpn_config"]

    credential = db.query(OpenVpnCredential).one()
    assert credential.user_id == test_user.id
    assert credential.server_id == server.id
    assert credential.password_encrypted != first_profile["openvpn_password"]
    assert credential.password_hash != first_profile["openvpn_password"]
    device_id = first_profile["device_id"]

    # Repeated issuance reuses a still-valid scoped credential and does not
    # repoint the generic device record away from WireGuard state.
    repeated = _profile(client, auth_headers, device_id=device_id)
    assert repeated.status_code == status.HTTP_200_OK
    assert repeated.json()["openvpn_username"] == first_profile["openvpn_username"]
    assert repeated.json()["openvpn_password"] == first_profile["openvpn_password"]
    assert db.query(WireGuardPeer).filter(WireGuardPeer.id == device_id).one().server_id is None

    usage = client.post(
        "/api/vpn/usage/sessions/start",
        headers=auth_headers,
        json={
            "device_id": device_id,
            "server_id": server.server_id,
            "protocol": "openvpn",
            "idempotency_key": "openvpn-lifecycle-start-001",
        },
    )
    assert usage.status_code == status.HTTP_200_OK, usage.text

    rotated = _profile(client, auth_headers, force_rotate=True, device_id=device_id)
    assert rotated.status_code == status.HTTP_200_OK, rotated.text
    assert rotated.json()["openvpn_username"] != first_profile["openvpn_username"]
    old = db.query(OpenVpnCredential).filter(
        OpenVpnCredential.username == first_profile["openvpn_username"]
    ).one()
    assert old.revoked_at is not None and old.is_active is False


def test_openvpn_expiry_rotates_and_device_revocation_removes_credentials(
    client, db, auth_headers
):
    _ready_openvpn_server(db, server_id="openvpn-lifecycle-2")
    issued = _profile(client, auth_headers)
    assert issued.status_code == status.HTTP_200_OK
    device_id = issued.json()["device_id"]
    first_name = issued.json()["openvpn_username"]
    credential = db.query(OpenVpnCredential).filter(
        OpenVpnCredential.username == first_name
    ).one()
    credential.expires_at = datetime.utcnow() - timedelta(seconds=1)
    db.commit()

    renewed = _profile(client, auth_headers, device_id=device_id)
    assert renewed.status_code == status.HTTP_200_OK, renewed.text
    assert renewed.json()["openvpn_username"] != first_name

    revoked = client.delete(f"/api/vpn/devices/{device_id}", headers=auth_headers)
    assert revoked.status_code == status.HTTP_204_NO_CONTENT, revoked.text
    active = db.query(OpenVpnCredential).filter(
        OpenVpnCredential.device_id == device_id,
        OpenVpnCredential.is_active.is_(True),
    ).count()
    assert active == 0


def test_openvpn_profile_rolls_back_new_device_when_remote_credential_write_fails(
    client, db, auth_headers, monkeypatch, test_user
):
    _ready_openvpn_server(db, server_id="openvpn-remote-failure")

    class RejectingRemote:
        async def upsert_credential(self, *args, **kwargs):
            return False, "rejected"

        async def revoke_credential(self, *args, **kwargs):
            return True, "revoked"

    import services.openvpn_credential_manager as credential_manager

    monkeypatch.setattr(
        credential_manager,
        "get_openvpn_server_manager",
        lambda: RejectingRemote(),
    )
    response = _profile(client, auth_headers)
    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert db.query(OpenVpnCredential).count() == 0
    peer = db.query(WireGuardPeer).filter(WireGuardPeer.user_id == test_user.id).one()
    assert peer.server_id is None and peer.is_active is False


def test_openvpn_malformed_server_profile_never_creates_a_device(
    client, db, auth_headers, test_user
):
    server = _ready_openvpn_server(db, server_id="openvpn-invalid-profile")
    server.openvpn_transport = "udp; unsafe"
    db.commit()

    response = _profile(client, auth_headers)
    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert db.query(OpenVpnCredential).count() == 0
    assert (
        db.query(WireGuardPeer)
        .filter(WireGuardPeer.user_id == test_user.id)
        .count()
        == 0
    )


def test_openvpn_egress_proof_requires_changed_matching_source_and_active_credential(
    db, auth_headers, test_user
):
    server = _ready_openvpn_server(db, server_id="openvpn-egress-proof")
    baseline_client = _client_from_ip(db, "198.51.100.10")
    try:
        issued = _profile(baseline_client, auth_headers)
        assert issued.status_code == status.HTTP_200_OK, issued.text
        device_id = issued.json()["device_id"]
        baseline = baseline_client.post("/api/vpn/egress/baseline", headers=auth_headers)
        assert baseline.status_code == status.HTTP_200_OK, baseline.text
        baseline_fingerprint = baseline.json()["fingerprint"]
    finally:
        baseline_client.close()

    egress_client = _client_from_ip(db, server.public_ip)
    try:
        proof = egress_client.post(
            "/api/vpn/egress/verify",
            headers=auth_headers,
            json={
                "server_id": server.server_id,
                "device_id": device_id,
                "protocol": "openvpn",
                "baseline_fingerprint": baseline_fingerprint,
            },
        )
        assert proof.status_code == status.HTTP_200_OK, proof.text
        assert proof.json() == {"verified": True}
        db.refresh(server)
        assert server.protocol_runtime_evidence["openvpn"]["data_plane_healthy"] is True
        assert "data_plane_observed_at" in server.protocol_runtime_evidence["openvpn"]

        unchanged = egress_client.post("/api/vpn/egress/baseline", headers=auth_headers)
        assert unchanged.status_code == status.HTTP_200_OK
        no_movement = egress_client.post(
            "/api/vpn/egress/verify",
            headers=auth_headers,
            json={
                "server_id": server.server_id,
                "device_id": device_id,
                "protocol": "openvpn",
                "baseline_fingerprint": unchanged.json()["fingerprint"],
            },
        )
        assert no_movement.status_code == status.HTTP_200_OK
        assert no_movement.json() == {"verified": False}

        credential = db.query(OpenVpnCredential).one()
        credential.is_active = False
        credential.revoked_at = datetime.utcnow()
        db.commit()
        revoked = egress_client.post(
            "/api/vpn/egress/verify",
            headers=auth_headers,
            json={
                "server_id": server.server_id,
                "device_id": device_id,
                "protocol": "openvpn",
                "baseline_fingerprint": baseline_fingerprint,
            },
        )
        assert revoked.status_code == status.HTTP_403_FORBIDDEN
    finally:
        egress_client.close()
        from main import app

        app.dependency_overrides.clear()


def test_openvpn_egress_proof_accepts_independent_https_exit_for_cohosted_api(
    db, auth_headers
):
    server = _ready_openvpn_server(db, server_id="openvpn-cohost-proof")
    baseline_client = _client_from_ip(db, "198.51.100.10")
    try:
        issued = _profile(baseline_client, auth_headers)
        assert issued.status_code == status.HTTP_200_OK, issued.text
        baseline = baseline_client.post("/api/vpn/egress/baseline", headers=auth_headers)
        assert baseline.status_code == status.HTTP_200_OK, baseline.text
        device_id = issued.json()["device_id"]
        baseline_fingerprint = baseline.json()["fingerprint"]
    finally:
        baseline_client.close()

    client = _client_from_ip(db, "198.51.100.11")
    try:
        response = client.post(
            "/api/vpn/egress/verify",
            headers=auth_headers,
            json={
                "server_id": server.server_id,
                "device_id": device_id,
                "protocol": "openvpn",
                "baseline_fingerprint": baseline_fingerprint,
                "external_baseline_ip": "198.51.100.10",
                "external_exit_ip": server.public_ip,
            },
        )
        assert response.status_code == status.HTTP_200_OK, response.text
        assert response.json() == {"verified": True}
        db.refresh(server)
        assert server.protocol_runtime_evidence["openvpn"]["data_plane_healthy"] is True
    finally:
        client.close()
        from main import app

        app.dependency_overrides.clear()
