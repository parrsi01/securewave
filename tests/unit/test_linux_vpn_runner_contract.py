from pathlib import Path


RUNNER = Path("securewave_app/linux/runner/my_application.cc")
HELPER = Path("securewave_app/packaging/linux/securewave-wg-quick")
HELPER_CONTRACT = Path("securewave_app/packaging/linux/securewave-wg-quick.contract")
POLKIT_RULE = Path("securewave_app/packaging/linux/50-securewave-wg.rules")
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
    assert "persist_active_protocol(state, \"wireguard\")" in source
    assert "persist_active_protocol(state, \"openvpn\")" in source
    assert "persist_active_protocol(state, \"ikev2\")" in source
    assert "load_active_protocol(state)" in source


def test_openvpn_start_requires_tunnel_evidence_not_only_daemon_pid():
    source = _runner_source()

    assert "openvpn_runtime_evidence_exists" in source
    assert "openvpn_pid_running(pid_path)" in source
    assert "openvpn_initialization_completed" in source
    assert "Initialization Sequence Completed" in source
    assert "openvpn_log_tail" in source
    assert "stop_openvpn_after_failed_start" in source
    assert 'run_securewave_helper_sync("openvpn-stop", stop_args, nullptr)' in source
    assert "OpenVPN process started but Initialization Sequence Completed" in source
    assert '{"ip", "route", "get", "1.1.1.1", nullptr}' in source
    assert '" dev tun"' in source
    assert '"/sys/class/net/tun0"' in source


def test_openvpn_start_and_stop_use_scoped_securewave_helper():
    source = _runner_source()

    assert 'const_cast<gchar*>("--disable-internal-agent")' in source
    assert 'const_cast<gchar*>("openvpn-start")' in source
    assert "g_ptr_array_add(argv_array, const_cast<gchar*>(log_path))" in source
    assert 'const_cast<gchar*>("openvpn-stop")' in source
    assert "verify_openvpn_started = TRUE" in source
    assert "verify_openvpn_stopped = TRUE" in source
    assert "OpenVPN stop command completed but process or tunnel route evidence remains." in source
    assert "securewave_helper_contract_available(&helper_detail)" in source


def test_wireguard_start_requires_route_evidence_not_only_interface():
    source = _runner_source()

    assert 'kWireGuardInterfaceName = "sw-wg"' in source
    assert 'kWireGuardConfigFileName = "sw-wg.conf"' in source
    assert "wireguard_route_exists" in source
    assert '{"ip", "route", "get", "1.1.1.1", nullptr}' in source
    assert '" dev sw-wg"' in source
    assert "route traffic was not using interface %s" in source


def test_wireguard_start_prefers_installed_securewave_helper():
    source = _runner_source()

    assert 'kWireGuardHelperPath = "/usr/local/libexec/securewave-wg-quick"' in source
    assert "wireguard_helper_available()" in source
    assert '"--disable-internal-agent"' in source
    assert "g_ptr_array_add(argv_array, const_cast<gchar*>(kWireGuardHelperPath))" in source


def test_linux_runner_preserves_helper_stdout_stderr_on_failures():
    source = _runner_source()

    assert "g_spawn_async_with_pipes" in source
    assert "read_fd_to_string(&ctx->stdout_fd)" in source
    assert "read_fd_to_string(&ctx->stderr_fd)" in source
    assert "command_failure_message" in source
    assert "VPN helper command failed." in source


def test_ikev2_start_uses_networkmanager_helper_and_runtime_evidence():
    source = _runner_source()

    assert 'kIkev2ConnectionName = "SecureWave-IKEv2"' in source
    assert '"ikev2-add-eap"' in source
    assert '"ikev2-up"' in source
    assert '"ikev2-down"' in source
    assert '"ikev2-delete"' in source
    assert "parse_config_value(config, \"remote_addrs\")" in source
    assert "parse_config_value(config, \"eap_id\")" in source
    assert "parse_config_value(config, \"secret\")" in source
    assert "parse_ikev2_ca_cert_pem(config)" in source
    assert 'kIkev2CaFileName = "securewave-ikev2-ca.pem"' in source
    assert "ctx->ca_cert_path" in source
    assert "kSecureWaveHelperContractVersion = 7" in source
    assert "ikev2_runtime_evidence_exists" in source
    assert "ikev2_xfrm_state_evidence_exists" in source
    assert "active NetworkManager VPN route/DNS and XFRM ESP evidence was not detected" in source


