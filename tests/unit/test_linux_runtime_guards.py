from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LINUX_RUNTIME = ROOT / "securewave_app" / "linux" / "runner" / "my_application.cc"
LINUX_HELPER = ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick"
LINUX_RUNBOOK = ROOT / "securewave_app" / "LINUX_VPN_SETUP.md"


def test_linux_runtime_prefers_installed_securewave_helper_for_wireguard():
    source = LINUX_RUNTIME.read_text(encoding="utf-8")

    assert 'kWireGuardInterfaceName = "sw-wg"' in source
    assert 'kWireGuardHelperPath = "/usr/local/libexec/securewave-wg-quick"' in source
    assert "wireguard_helper_available()" in source
    assert 'const_cast<gchar*>("--disable-internal-agent")' in source
    assert "g_ptr_array_add(argv_array, const_cast<gchar*>(kWireGuardHelperPath))" in source


def test_linux_runtime_writes_private_state_and_helper_restricts_paths():
    source = LINUX_RUNTIME.read_text(encoding="utf-8")
    helper = LINUX_HELPER.read_text(encoding="utf-8")

    assert 'kWireGuardConfigFileName = "sw-wg.conf"' in source
    assert "build_state_path(kWireGuardConfigFileName)" in source
    assert "g_file_set_contents(state->config_path, config" in source
    assert "g_chmod(state->config_path, 0600)" in source
    assert 'persist_active_protocol(state, "wireguard")' in source
    assert "require_safe_config_path()" in helper
    assert "/home/*/.config/securewave/*.conf" in helper
    assert "require_sw_wg_iface()" in helper
    assert 'if [[ "$iface" != "sw-wg" ]]' in helper


def test_linux_runtime_reports_helper_failures_and_requires_route_evidence():
    source = LINUX_RUNTIME.read_text(encoding="utf-8")

    assert "kWgQuickTimeoutMs" in source
    assert "g_spawn_async_with_pipes" in source
    assert "read_fd_to_string(&ctx->stdout_fd)" in source
    assert "read_fd_to_string(&ctx->stderr_fd)" in source
    assert "command_failure_message" in source
    assert "wireguard_route_exists" in source
    assert "route traffic was not using interface %s" in source
    assert "WireGuard command completed but interface %s is still present." in source


def test_linux_setup_doc_documents_helper_recovery_without_scope_expansion():
    runbook = LINUX_RUNBOOK.read_text(encoding="utf-8")

    assert "Config file permissions" in runbook
    assert "Manual cleanup" in runbook
    assert "securewave-wg-quick policy-clear-link sw-wg" in runbook
    assert "Do not enable OpenVPN or IKEv2 as a workaround for public v1" in runbook
