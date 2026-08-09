from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_active_linux_surface_is_wireguard_only() -> None:
    active = [
        ROOT / "main.py",
        ROOT / "routes" / "auth.py",
        ROOT / "routes" / "vpn.py",
        ROOT / "services" / "jwt_service.py",
        ROOT / "services" / "vpn_peer_manager.py",
        ROOT / "services" / "wireguard_peer_lifecycle.py",
        ROOT / "services" / "wireguard_server_manager.py",
        ROOT / "services" / "wireguard_service.py",
        ROOT / "securewave_app" / "linux" / "helperd" / "securewave_helperd.cc",
        ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick",
    ]
    text = "\n".join(path.read_text() for path in active).lower()
    assert "openvpn" not in text
    assert "ikev2" not in text
    assert "strongswan" not in text


def test_release_requirements_and_package_are_small() -> None:
    requirements = (ROOT / "requirements_production.txt").read_text().lower()
    package_builder = (ROOT / "securewave_app" / "scripts" / "build_deb.sh").read_text().lower()
    assert "stripe" not in requirements
    assert "sendgrid" not in requirements
    assert "openvpn" not in package_builder
    assert "strongswan" not in package_builder
    assert "wireguard-tools" in package_builder
    assert "libgtk-3-0t64" in package_builder
    assert "libsecret-1-0" in package_builder
    assert "libegl1" in package_builder
    assert "libgles2" in package_builder
    assert "systemctl restart securewave-helper.service" in package_builder
    assert '[[ -s "$runtime_dir/helper.sock" ]]' in package_builder
    assert "seq 1 50" in package_builder
    assert "op=wireguard.cleanup" not in package_builder
    assert "refusing package removal" in package_builder
    assert "usr/share/securewave/release/source-sha" in package_builder


def test_linux_helper_is_one_wireguard_contract() -> None:
    helper = (ROOT / "securewave_app" / "linux" / "helperd" / "securewave_helperd.cc").read_text().lower()
    wrapper = (ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick").read_text().lower()
    contract = (ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick.contract").read_text().strip()
    assert contract == "13"
    assert '"wireguard.status"' in helper
    assert '"wireguard.counters"' in helper
    assert '"wireguard.up"' in helper
    assert '"wireguard.down"' in helper
    assert 'interface="sw-wg"' in wrapper
    assert "wg-quick" in wrapper
