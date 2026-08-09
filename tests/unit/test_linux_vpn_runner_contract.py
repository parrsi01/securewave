from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "securewave_app/linux/runner/my_application.cc"
HELPER = ROOT / "securewave_app/packaging/linux/securewave-wg-quick"
HELPERD_SOURCE = ROOT / "securewave_app/linux/helperd/securewave_helperd.cc"
HELPER_CONTRACT = ROOT / "securewave_app/packaging/linux/securewave-wg-quick.contract"
HELPER_SERVICE = ROOT / "securewave_app/packaging/linux/securewave-helper.service"
HELPER_TMPFILES = ROOT / "securewave_app/packaging/linux/securewave-helper.tmpfiles"
BUILD_DEB = ROOT / "securewave_app/scripts/build_deb.sh"
HELPER_INSTALLER = ROOT / "securewave_app/scripts/install_linux_helper.sh"
LINUX_CMAKE = ROOT / "securewave_app/linux/CMakeLists.txt"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_linux_runner_uses_allowlisted_helper_socket_without_connect_prompts():
    source = _read(RUNNER)

    assert 'kHelperSocketPath = "/run/securewave/helper.sock"' in source
    assert 'kHelperDaemonPath = "/usr/local/libexec/securewave-helperd"' in source
    assert "helper_request(" in source
    assert "helper_operation(" in source
    assert "pkexec" not in source
    assert "sudo" not in source
    assert "g_spawn_async_with_pipes" not in source


def test_linux_runner_persists_wireguard_state_for_restart_cleanup():
    source = _read(RUNNER)

    assert "kActiveProtocolFileName" in source
    assert "persist_active_protocol" in source
    assert "load_active_protocol(state)" in source
    assert "g_file_get_contents(state->active_protocol_path" in source
    assert 'return g_strcmp0(protocol, "wireguard") == 0;' in source
    assert 'return "wireguard.up";' in source
    assert 'return "wireguard.down";' in source


def test_linux_runner_exposes_only_wireguard_through_public_protocol_gate():
    source = _read(RUNNER)

    gate = source.split("static gboolean supported_protocol", 1)[1].split(
        "static void handle_vpn_call", 1
    )[0]
    assert 'g_strcmp0(protocol, "wireguard") == 0' in gate
    assert 'g_strcmp0(protocol, "openvpn")' not in gate
    assert 'g_strcmp0(protocol, "ikev2")' not in gate


def test_helper_daemon_validates_only_wireguard_and_has_contract_socket():
    source = _read(HELPERD_SOURCE)

    assert 'kSocketPath = "/run/securewave/helper.sock"' in source
    assert 'kAllowedUsersPath = "/etc/securewave/helper-users"' in source
    assert 'kGroupName = "securewave"' in source
    assert "SO_PEERCRED" in source
    assert "UidAllowedByFile" in source
    assert 'static bool ValidateProtocol(const std::string& protocol)' in source
    validation = source.split(
        'static bool ValidateProtocol(const std::string& protocol)', 1
    )[1].split("}", 1)[0]
    assert 'protocol == "wireguard"' in validation
    assert 'protocol == "openvpn"' not in validation
    assert 'protocol == "ikev2"' not in validation
    assert (
        'Error("protocol_unavailable", "This Linux beta supports WireGuard only.")'
        in source
    )


def test_wireguard_helper_script_is_the_only_packaged_protocol_runtime():
    helper = _read(HELPER)
    build = _read(BUILD_DEB)
    installer = _read(HELPER_INSTALLER)

    assert "securewave-wg-quick probe wireguard" in helper
    assert "wireguard-transfer" in helper
    assert "openvpn-*|ikev2-*|xfrm-state" in helper
    assert "Depends: wireguard-tools, iproute2, iptables, nftables, systemd, systemd-resolved" in build
    assert "apt-get" not in installer
    for deferred in ("openvpn", "strongswan", "ikev2", "network-manager"):
        assert deferred not in build.lower()
        assert deferred not in installer.lower()


def test_linux_package_bundles_helper_contract_service_and_tmpfiles():
    build = _read(BUILD_DEB)
    cmake = _read(LINUX_CMAKE)
    service = _read(HELPER_SERVICE)
    tmpfiles = _read(HELPER_TMPFILES)

    for payload in (
        "securewave-helperd",
        "securewave-wg-quick",
        "securewave-wg-quick.contract",
        "securewave-helper.service",
        "securewave-helper.tmpfiles",
    ):
        assert payload in build
        assert payload in cmake
    assert "ExecStart=/usr/local/libexec/securewave-helperd" in service
    assert "User=root" in service
    assert "Group=securewave" in service
    assert "d /run/securewave 0750 root securewave -" in tmpfiles
    assert "securewave-strongswan-routing.conf" not in build
    assert "securewave-strongswan-routing.conf" not in cmake


def test_helper_contract_version_is_shared_by_packaged_payload():
    assert _read(HELPER_CONTRACT).strip() == "13"
    assert "const guint kContractVersion = 13;" in _read(HELPERD_SOURCE)
