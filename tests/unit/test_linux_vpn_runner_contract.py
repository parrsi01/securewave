from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_DEB = ROOT / "securewave_app" / "scripts" / "build_deb.sh"
CMAKE = ROOT / "securewave_app" / "linux" / "CMakeLists.txt"
PACKAGING = ROOT / "securewave_app" / "packaging" / "linux"
RUNNER = ROOT / "securewave_app" / "linux" / "runner" / "my_application.cc"

REQUIRED_DEPENDS = {
    "wireguard-tools",
    "openvpn",
    "network-manager",
    "network-manager-strongswan",
    "strongswan",
    "strongswan-swanctl",
    "strongswan-charon",
    "libcharon-extra-plugins",
    "libstrongswan-extra-plugins",
    "iproute2",
    "iptables",
    "acl",
    "systemd",
}


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_linux_disconnect_can_clean_wireguard_residue_without_config_file():
    """A lost config must not make an existing sw-wg interface uncleanable."""
    runner = _read(RUNNER)

    assert '{"version", "1"}, {"op", "wireguard.cleanup"}' in runner


def test_linux_runner_registers_a_fail_closed_https_link_channel():
    runner = _read(RUNNER)

    assert 'const char* kLinksChannelName = "securewave/links";' in runner
    assert 'g_ascii_strcasecmp(scheme, "https") == 0' in runner
    assert '(!userinfo || *userinfo == \'\\0\')' in runner
    assert 'g_app_info_launch_default_for_uri(url, nullptr, &error)' in runner
    assert 'handle_links_call' in runner


def test_historical_runner_does_not_start_openvpn_without_authenticated_credentials():
    runner = _read(RUNNER)

    assert "OpenVPN is unavailable until authenticated current-source runtime and credential evidence is recorded." in runner
    openvpn_start = runner.index('if (g_strcmp0(protocol, "openvpn") == 0)')
    openvpn_end = runner.index('if (g_strcmp0(protocol, "ikev2") == 0)', openvpn_start)
    assert "openvpn.start" not in runner[openvpn_start:openvpn_end]


def test_openvpn_cleanup_contract_carries_auth_file_and_helper_requires_it():
    runner = _read(RUNNER)
    helperd = _read(ROOT / "securewave_app" / "linux" / "helperd" / "securewave_helperd.cc")

    assert '"op", "openvpn.cleanup"' in runner
    assert '"auth_path"' in runner[runner.index('"op", "openvpn.cleanup"'):runner.index('"op", "openvpn.cleanup"') + 260]
    assert 'op == "openvpn.cleanup" && auth_path.empty()' in helperd
    assert 'op == "openvpn.start"' in helperd
    assert "OpenVPN is unavailable until authenticated current-source runtime and credential evidence is recorded." in helperd


def test_linux_build_wires_helper_daemon_into_flutter_bundle():
    cmake = _read(CMAKE)

    assert "add_executable(securewave_helperd" in cmake
    assert '"helperd/securewave_helperd.cc"' in cmake
    assert 'OUTPUT_NAME "securewave-helperd"' in cmake
    assert 'install(TARGETS securewave_helperd' in cmake
    assert 'DESTINATION "${CMAKE_INSTALL_PREFIX}/packaging/linux"' in cmake
    assert "../scripts/install_linux_helper.sh" in cmake


def test_linux_deb_includes_helper_payload_and_runtime_dependencies():
    build = _read(BUILD_DEB)

    for payload in (
        "securewave-helperd",
        "securewave-wg-quick",
        "securewave-wg-quick.contract",
        "securewave-helper.service",
        "securewave-helper.tmpfiles",
        "securewave-helper.conf",
    ):
        assert payload in build

    depends_line = next(
        line for line in build.splitlines() if line.startswith("Depends: ")
    )
    declared = {
        package.strip()
        for package in depends_line.removeprefix("Depends: ").split(",")
    }
    assert REQUIRED_DEPENDS <= declared
    assert "dpkg-deb --root-owner-group --build" in build


def test_linux_deb_postinst_installs_helper_service_without_polkit_prompt_model():
    build = _read(BUILD_DEB)

    for install_target in (
        "HELPER=$HELPER_DIR/securewave-wg-quick",
        "HELPERD=$HELPER_DIR/securewave-helperd",
        "HELPER_CONTRACT=$HELPER_DIR/securewave-wg-quick.contract",
        "SERVICE_FILE=/etc/systemd/system/securewave-helper.service",
        "TMPFILES_FILE=/usr/lib/tmpfiles.d/securewave-helper.conf",
        "RUNTIME_GROUP=securewave",
        "RUNTIME_DIR=/run/securewave",
        "AUTH_FILE=$AUTH_DIR/helper-users",
    ):
        assert install_target in build

    assert 'groupadd --system "$RUNTIME_GROUP"' in build
    assert 'usermod -a -G "$RUNTIME_GROUP" "$user"' in build
    assert 'rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules' in build
    assert "systemctl daemon-reload" in build
    assert "systemctl enable --now securewave-helper.service" in build
    assert "systemctl restart securewave-helper.service" in build


def test_linux_deb_postrm_removes_helper_payload_and_socket():
    build = _read(BUILD_DEB)

    for removed in (
        "/run/securewave/helper.sock",
        "/usr/local/libexec/securewave-wg-quick.contract",
        "/usr/local/libexec/securewave-helperd",
        "/usr/local/libexec/securewave-wg-quick",
        "/etc/securewave/helper-users",
        "/etc/systemd/system/securewave-helper.service",
        "/usr/lib/tmpfiles.d/securewave-helper.conf",
    ):
        assert f"rm -f {removed}" in build


def test_linux_packaging_assets_are_tracked_inputs():
    for relative in (
        "securewave-wg-quick",
        "securewave-wg-quick.contract",
        "securewave-helper.service",
        "securewave-helper.tmpfiles",
    ):
        assert (PACKAGING / relative).is_file()
