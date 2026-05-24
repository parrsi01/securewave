from types import SimpleNamespace


def _server(server_id, city, country_code):
    return SimpleNamespace(
        server_id=server_id,
        location=city,
        country=city,
        country_code=country_code,
        city=city,
        region="Europe",
        public_ip="203.0.113.9",
        endpoint="203.0.113.9:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5LWJhc2U2NA==",
        wg_private_key_encrypted="encrypted",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
    )


def test_synthetic_bootstrap_aliases_are_hidden_outside_testing(monkeypatch):
    from services.vpn_server_service import VPNServerService

    monkeypatch.setenv("TESTING", "false")
    monkeypatch.delenv("SECUREWAVE_ALLOW_SYNTHETIC_SERVER_BOOTSTRAP", raising=False)

    servers = [
        _server("de-nue-1", "Nuremberg", "DE"),
        _server("de-fra-1", "Frankfurt", "DE"),
        _server("ch-zrh-1", "Zurich", "CH"),
        _server("fr-par-1", "Paris", "FR"),
        _server("nl-ams-1", "Amsterdam", "NL"),
    ]

    visible = VPNServerService._filter_synthetic_bootstrap_aliases(servers)

    assert [server.server_id for server in visible] == ["de-nue-1"]


def test_synthetic_bootstrap_aliases_can_be_explicitly_exposed(monkeypatch):
    from services.vpn_server_service import VPNServerService

    monkeypatch.setenv("TESTING", "false")
    monkeypatch.setenv("SECUREWAVE_ALLOW_SYNTHETIC_SERVER_BOOTSTRAP", "true")

    servers = [
        _server("de-nue-1", "Nuremberg", "DE"),
        _server("de-fra-1", "Frankfurt", "DE"),
    ]

    visible = VPNServerService._filter_synthetic_bootstrap_aliases(servers)

    assert [server.server_id for server in visible] == ["de-nue-1", "de-fra-1"]
