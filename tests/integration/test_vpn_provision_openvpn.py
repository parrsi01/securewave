import pytest

from tests.integration.test_vpn_credentials import _create_openvpn_server


@pytest.mark.offline
def test_openvpn_provision_uses_stub_mode_and_reuses_existing_material(client, auth_headers, db, monkeypatch):
    server = _create_openvpn_server(db)
    monkeypatch.setenv("SECUREWAVE_TEST_ENFORCE_RUNTIME_CHECKS", "true")
    monkeypatch.setenv("SECUREWAVE_PROVISIONING_MODE", "local_stub")

    payload = {
        "protocol": "openvpn",
        "device_name": "Stub Linux",
        "device_type": "linux",
        "server_id": server.server_id,
    }

    first = client.post("/api/vpn/credentials/provision", headers=auth_headers, json=payload)
    assert first.status_code == 200, first.text
    body1 = first.json()
    profile1 = body1["profile"]
    assert profile1["type"] == "openvpn"
    assert profile1["auth_method"] == "mtls"
    assert "remote 10.10.10.10 1194" in profile1["ovpn_config"]
    assert "BEGIN CERTIFICATE" in profile1["ovpn_config"]

    second = client.post("/api/vpn/credentials/provision", headers=auth_headers, json=payload)
    assert second.status_code == 200, second.text
    body2 = second.json()
    profile2 = body2["profile"]
    assert body2["credential"]["username"] == body1["credential"]["username"]
    assert body2["credential"]["revision"] == body1["credential"]["revision"]
    assert profile2["ovpn_config"] == profile1["ovpn_config"]
