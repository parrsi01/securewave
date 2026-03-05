from services.uptime_monitor import UptimeMonitorService


def test_check_all_vpn_servers_uses_current_vpn_server_fields(db, test_vpn_server, monkeypatch):
    monitor = UptimeMonitorService()

    def fake_check(server_ip: str, server_port: int = 51820) -> dict:
        return {
            "check_name": f"vpn_server_{server_ip}",
            "check_type": "udp",
            "target": f"{server_ip}:{server_port}",
            "is_up": True,
            "response_time_ms": 7,
            "error_message": None,
            "checked_at": None,
        }

    monkeypatch.setattr(monitor, "check_vpn_server", fake_check)

    results = monitor.check_all_vpn_servers()

    assert len(results) == 1
    check = results[0]
    assert check["target"] == f"{test_vpn_server.public_ip}:{test_vpn_server.wg_listen_port}"
    assert check["is_up"] is True
    assert check["metadata"] == {
        "server_id": test_vpn_server.server_id,
        "server_name": test_vpn_server.location,
        "location": test_vpn_server.location,
    }
