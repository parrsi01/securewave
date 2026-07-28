from pathlib import Path


RUNNER = Path("securewave_app/linux/runner/my_application.cc")
HELPER = Path("securewave_app/packaging/linux/securewave-wg-quick")
HELPERD_SOURCE = Path("securewave_app/linux/helperd/securewave_helperd.cc")
HELPER_CONTRACT = Path("securewave_app/packaging/linux/securewave-wg-quick.contract")
HELPER_SERVICE = Path("securewave_app/packaging/linux/securewave-helper.service")
HELPER_TMPFILES = Path("securewave_app/packaging/linux/securewave-helper.tmpfiles")
STRONGSWAN_ROUTING = Path(
    "securewave_app/packaging/linux/securewave-strongswan-routing.conf"
)
BUILD_DEB = Path("securewave_app/scripts/build_deb.sh")
BUILD_APPS = Path("scripts/build_apps.sh")
DOWNLOAD_INSTALLER = Path("static/downloads/install-linux.sh")
HELPER_INSTALLER = Path("securewave_app/scripts/install_linux_helper.sh")
LINUX_CMAKE = Path("securewave_app/linux/CMakeLists.txt")


def _runner_source() -> str:
    return RUNNER.read_text(encoding="utf-8")


def test_linux_runner_persists_active_protocol_for_restart_cleanup():
    source = _runner_source()

    assert "kActiveProtocolFileName" in source
    assert "persist_active_protocol" in source
    assert "persist_active_protocol(state, protocol)" in source
    assert "load_active_protocol(state)" in source
    assert "g_file_get_contents(state->active_protocol_path" in source


def test_runner_uses_helper_service_socket_without_connect_time_prompts():
    source = _runner_source()

    assert 'kHelperSocketPath = "/run/securewave/helper.sock"' in source
    assert 'kHelperDaemonPath = "/usr/local/libexec/securewave-helperd"' in source
    assert "helper_request(" in source
    assert "helper_operation(" in source
    assert 'helper_operation("probe", probe_args' in source
    assert "pkexec" not in source
    assert "sudo" not in source
    assert "g_spawn_async_with_pipes" not in source


def test_runner_rejects_missing_malformed_and_outdated_helper_contracts():
    source = _runner_source()

    assert "const std::string contract_field" in source
    assert "contract_end != contract_field.c_str()" in source
    assert "*contract_end == '\\0'" in source
    assert "contract_value <= G_MAXUINT" in source
    assert "if (!contract_valid)" in source
    assert "returned an invalid contract" in source
    assert "if (contract < kSecureWaveHelperContractVersion)" in source
    assert "contract > 0 && contract < kSecureWaveHelperContractVersion" not in source


def test_packaged_runner_is_single_instance_and_probe_uses_a_separate_id():
    source = _runner_source()
    cmake = LINUX_CMAKE.read_text(encoding="utf-8")

    assert "G_APPLICATION_HANDLES_COMMAND_LINE" in source
    assert "G_APPLICATION_NON_UNIQUE" not in source
    assert "gtk_widget_show(GTK_WIDGET(window))" in source
    assert 'if("$ENV{SECUREWAVE_RUNTIME_PROBE_BUILD}" STREQUAL "1")' in cmake
    assert 'set(APPLICATION_ID "com.example.securewave_app.runtime_probe")' in cmake


def test_runner_connect_disconnect_use_allowlisted_helper_operations():
    source = _runner_source()

    assert '"wireguard.up"' in source
    assert '"wireguard.down"' in source
    assert '"openvpn.start"' in source
    assert '"openvpn.stop"' in source
    assert '"ikev2.start"' in source
    assert '"ikev2.stop"' in source
    assert "run_helper_operation_async(" in source
    assert "connect_op_for_protocol(protocol)" in source
    assert "disconnect_op_for_protocol(protocol)" in source
    assert "write_config_file(method_call, state->config_path, config)" in source
    assert "g_chmod(path, 0600)" in source
    assert 'kOpenVpnAuthFileName = "securewave-openvpn.auth"' in source
    assert '"openvpn_username"' in source
    assert '"openvpn_password"' in source
    assert "write_openvpn_auth_file" in source


def test_helper_exposes_socket_only_openvpn_dns_revert_operation():
    source = HELPERD_SOURCE.read_text(encoding="utf-8")

    assert 'if (op == "openvpn.dns_revert")' in source
    assert 'RunHelper({"openvpn-dns-revert"})' in source


