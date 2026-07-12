from pathlib import Path


RUNNER = Path("securewave_app/linux/runner/my_application.cc")
HELPER = Path("securewave_app/packaging/linux/securewave-wg-quick")
HELPER_CONTRACT = Path("securewave_app/packaging/linux/securewave-wg-quick.contract")
HELPER_SERVICE = Path("securewave_app/packaging/linux/securewave-helper.service")
HELPER_TMPFILES = Path("securewave_app/packaging/linux/securewave-helper.tmpfiles")
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


def test_runner_allows_probe_launch_when_installed_app_is_already_running():
    source = _runner_source()

    assert "G_APPLICATION_HANDLES_COMMAND_LINE" in source
    assert "G_APPLICATION_NON_UNIQUE" in source
    assert "gtk_widget_show(GTK_WIDGET(window))" in source


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
    assert "Install the SecureWave .deb package for full no-prompt VPN routing" in source
    assert "the app will not request administrator privileges at connect time" in source


def test_linux_package_installs_privileged_helper_service_and_dependencies():
    helper = HELPER.read_text(encoding="utf-8")
    helper_contract = HELPER_CONTRACT.read_text(encoding="utf-8").strip()
    build = BUILD_DEB.read_text(encoding="utf-8")

    assert "securewave-wg-quick openvpn-start <config-path> <pid-path> <log-path> [auth-path]" in helper
    assert "wireguard-transfer" in helper
    assert "xfrm-state" in helper
    assert "require_safe_config_path()" in helper
    assert "require_sw_wg_iface()" in helper
    assert 'if [[ "$iface" != "sw-wg" ]]' in helper
    assert '--log "$log_file"' in helper
    assert "prepare_owned_runtime_file" in helper
    assert 'prepare_owned_runtime_file "$pid_file" "pid" "$config"' in helper
    assert 'prepare_owned_runtime_file "$log_file" "log" "$config"' in helper
    assert helper_contract == "10"
    assert "securewave-helper.service" in build
    assert "securewave-helper.tmpfiles" in build
    assert "securewave-helperd" in build
    assert "securewave-wg-quick.contract" in build
    assert "systemctl enable --now securewave-helper.service" in build
    assert "done < /etc/passwd" not in build
    assert '"$HELPER" policy-clear-link sw-wg' in build
    assert '"$HELPER" ikev2-delete' in build
    assert "securewave\\.ovpn$" in build
    assert 'groupdel securewave' in build
    assert "rm -f /run/securewave/helper.sock" in build
    assert "Depends: wireguard-tools, openvpn, network-manager, libgtk-3-0, libsecret-1-0, iproute2, iptables, acl, systemd" in build
    assert "Suggests: network-manager-strongswan, strongswan, strongswan-swanctl, strongswan-charon, libcharon-extra-plugins, libstrongswan-extra-plugins" in build
    assert "rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules" in build
    assert "render_polkit_rule" not in build


