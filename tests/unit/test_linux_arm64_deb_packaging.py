from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "securewave_app"


def test_linux_deb_packaging_assets_exist():
    packaging_dir = APP / "packaging/linux"

    assert (APP / "linux/helperd/securewave_helperd.cc").is_file()
    assert (APP / "scripts/install_linux_helper.sh").is_file()
    assert (packaging_dir / "securewave-wg-quick").is_file()
    assert (packaging_dir / "securewave-wg-quick.contract").read_text().strip() == "9"
    assert (packaging_dir / "securewave-helper.service").is_file()
    assert (packaging_dir / "securewave-helper.tmpfiles").is_file()


def test_build_deb_is_local_only_and_packages_helper_payload():
    script = (APP / "scripts/build_deb.sh").read_text()

    assert "securewave-helperd was not produced" in script
    assert "securewave-helper.service" in script
    assert "securewave-helper.tmpfiles" in script
    assert "securewave-wg-quick.contract" in script
    assert "wireguard-tools, openvpn" in script
    assert "network-manager-strongswan" in script
    assert "strongswan-swanctl" in script
    assert "Local package only; no release artifact was published" in script
    assert "static/downloads" not in script
    assert "update_download_manifest.py" not in script
