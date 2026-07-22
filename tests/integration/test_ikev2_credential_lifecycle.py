"""Regression coverage for scoped IKEv2 EAP profile credentials."""

from __future__ import annotations

import re
from datetime import datetime, timedelta

from fastapi import status
from fastapi.testclient import TestClient

from database.session import get_db
from models.ikev2_credential import Ikev2Credential
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer


def _ready_ikev2_server(db, *, server_id: str = "ikev2-lifecycle-1"):
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


def _profile(client, headers, *, force_rotate=False, device_id=None):
    payload = {
        "device_name": "IKEv2 Lifecycle Laptop",
        "device_type": "future-protocol-fixture",
        "protocol": "ikev2",
        "force_rotate_keys": force_rotate,
    }
    if device_id is not None:
        payload["device_id"] = device_id
    return client.post("/api/vpn/profile", headers=headers, json=payload)


def _config_credential(profile: dict[str, object]) -> tuple[str, str]:
    config = str(profile["ikev2_config"])
    username = re.search(r'eap_id = "(swikev2-[a-f0-9]{32})"', config)
    password = re.search(r'secret = "([A-Za-z0-9_-]{32,128})"', config)
    assert username and password
    return username.group(1), password.group(1)


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


def test_ikev2_credentials_are_encrypted_scoped_rotated_and_metered(
    client, db, auth_headers, test_user
):
    server = _ready_ikev2_server(db)

    first = _profile(client, auth_headers)
    assert first.status_code == status.HTTP_200_OK, first.text
    first_profile = first.json()
    first_name, first_password = _config_credential(first_profile)

    credential = db.query(Ikev2Credential).one()
    assert credential.username == first_name
    assert credential.user_id == test_user.id
    assert credential.server_id == server.id
    assert credential.password_encrypted != first_password
    device_id = first_profile["device_id"]

    repeated = _profile(client, auth_headers, device_id=device_id)
    assert repeated.status_code == status.HTTP_200_OK, repeated.text
    assert _config_credential(repeated.json()) == (first_name, first_password)
    assert db.query(WireGuardPeer).filter(WireGuardPeer.id == device_id).one().server_id is None

    usage = client.post(
        "/api/vpn/usage/sessions/start",
        headers=auth_headers,
        json={
            "device_id": device_id,
            "server_id": server.server_id,
            "protocol": "ikev2",
            "idempotency_key": "ikev2-lifecycle-start-001",
        },
    )
    assert usage.status_code == status.HTTP_200_OK, usage.text

    rotated = _profile(client, auth_headers, force_rotate=True, device_id=device_id)
    assert rotated.status_code == status.HTTP_200_OK, rotated.text
    rotated_name, _ = _config_credential(rotated.json())
    assert rotated_name != first_name
    old = db.query(Ikev2Credential).filter(Ikev2Credential.username == first_name).one()
    assert old.revoked_at is not None and old.is_active is False


def test_ikev2_expiry_rotates_and_device_revocation_removes_credentials(
    client, db, auth_headers
):
    _ready_ikev2_server(db, server_id="ikev2-lifecycle-2")
    issued = _profile(client, auth_headers)
    assert issued.status_code == status.HTTP_200_OK
    device_id = issued.json()["device_id"]
    first_name, _ = _config_credential(issued.json())
    credential = db.query(Ikev2Credential).filter(Ikev2Credential.username == first_name).one()
    credential.expires_at = datetime.utcnow() - timedelta(seconds=1)
    db.commit()

    renewed = _profile(client, auth_headers, device_id=device_id)
    assert renewed.status_code == status.HTTP_200_OK, renewed.text
    renewed_name, _ = _config_credential(renewed.json())
    assert renewed_name != first_name

    revoked = client.delete(f"/api/vpn/devices/{device_id}", headers=auth_headers)
    assert revoked.status_code == status.HTTP_204_NO_CONTENT, revoked.text
    assert (
        db.query(Ikev2Credential)
        .filter(
            Ikev2Credential.device_id == device_id,
            Ikev2Credential.is_active.is_(True),
        )
        .count()
        == 0
    )


def test_ikev2_profile_rolls_back_new_device_when_remote_credential_write_fails(
    client, db, auth_headers, monkeypatch, test_user
):
    _ready_ikev2_server(db, server_id="ikev2-remote-failure")

    class RejectingRemote:
        async def upsert_credential(self, *args, **kwargs):
            return False, "rejected"

        async def revoke_credential(self, *args, **kwargs):
            return True, "revoked"

    import services.ikev2_credential_manager as credential_manager

    monkeypatch.setattr(
        credential_manager,
        "get_ikev2_server_manager",
        lambda: RejectingRemote(),
    )
    response = _profile(client, auth_headers)
    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert db.query(Ikev2Credential).count() == 0
    peer = db.query(WireGuardPeer).filter(WireGuardPeer.user_id == test_user.id).one()
    assert peer.server_id is None and peer.is_active is False


def test_ikev2_egress_proof_requires_changed_matching_source_and_active_credential(
    db, auth_headers
):
    server = _ready_ikev2_server(db, server_id="ikev2-egress-proof")
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
                "protocol": "ikev2",
                "baseline_fingerprint": baseline_fingerprint,
            },
        )
        assert proof.status_code == status.HTTP_200_OK, proof.text
        assert proof.json() == {"verified": True}

        credential = db.query(Ikev2Credential).one()
        credential.is_active = False
        credential.revoked_at = datetime.utcnow()
        db.commit()
        revoked = egress_client.post(
            "/api/vpn/egress/verify",
            headers=auth_headers,
            json={
                "server_id": server.server_id,
                "device_id": device_id,
                "protocol": "ikev2",
                "baseline_fingerprint": baseline_fingerprint,
            },
        )
        assert revoked.status_code == status.HTTP_403_FORBIDDEN
    finally:
        egress_client.close()
        from main import app

        app.dependency_overrides.clear()