def test_ikev2_helper_cleans_only_unqualified_pref_220_loop_rule():
    helper = HELPER.read_text(encoding="utf-8")

    assert "clear_ikev2_unqualified_rule()" in helper
    assert "clear_ikev2_pref220_rules()" in helper
    assert "clear_ikev2_route_state()" in helper
    assert "other_active_vpn_exists()" in helper
    assert "grep -Eq '^220:[[:space:]]+from all lookup 220$'" in helper
    assert "ip rule del pref 220 table 220" in helper
    assert 'ip rule add pref 220 not fwmark "$fwmark" table 220' in helper
    assert 'exec nmcli connection up id "$CONNECTION_NAME"' not in helper

    rule_block = helper.split("clear_ikev2_unqualified_rule() {", 1)[1].split("clear_ikev2_xfrm_routes() {", 1)[0]
    assert "ip rule del not fwmark" not in rule_block

    route_state_block = helper.split("clear_ikev2_route_state() {", 1)[1].split("clear_policy_state() {", 1)[0]
    assert "if other_active_vpn_exists; then" in route_state_block
    assert "clear_ikev2_pref220_rules" in route_state_block
    assert "clear_ikev2_unqualified_rule" in route_state_block

    up_block = helper.split('if [[ "$action" == "ikev2-up" ]]; then', 1)[1].split("\nfi\n", 1)[0]
    assert up_block.count("clear_ikev2_route_state") == 1
    assert "clear_ikev2_unqualified_rule" in up_block
    assert up_block.index("clear_ikev2_route_state") < up_block.index('nmcli connection up id "$CONNECTION_NAME"')
    assert up_block.index("clear_ikev2_unqualified_rule") > up_block.index('nmcli connection up id "$CONNECTION_NAME"')

    down_block = helper.split('if [[ "$action" == "ikev2-down" ]]; then', 1)[1].split("\nfi\n", 1)[0]
    delete_block = helper.split('if [[ "$action" == "ikev2-delete" ]]; then', 1)[1].split("\nfi\n", 1)[0]
    assert "clear_ikev2_route_state" in down_block
    assert "clear_ikev2_route_state" in delete_block


def test_linux_tarball_and_installer_are_truthful_portable_ui_builds():
    build_apps = BUILD_APPS.read_text(encoding="utf-8")
    installer = DOWNLOAD_INSTALLER.read_text(encoding="utf-8")

    assert 'rm -rf "$PACKAGE_STAGING/packaging/linux" "$PACKAGE_STAGING/scripts/install_linux_helper.sh"' in build_apps
    assert "SecureWave portable Linux package" in build_apps
    assert "Full-device VPN routing requires the root-owned SecureWave helper service." in build_apps
    assert "Install the matching SecureWave .deb package for full no-prompt VPN connect/disconnect." in build_apps
    assert 'aarch64|arm64) ARCH_LABEL="arm64"' in build_apps
    assert 'TARBALL="$DOWNLOADS_DIR/securewave-linux-$ARCH_LABEL.tar.gz"' in build_apps
    assert 'ARCH_LABEL="x64";   FLUTTER_ARCH="arm64"' not in build_apps
    assert "This installs a portable UI-only build" in installer
    assert ".deb package: full VPN routing with the root-owned SecureWave helper service." in installer
    assert "Portable AppImage/tarball/zip: UI-only unless the .deb helper service is already installed." in installer
    assert "pressing Connect should not ask for sudo, pkexec, or a password" in installer
    assert 'aarch64|arm64) ARCH_LABEL="arm64"' in installer


def test_helper_installer_installs_service_socket_model():
    helper_installer = HELPER_INSTALLER.read_text(encoding="utf-8")

    assert "securewave-helperd" in helper_installer
    assert "securewave-helper.service" in helper_installer
    assert "securewave-helper.tmpfiles" in helper_installer
    assert "wireguard-tools" in helper_installer
    assert "openvpn" in helper_installer
    assert "network-manager-strongswan" in helper_installer
    assert "libstrongswan-extra-plugins" in helper_installer
    assert "acl" in helper_installer
    assert "SECUREWAVE_ALLOWED_USER" in helper_installer
    assert 'install -m 0755 "$SOURCE_HELPER_DAEMON" "$HELPER_DAEMON"' in helper_installer
    assert 'install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"' in helper_installer
    assert "systemctl enable --now securewave-helper.service" in helper_installer
    assert "rm -f \"$OLD_POLKIT_RULE\"" in helper_installer


def test_flutter_linux_bundle_ships_deb_runtime_payload():
    cmake = LINUX_CMAKE.read_text(encoding="utf-8")

    assert "add_executable(securewave_helperd" in cmake
    assert "../packaging/linux/securewave-wg-quick" in cmake
    assert "../packaging/linux/securewave-wg-quick.contract" in cmake
    assert "../packaging/linux/securewave-helper.service" in cmake
    assert "../packaging/linux/securewave-helper.tmpfiles" in cmake
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
    assert "d /run/securewave 0750 root securewave -" in tmpfiles
