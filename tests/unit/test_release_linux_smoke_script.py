from pathlib import Path


def test_release_linux_smoke_script_uses_real_mode_bridge_checks():
    script = Path(
        "securewave_app/scripts/run_release_linux_smoke_checks.sh"
    ).read_text(encoding="utf-8")

    assert "test/vpn_service_provider_test.dart" in script
    assert "test/channel_vpn_service_linux_bridge_test.dart" in script
    assert "--dart-define=SECUREWAVE_MOCK_VPN=false" in script
    assert "--dart-define=SECUREWAVE_SIM_MODE=false" in script