def test_linux_runner_exposes_protocol_traffic_stats():
    source = _runner_source()

    assert 'getTrafficStats' in source
    assert 'rx_bytes' in source
    assert 'tx_bytes' in source
    assert 'interface_counter_available' in source
    assert 'counters_available' in source
    assert 'unavailable_reason' in source
    assert 'traffic_interface_for_protocol' in source
    assert '"/sys/class/net"' in source
    assert 'read_wireguard_transfer_counters' in source
    assert '"wireguard-transfer"' in source
    assert 'run_securewave_helper_capture_sync' in source
    assert 'read_ikev2_xfrm_counters' in source
    assert '"ip", "-s", "xfrm", "state"' in source
    assert '"xfrm-state"' in source
    assert '"xfrm"' in source



def test_linux_package_installs_privileged_helper_and_runtime_dependencies():
    helper = HELPER.read_text(encoding="utf-8")
    helper_contract = HELPER_CONTRACT.read_text(encoding="utf-8").strip()
    build = BUILD_DEB.read_text(encoding="utf-8")

    assert "securewave-wg-quick openvpn-start <config-path> <pid-path> <log-path> [auth-path]" in helper
    assert "wireguard-transfer" in helper
    assert "xfrm-state" in helper
    assert "ikev2-add-eap <server> <username> <password> [remote-id] [ca-cert-path]" in helper
    assert "cert-source=file" in helper
    assert "certificate=${ca_cert}" in helper
    assert '--log "$log_file"' in helper
    assert "prepare_owned_runtime_file" in helper
    assert 'prepare_owned_runtime_file "$pid_file" "pid" "$config"' in helper
    assert 'prepare_owned_runtime_file "$log_file" "log" "$config"' in helper
    assert "stat -c '%u:%g'" in helper
    assert 'chmod 0600 "$tmp"' in helper
    assert 'mv -fT "$tmp" "$path"' in helper
    assert helper_contract == "7"
    assert "securewave-wg-quick.contract" in build
    assert "50-securewave-wg.rules" in build
    assert "render_polkit_rule" in build
    assert "__SECUREWAVE_ALLOWED_USER__" in build
    assert "reload_polkit" in build
    assert "try-reload-or-restart polkit.service" in build
    assert "postinst" in build
    assert "postrm" in build
    assert "Depends: wireguard-tools, openvpn, network-manager, network-manager-strongswan, strongswan, policykit-1" in build


def test_linux_tarball_and_installer_ship_privileged_helper():
    build_apps = BUILD_APPS.read_text(encoding="utf-8")
    installer = DOWNLOAD_INSTALLER.read_text(encoding="utf-8")
    helper_installer = HELPER_INSTALLER.read_text(encoding="utf-8")

    assert 'mkdir -p "$PACKAGE_STAGING/packaging/linux" "$PACKAGE_STAGING/scripts"' in build_apps
    assert 'ARCH_LABEL="arm64"; FLUTTER_ARCH="arm64"' in build_apps
    assert "securewave-wg-quick" in build_apps
    assert "securewave-wg-quick.contract" in build_apps
    assert "50-securewave-wg.rules" in build_apps
    assert "install_linux_helper.sh" in build_apps
    assert "securewave-app-linux-arm64.zip" in build_apps
    assert "securewave-linux-x64.tar.gz" in build_apps
    assert 'HELPER_INSTALLER="$INSTALL_DIR/scripts/install_linux_helper.sh"' in installer
    assert "extract_package()" in installer
    assert "*.tar.gz|*.tgz)" in installer
    assert "*.zip)" in installer
    assert 'SECUREWAVE_ALLOWED_USER="${SUDO_USER:-}" "$HELPER_INSTALLER" "$INSTALL_DIR/packaging/linux"' in installer
    assert 'Download a current SecureWave Linux package' in installer
    assert "apt-get install -y" in helper_installer
    assert "wireguard-tools" in helper_installer
    assert "network-manager-strongswan" in helper_installer
    assert "PKEXEC_UID" in helper_installer
    assert 'getent passwd "$PKEXEC_UID"' in helper_installer
    assert 'install -m 0755 "$SOURCE_HELPER" "$HELPER"' in helper_installer
    assert 'install -m 0644 "$SOURCE_CONTRACT" "$HELPER_CONTRACT"' in helper_installer
    assert 'sed "s/__SECUREWAVE_ALLOWED_USER__/${escaped_user}/g"' in helper_installer
    assert "systemctl try-reload-or-restart polkit.service" in helper_installer


