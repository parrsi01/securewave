from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "monitor_production_health.sh"
SERVICE = ROOT / "infrastructure" / "systemd" / "securewave-health-monitor.service"
TIMER = ROOT / "infrastructure" / "systemd" / "securewave-health-monitor.timer"


def test_health_monitor_is_read_only_and_uses_existing_routes():
    source = SCRIPT.read_text(encoding="utf-8")

    for endpoint in ("/api/health", "/api/ready", "/downloads/manifest.json"):
        assert endpoint in source

    forbidden = (
        "git reset",
        "iptables",
        "nft ",
        "systemctl enable",
        "systemctl restart",
        "docker compose up",
        "ssh ",
        "Authorization:",
        "/api/vpn/connect",
        "/api/vpn/disconnect",
    )
    for token in forbidden:
        assert token not in source


def test_health_monitor_fails_closed_on_publication_contract():
    source = SCRIPT.read_text(encoding="utf-8")

    assert 'entry.get("status") != "available"' in source
    assert 'entry.get("url") != "/downloads/securewave-linux-arm64.deb"' in source
    assert "checksum is missing or malformed" in source


def test_systemd_monitor_is_bounded_unprivileged_and_timer_driven():
    service = SERVICE.read_text(encoding="utf-8")
    timer = TIMER.read_text(encoding="utf-8")

    assert "Type=oneshot" in service
    assert "User=securewave" in service
    assert "NoNewPrivileges=true" in service
    assert "ProtectSystem=strict" in service
    assert "SECUREWAVE_HEALTH_TIMEOUT_SECONDS=8" in service
    assert "OnUnitActiveSec=5min" in timer
    assert "Unit=securewave-health-monitor.service" in timer