def test_runner_does_not_enable_secondary_protocols_from_local_tools_alone():
    source = _runner_source()

    assert 'return g_strcmp0(protocol, "wireguard") == 0;' in source
    assert '"OpenVPN and IKEv2 are Coming soon on Linux."' in source
    assert 'const gchar* protocols[] = {"wireguard"};' in source
    assert "g_unlink(state->active_protocol_path)" in source
    assert '"openvpn_helper_probe"' in source
    assert '"ikev2_helper_probe"' in source
    assert '"openvpn_available"' not in source
    assert '"ikev2_available"' not in source


def test_packaged_helper_exposes_secondary_protocol_cleanup_only():
    source = HELPERD_SOURCE.read_text(encoding="utf-8")

    assert "const bool kWireGuardOnlyRelease = true;" in source
    assert 'op != "openvpn.stop"' in source
    assert 'op != "openvpn.cleanup"' in source
    assert 'op != "openvpn.dns_revert"' in source
    assert 'op != "ikev2.stop"' in source
    assert 'op != "ikev2.cleanup"' in source
    assert "OpenVPN is unavailable in this WireGuard-only Linux release." in source
    assert "IKEv2 is unavailable in this WireGuard-only Linux release." in source


def test_linux_v1_runner_exposes_only_wireguard_to_flutter():
    source = _runner_source()

    assert 'static gboolean supported_protocol(const gchar* protocol) {\n  return g_strcmp0(protocol, "wireguard") == 0;\n}' in source
    assert 'const gchar* protocols[] = {"wireguard"};' in source
    assert 'if (g_strcmp0(stored, "wireguard") == 0)' in source
    assert 'g_unlink(state->active_protocol_path);' in source


def test_runner_exposes_runtime_status_and_traffic_stats_from_helper():
    source = _runner_source()

    assert 'g_strcmp0(method, "getStatus") == 0' in source
    assert 'g_strcmp0(method, "getTrafficStats") == 0' in source
    assert '"wireguard.counters"' in source
    assert '"wireguard.status"' in source
    assert '"openvpn.status"' in source
    assert '"ikev2.status"' in source
    assert '"counters_available"' in source
    assert '"unavailable_reason"' in source
    assert '"rx_bytes"' in source
    assert '"tx_bytes"' in source


def test_runner_reports_portable_ui_only_and_deb_runtime_install_state():
    source = _runner_source()

    assert "bundled_runtime_payload_available" in source
    assert "kBundledHelperScriptRelativePath" in source
    assert "kBundledHelperDaemonRelativePath" in source
    assert "kBundledHelperServiceRelativePath" in source
    assert "kBundledHelperTmpfilesRelativePath" in source
    assert 'g_strcmp0(method, "getRuntimeInstallState") == 0' in source
    assert 'g_strcmp0(method, "installRuntimeHelper") == 0' in source
    assert "runtime_install_requires_deb" in source
    assert (
        "Install the SecureWave .deb package for full no-prompt VPN routing" in source
    )
    assert "the app will not request administrator privileges at connect time" in source


def test_linux_package_installs_privileged_helper_service_and_dependencies():
    helper = HELPER.read_text(encoding="utf-8")
    helper_contract = HELPER_CONTRACT.read_text(encoding="utf-8").strip()
    build = BUILD_DEB.read_text(encoding="utf-8")

    assert (
        "securewave-wg-quick openvpn-start <config-path> <pid-path> <log-path> [auth-path]"
        in helper
    )
    assert "wireguard-transfer" in helper
    assert "xfrm-state" in helper
    assert "require_safe_config_path()" in helper
    assert "require_sw_wg_iface()" in helper
    assert 'if [[ "$iface" != "sw-wg" ]]' in helper
    assert '--log "$log_file"' in helper
    assert "prepare_owned_runtime_file" in helper
    assert 'prepare_owned_runtime_file "$pid_file" "pid" "$config"' in helper
    assert 'prepare_owned_runtime_file "$log_file" "log" "$config"' in helper
    assert helper_contract == "13"
    assert '--dev "$OPENVPN_INTERFACE"' in helper
    assert 'resolvectl dns "$OPENVPN_INTERFACE"' in helper
    assert "resolvectl domain \"$OPENVPN_INTERFACE\" '~.'" in helper
    assert 'resolvectl revert "$OPENVPN_INTERFACE"' in helper
    assert 'if [[ "$action" == "ikev2-set-dns" ]]' in helper
    assert "ipv4.ignore-auto-dns yes" in helper
    assert "ipv6.ignore-auto-dns yes" in helper
    assert "ipv4.dns-priority -50" in helper
    assert "ipv6.dns-priority -50" in helper
    assert "securewave-helper.service" in build
    assert "securewave-helper.tmpfiles" in build
    assert "securewave-helperd" in build
    assert "securewave-wg-quick.contract" in build
    assert "cp -f \"$ROOT_DIR/packaging/linux/securewave-strongswan-routing.conf\"" not in build
    assert "systemctl enable --now securewave-helper.service" in build
    assert "done < /etc/passwd" not in build
    assert "helper_request wireguard.cleanup" in build
    assert "helper_request ikev2.cleanup" in build
    assert "helper_request openvpn.dns_revert" in build
    assert '"$HELPERD" --request' in build
    assert "securewave\\.ovpn$" in build
    assert "groupdel securewave" in build
    assert "rm -f /run/securewave/helper.sock" in build
    assert (
        "Depends: wireguard-tools, iproute2, iptables, nftables, acl, systemd, systemd-resolved, libgtk-3-0, libsecret-1-0, libegl1, libgles2"
        in build
    )
    assert "strongswan-swanctl" not in build
    assert "strongswan-charon" not in build
    assert "rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules" in build
    assert "render_polkit_rule" not in build
    assert "find_strongswan_fwmark_conflict" not in build
    assert "charon_nm_running" in build
    assert "DEBIAN/preinst" in build
    assert "systemctl try-restart strongswan-starter.service" not in build
    assert "remove|purge" in build


