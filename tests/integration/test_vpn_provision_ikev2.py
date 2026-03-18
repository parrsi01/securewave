import pytest

import routes.vpn as vpn_routes
import services.vpn_credential_service as vpn_credential_service
from tests.integration.test_vpn_credentials import _create_ikev2_server


@pytest.mark.offline
def test_ikev2_provision_uses_stub_mode_and_returns_full_tunnel_payload(client, auth_headers, db, monkeypatch):
    server = _create_ikev2_server(db)
    monkeypatch.setenv("SECUREWAVE_TEST_ENFORCE_RUNTIME_CHECKS", "true")
    monkeypatch.setenv("SECUREWAVE_PROVISIONING_MODE", "local_stub")

    payload = {
        "protocol": "ikev2",
        "device_name": "Stub Linux",
        "device_type": "linux",
        "server_id": server.server_id,
    }

    first = client.post("/api/vpn/credentials/provision", headers=auth_headers, json=payload)
    assert first.status_code == 200, first.text
    body1 = first.json()
    profile1 = body1["profile"]
    assert profile1["type"] == "ikev2"
    assert profile1["auth_method"] == "eap-mschapv2"
    assert profile1["server"] == "vpn.securewave.test"
    assert profile1["username"]
    assert profile1["password"]
    assert "BEGIN CERTIFICATE" in profile1["ca_cert_pem"]
    assert profile1["traffic_selectors"] == ["0.0.0.0/0"]
    assert profile1["proposals"]
    assert profile1["proposals"][0].startswith("ike=")

    second = client.post("/api/vpn/credentials/provision", headers=auth_headers, json=payload)
    assert second.status_code == 200, second.text
    body2 = second.json()
    profile2 = body2["profile"]
    assert body2["credential"]["username"] == body1["credential"]["username"]
    assert body2["credential"]["revision"] == body1["credential"]["revision"]
    assert profile2["password"] == profile1["password"]


@pytest.mark.offline
@pytest.mark.parametrize(
    ("stdout_body", "stderr_body", "expected_fragment"),
    [
        ("ikev2_issue_failed_stdout", "Warning: Permanently added '10.10.10.11' (ED25519) to the list of known hosts.", "stdout=ikev2_issue_failed_stdout"),
        ("", "Warning: Permanently added '10.10.10.11' (ED25519) to the list of known hosts.\nikev2_issue_failed_stderr", "stderr=ikev2_issue_failed_stderr"),
    ],
)
def test_ikev2_provision_fallback_surfaces_real_issue_client_failure(
    client,
    auth_headers,
    db,
    monkeypatch,
    stdout_body,
    stderr_body,
    expected_fragment,
):
    server = _create_ikev2_server(db)
    monkeypatch.setenv("TESTING", "false")
    monkeypatch.setenv("SECUREWAVE_ENFORCE_RUNTIME_CHECKS", "false")
    monkeypatch.setenv("SECUREWAVE_IKEV2_AUTH_MODE", "eap-tls")
    monkeypatch.setenv("SECUREWAVE_IKEV2_EAPTLS_FALLBACK_USERPASS", "true")
    monkeypatch.setattr(vpn_routes, "AUTO_PROVISION_CREDENTIALS", False)

    class _FakeSshManager:
        async def run_ssh_command(self, conn, command, *, stdin_data=None):
            assert "securewave-ikev2-issue-client" in command
            stdout = stdout_body
            if stdout:
                stdout += "\n"
            stdout += f"{vpn_credential_service._REMOTE_EXIT_MARKER}23"
            return True, stdout, stderr_body

    monkeypatch.setattr(
        vpn_credential_service,
        "get_wireguard_server_manager",
        lambda: _FakeSshManager(),
    )

    response = client.post(
        "/api/vpn/credentials/provision",
        headers=auth_headers,
        json={
            "protocol": "ikev2",
            "device_name": "Windows Cert Probe",
            "device_type": "windows",
            "server_id": server.server_id,
        },
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["profile"]["auth_method"] == "eap-mschapv2"
    assert body["status"].startswith("eap_tls_failed_fallback_userpass:")
    assert "exit_code=23" in body["status"]
    assert expected_fragment in body["status"]
    assert "Permanently added" not in body["status"]
