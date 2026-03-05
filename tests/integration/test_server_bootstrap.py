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