def test_flutter_linux_bundle_installs_helper_payload():
    cmake = LINUX_CMAKE.read_text(encoding="utf-8")

    assert "../packaging/linux/securewave-wg-quick" in cmake
    assert "../packaging/linux/securewave-wg-quick.contract" in cmake
    assert "../packaging/linux/50-securewave-wg.rules" in cmake
    assert "../scripts/install_linux_helper.sh" in cmake
    assert 'DESTINATION "${CMAKE_INSTALL_PREFIX}/packaging/linux"' in cmake
    assert 'DESTINATION "${CMAKE_INSTALL_PREFIX}/scripts"' in cmake


def test_polkit_rule_scopes_prompt_free_actions_to_securewave_runtime():
    rule = POLKIT_RULE.read_text(encoding="utf-8")

    assert 'action.id != "org.freedesktop.policykit.exec"' in rule
    assert 'configuredUser != "__SECUREWAVE_ALLOWED_USER__"' in rule
    assert "subject.user == configuredUser" in rule
    assert 'subject.user == "securewave"' in rule
    assert 'subject.isInGroup("sudo")' in rule
    assert 'program == "/usr/local/libexec/securewave-wg-quick"' in rule
    assert 'program == "/usr/bin/wg" || program == "/bin/wg"' in rule
    assert 'commandHasArg(commandLine, "show")' in rule
    assert "polkit.Result.YES" in rule
    assert "polkit.Result.NOT_HANDLED" in rule


def test_linux_deb_postinst_installs_rendered_polkit_rule_safely():
    build = BUILD_DEB.read_text(encoding="utf-8")

    assert "SOURCE_POLKIT_RULE=$SOURCE_DIR/50-securewave-wg.rules" in build
    assert "POLKIT_RULES_DIR=/etc/polkit-1/rules.d" in build
    assert "POLKIT_RULE=$POLKIT_RULES_DIR/50-securewave-wg.rules" in build
    assert 'mkdir -p "$POLKIT_RULES_DIR"' in build
    assert 'install -m 0644 "$SOURCE_POLKIT_RULE" "$POLKIT_RULE"' in build
    assert 'sed "s/__SECUREWAVE_ALLOWED_USER__/${escaped_user}/g"' in build
    assert 'chmod 0644 "$POLKIT_RULE"' in build
    assert 'ALLOW_USER="${SUDO_USER:-}"' in build
    assert 'ALLOW_USER="$(logname 2>/dev/null || true)"' in build
    assert "systemctl try-reload-or-restart polkit.service" in build
    assert "rm -f /etc/polkit-1/rules.d/50-securewave-wg.rules" in build


def test_linux_runner_reports_missing_helper_before_protocol_start():
    source = _runner_source()

    assert "linux_native_runtime_available" in source
    assert "securewave_helper_contract_available(detail)" in source
    assert "PolicyKit/pkexec not found" in source
    assert "SecureWave Linux VPN runtime is unavailable." in source
    assert 'g_strcmp0(method, "isAvailable") == 0' in source


def test_linux_runner_exposes_first_run_helper_installation():
    source = _runner_source()

    assert "bundled_runtime_payload_available" in source
    assert "kHelperInstallerRelativePath" in source
    assert "kBundledHelperRelativePath" in source
    assert "respond_runtime_install_state" in source
    assert "install_runtime_helper_async" in source
    assert 'g_strcmp0(method, "getRuntimeInstallState") == 0' in source
    assert 'g_strcmp0(method, "installRuntimeHelper") == 0' in source
    assert "g_find_program_in_path(\"pkexec\")" in source