def test_ikev2_helper_reconciles_only_unqualified_dual_stack_charon_nm_rules():
    helper = HELPER.read_text(encoding="utf-8")

    assert "clear_ikev2_unqualified_rule_family()" in helper
    assert "clear_ikev2_unqualified_rules()" in helper
    assert "clear_ikev2_route_state()" in helper
    assert "clear_ikev2_unqualified_rule_family -4" in helper
    assert "clear_ikev2_unqualified_rule_family -6" in helper
    assert 'IKEV2_ROUTING_TABLE=210' in helper
    assert 'IKEV2_ROUTING_PRIORITY=210' in helper
    assert (
        'ip "$family" rule del pref "$IKEV2_ROUTING_PRIORITY" from all table "$IKEV2_ROUTING_TABLE"'
        in helper
    )
    assert "refusing to alter mixed ${family} charon-nm policy rules" in helper
    assert "clear_ikev2_pref220_rules" not in helper
    assert "clear_ikev2_xfrm_routes" not in helper
    assert 'ip rule add pref 210 not fwmark "$fwmark" table 210' not in helper
    assert "clear_policy_state 0 0" in helper
    assert 'exec nmcli connection up id "$CONNECTION_NAME"' not in helper

    rule_block = helper.split("clear_ikev2_unqualified_rule_family() {", 1)[1].split(
        "clear_ikev2_unqualified_rules() {", 1
    )[0]
    assert "ip rule del not fwmark" not in rule_block
    assert 'priority="${IKEV2_ROUTING_PRIORITY}:"' in rule_block
    assert 'table="$IKEV2_ROUTING_TABLE"' in rule_block

    route_state_block = helper.split("clear_ikev2_route_state() {", 1)[1].split(
        "clear_policy_state() {", 1
    )[0]
    assert "clear_ikev2_unqualified_rules" in route_state_block
    assert "route del table 210" not in route_state_block

    up_block = helper.split('if [[ "$action" == "ikev2-up" ]]; then', 1)[1].split(
        "\nfi\n", 1
    )[0]
    assert up_block.count("clear_ikev2_route_state") == 2
    assert "clear_ikev2_unqualified_rules" in up_block
    assert up_block.index("clear_ikev2_route_state") < up_block.index(
        'nmcli connection up id "$CONNECTION_NAME"'
    )
    assert up_block.index("clear_ikev2_unqualified_rules") > up_block.index(
        'nmcli connection up id "$CONNECTION_NAME"'
    )

    down_block = helper.split('if [[ "$action" == "ikev2-down" ]]; then', 1)[1].split(
        "\nfi\n", 1
    )[0]
    delete_block = helper.split('if [[ "$action" == "ikev2-delete" ]]; then', 1)[
        1
    ].split("\nfi\n", 1)[0]
    assert "clear_ikev2_route_state" in down_block
    assert "clear_ikev2_route_state" in delete_block


def test_strongswan_routing_payload_pairs_socket_and_inverted_route_marks():
    routing = STRONGSWAN_ROUTING.read_text(encoding="utf-8")

    assert routing.count("fwmark = !0xdc") == 1
    assert routing.count("fwmark = 0xdc") == 1
    assert "charon {" not in routing
    assert "routing_table = 210" in routing
    assert "routing_table_prio = 210" in routing
    assert "charon-nm {" in routing
    assert "kernel-netlink {" in routing
    assert "socket-default {" in routing


