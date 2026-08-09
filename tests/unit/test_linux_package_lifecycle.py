import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
BUILD_DEB = ROOT / "securewave_app/scripts/build_deb.sh"
HELPER_INSTALLER = ROOT / "securewave_app/scripts/install_linux_helper.sh"


def _maintainer_script(name: str) -> str:
    source = BUILD_DEB.read_text(encoding="utf-8")
    marker = f"cat <<'{name}' >"
    start = source.index(marker)
    body_start = source.index("\n", start) + 1
    body_end = source.index(f"\n{name}\n", body_start)
    return source[body_start:body_end] + "\n"


@pytest.mark.parametrize("name", ("PREINST", "POSTINST", "PRERM", "POSTRM"))
def test_generated_maintainer_scripts_are_valid_bash(name: str):
    result = subprocess.run(
        ["bash", "-n"],
        input=_maintainer_script(name),
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr


def test_package_dependencies_are_minimal_and_wireguard_only():
    source = BUILD_DEB.read_text(encoding="utf-8")

    assert (
        "Depends: wireguard-tools, iproute2, iptables, nftables, systemd, systemd-resolved"
        in source
    )
    for deferred in ("openvpn", "strongswan", "ikev2", "network-manager"):
        assert deferred not in source.lower()


def test_postinst_installs_root_owned_wireguard_helper_without_connect_prompts():
    source = _maintainer_script("POSTINST")

    assert "HELPER_DIR=/usr/local/libexec" in source
    assert '"$HELPER_DIR/securewave-helperd"' in source
    assert '"$HELPER_DIR/securewave-wg-quick"' in source
    assert "AUTH_DIR=/etc/securewave" in source
    assert "AUTH_FILE=$AUTH_DIR/helper-users" in source
    assert "groupadd --system \"$RUNTIME_GROUP\"" in source
    assert "systemctl enable --now securewave-helper.service" in source
    assert "sudo " not in source.lower()
    assert "pkexec" not in source.lower()


def test_prerm_cleans_wireguard_and_refuses_removal_with_active_interface():
    source = _maintainer_script("PRERM")

    assert "op=wireguard.cleanup" in source
    assert "ip link show dev sw-wg" in source
    assert "refusing package removal" in source
    for deferred in ("openvpn", "strongswan", "ikev2"):
        assert deferred not in source.lower()


def test_postrm_removes_only_package_owned_runtime_and_purges_allowlist():
    source = _maintainer_script("POSTRM")

    assert "securewave-helper.service" in source
    assert "/usr/local/libexec/securewave-helperd" in source
    assert "/usr/local/libexec/securewave-wg-quick" in source
    assert 'if [[ "${1:-}" == purge ]]' in source
    assert "rm -f /etc/securewave/helper-users" in source
    assert "groupdel securewave" in source
    for deferred in ("openvpn", "strongswan", "ikev2"):
        assert deferred not in source.lower()


def test_helper_installer_is_wireguard_only_and_does_not_install_apt_packages():
    source = HELPER_INSTALLER.read_text(encoding="utf-8")

    for required in (
        "wg",
        "wg-quick",
        "ip",
        "iptables",
        "nft",
        "systemctl",
        "securewave-helperd",
        "securewave-helper.service",
        "securewave-helper.tmpfiles",
        "SECUREWAVE_ALLOWED_USER",
    ):
        assert required in source
    assert "apt-get" not in source
    for deferred in ("openvpn", "strongswan", "ikev2", "network-manager"):
        assert deferred not in source.lower()


def test_package_source_marker_preserves_dirty_checkout_provenance():
    source = BUILD_DEB.read_text(encoding="utf-8")

    assert 'source_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"' in source
    assert 'git -C "$REPO_ROOT" status --porcelain --untracked-files=all' in source
    assert "dirty=true" in source
    assert "tracked_diff_sha256" in source
    assert "untracked_files_sha256" in source
    assert 'git -C "$REPO_ROOT" ls-files -z --others --exclude-standard' in source
    assert 'git -C "$REPO_ROOT" diff --binary HEAD' in source


def test_wireguard_helper_rejects_deferred_protocol_actions():
    helper = ROOT / "securewave_app/packaging/linux/securewave-wg-quick"
    result = subprocess.run(
        [str(helper), "probe", "openvpn"],
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 64
    assert "only WireGuard is supported" in result.stderr
