import pytest

from services import server_bootstrap


def test_bootstrap_rejects_placeholder_material_in_production(db, monkeypatch):
    from models.vpn_server import VPNServer

    monkeypatch.setenv("ENVIRONMENT", "production")

    with pytest.raises(RuntimeError, match="placeholder WireGuard credentials"):
        server_bootstrap.ensure_default_servers(db)

    assert db.query(VPNServer).count() == 0


def test_bootstrap_rejects_invalid_public_key_material(db, monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setattr(
        server_bootstrap,
        "_DEFAULT_SERVERS",
        (
            {
                "server_id": "bad-key-1",
                "location": "Test",
                "country": "Testland",
                "country_code": "TL",
                "city": "Test City",
                "region": "Test Region",
                "hcloud_location": "fsn1",
                "wg_public_key": "not-a-wireguard-key",
                "tier_restriction": None,
            },
        ),
    )

    with pytest.raises(RuntimeError, match="invalid WireGuard public key"):
        server_bootstrap.ensure_default_servers(db)
