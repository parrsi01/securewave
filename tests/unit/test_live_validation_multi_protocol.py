from pathlib import Path
import importlib.util
import sys


def _load_module():
    root = Path(__file__).resolve().parents[2]
    module_path = root / "sandbox" / "live_validation_multi_protocol" / "run_validation.py"
    spec = importlib.util.spec_from_file_location("run_validation", module_path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_parse_declared_protocols_contains_desktop_multi_protocols():
    module = _load_module()
    root = Path(__file__).resolve().parents[2]
    capability_file = root / "securewave_app/lib/core/vpn/protocol_capabilities.dart"

    declared = module.parse_declared_protocols(capability_file)

    assert "wireguard" in declared["linux"]
    assert "openvpn" in declared["linux"]
    assert "ikev2" in declared["linux"]

    assert "wireguard" in declared["windows"]
    assert "openvpn" in declared["windows"]
    assert "ikev2" in declared["windows"]

    assert "wireguard" in declared["android"]
    assert "openvpn" not in declared["android"]
    assert "ikev2" not in declared["android"]


def test_validate_profile_claims_for_ikev2_requires_dns_off():
    module = _load_module()

    profile = {
        "dns": {
            "mode": "platform_default",
            "servers": [],
            "ad_malware_blocking": "off",
            "enforcement": "none",
        },
        "kill_switch": {
            "mode": "disabled",
            "enforcement": "none",
            "notes": "SecureWave does not enforce a kill switch for this protocol/platform.",
        },
    }

    dns_row, kill_row = module.validate_profile_claims("ikev2", "linux", profile)
    assert dns_row["result"] == "pass"
    assert kill_row["result"] == "pass"


def test_validate_profile_claims_for_linux_wireguard_requires_killswitch_hooks():
    module = _load_module()

    profile = {
        "dns": {
            "mode": "tunnel",
            "servers": ["94.140.14.14", "94.140.15.15"],
            "ad_malware_blocking": "on",
            "enforcement": "config",
        },
        "kill_switch": {
            "mode": "enabled",
            "enforcement": "wg-quick hooks",
            "notes": "Linux WireGuard profiles include wg-quick iptables hooks for kill-switch behavior.",
        },
    }

    dns_row, kill_row = module.validate_profile_claims("wireguard", "linux", profile)
    assert dns_row["result"] == "pass"
    assert kill_row["result"] == "pass"
