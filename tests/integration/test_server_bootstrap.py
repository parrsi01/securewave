from services import server_bootstrap
from services.server_bootstrap import ensure_default_servers


def test_ensure_default_servers_seeds_five_rows_and_is_idempotent(db):
    from models.vpn_server import VPNServer

    expected_ids = {
        "de-nue-1",
        "de-fra-1",
        "ch-zrh-1",
        "nl-ams-1",
        "fr-par-1",
    }

    ensure_default_servers(db)

    first_pass = db.query(VPNServer).order_by(VPNServer.server_id.asc()).all()
    assert len(first_pass) == 5
    assert {server.server_id for server in first_pass} == expected_ids

    ensure_default_servers(db)

    second_pass = db.query(VPNServer).order_by(VPNServer.server_id.asc()).all()
    assert len(second_pass) == 5
    assert {server.server_id for server in second_pass} == expected_ids
    assert len({server.server_id for server in second_pass}) == 5


def test_ensure_default_servers_applies_runtime_protocol_inventory(db, monkeypatch):
    from models.vpn_server import VPNServer

    monkeypatch.setattr(server_bootstrap, "_runtime_bootstrap_enabled", lambda: True)
    monkeypatch.setattr(server_bootstrap, "_detect_public_ip", lambda: "203.0.113.25")
    monkeypatch.setattr(
        server_bootstrap,
        "_detect_wireguard_public_key",
        lambda: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
    )
    monkeypatch.setattr(
        server_bootstrap,
        "_detect_openvpn_runtime",
        lambda host_ip: (
            True,
            host_ip,
            1194,
            "udp",
            "-----BEGIN CERTIFICATE-----\nOPENVPN-CA\n-----END CERTIFICATE-----",
        ),
    )
    monkeypatch.setattr(
        server_bootstrap,
        "_detect_ikev2_runtime",
        lambda host_ip: (
            True,
            "@vpn.runtime.example",
            "-----BEGIN CERTIFICATE-----\nIKEV2-CA\n-----END CERTIFICATE-----",
        ),
    )

    ensure_default_servers(db)

    rows = db.query(VPNServer).order_by(VPNServer.server_id.asc()).all()
    assert len(rows) == 5
    for row in rows:
        assert row.public_ip == "203.0.113.25"
        assert row.endpoint == "203.0.113.25:51820"
        assert row.wg_public_key == "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
        assert row.wg_private_key_encrypted == ""
        assert row.supports_openvpn is True
        assert row.openvpn_endpoint == "203.0.113.25"
        assert row.openvpn_port == 1194
        assert row.openvpn_transport == "udp"
        assert "OPENVPN-CA" in (row.openvpn_ca_cert_pem or "")
        assert row.supports_ikev2 is True
        assert row.ikev2_remote_id == "@vpn.runtime.example"
        assert "IKEV2-CA" in (row.ikev2_ca_cert_pem or "")