def test_linux_tarball_and_installer_are_truthful_portable_ui_builds():
    build_apps = BUILD_APPS.read_text(encoding="utf-8")
    installer = DOWNLOAD_INSTALLER.read_text(encoding="utf-8")

    assert "Keep the helper payload in the archive" in build_apps
    assert 'cat > "$PACKAGE_STAGING/install-linux.sh"' in build_apps
    assert "SecureWave portable Linux package" in build_apps
    assert "Run ./install-linux.sh once with administrator authentication for VPN routing." in build_apps
    assert 'aarch64|arm64) ARCH_LABEL="arm64"' in build_apps
    assert 'TARBALL="$DOWNLOADS_DIR/securewave-linux-$ARCH_LABEL.tar.gz"' in build_apps
    assert 'ARCH_LABEL="x64";   FLUTTER_ARCH="arm64"' not in build_apps
    assert '"$INSTALL_DIR/scripts/install_linux_helper.sh"' in installer
    assert "SecureWave Linux app and helper service installed successfully." in installer
    assert (
        "pressing Connect should not ask for sudo, pkexec, or a password" in installer
    )
    assert 'aarch64|arm64) ARCH_LABEL="arm64"' in installer


def test_helper_installer_installs_service_socket_model():
    helper_installer = HELPER_INSTALLER.read_text(encoding="utf-8")

    assert "securewave-helperd" in helper_installer
    assert "securewave-helper.service" in helper_installer
    assert "securewave-helper.tmpfiles" in helper_installer
    assert "wireguard-tools" in helper_installer
    assert "packages+=(openvpn)" not in helper_installer
    assert "systemd-resolved" in helper_installer
    assert "nftables" in helper_installer
    assert "network-manager-strongswan" not in helper_installer
    assert "strongswan-swanctl" not in helper_installer
    assert "strongswan-charon" not in helper_installer
    assert "libcharon-extauth-plugins" not in helper_installer
    assert "libstrongswan-standard-plugins" not in helper_installer
    assert "libstrongswan-extra-plugins" not in helper_installer
    assert "acl" in helper_installer
    assert "SECUREWAVE_ALLOWED_USER" in helper_installer
    assert (
        'install -m 0755 "$SOURCE_HELPER_DAEMON" "$HELPER_DAEMON"' in helper_installer
    )
    assert 'install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"' in helper_installer
    assert "SOURCE_STRONGSWAN_ROUTING" not in helper_installer
    assert "find_strongswan_fwmark_conflict" not in helper_installer
    assert "charon_nm_running" not in helper_installer
    assert helper_installer.count("preflight_install") == 2
    calls = helper_installer.rsplit("install_systemd_service()", 1)[1]
    assert calls.index("preflight_install\ninstall_apt_dependencies") < (
        calls.index("ensure_runtime_group")
    )
    assert "systemctl try-restart strongswan-starter.service" not in helper_installer
    assert "systemctl enable --now securewave-helper.service" in helper_installer
    assert 'rm -f "$OLD_POLKIT_RULE"' in helper_installer


def test_flutter_linux_bundle_ships_deb_runtime_payload():
    cmake = LINUX_CMAKE.read_text(encoding="utf-8")

    assert "add_executable(securewave_helperd" in cmake
    assert "../packaging/linux/securewave-wg-quick" in cmake
    assert "../packaging/linux/securewave-wg-quick.contract" in cmake
    assert "../packaging/linux/securewave-helper.service" in cmake
    assert "../packaging/linux/securewave-helper.tmpfiles" in cmake
    assert "../packaging/linux/securewave-strongswan-routing.conf" not in cmake
    assert "../scripts/install_linux_helper.sh" in cmake
    assert 'DESTINATION "${CMAKE_INSTALL_PREFIX}/packaging/linux"' in cmake
    assert 'DESTINATION "${CMAKE_INSTALL_PREFIX}/scripts"' in cmake


def test_helper_service_owns_runtime_socket_path():
    service = HELPER_SERVICE.read_text(encoding="utf-8")
    tmpfiles = HELPER_TMPFILES.read_text(encoding="utf-8")

    assert "ExecStart=/usr/local/libexec/securewave-helperd" in service
    assert "User=root" in service
    assert "Group=securewave" in service
    assert "RuntimeDirectory=securewave" in service
    assert "RuntimeDirectoryMode=0750" in service
    assert "NoNewPrivileges=yes" in service
    assert "UMask=0077" in service
    assert "After=network-online.target NetworkManager.service" in service
    assert "strongswan-starter.service" not in service
    assert "d /run/securewave 0750 root securewave -" in tmpfiles
