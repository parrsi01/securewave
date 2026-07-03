from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LINUX_RUNTIME = ROOT / "securewave_app" / "linux" / "runner" / "my_application.cc"
LINUX_HELPERD = ROOT / "securewave_app" / "linux" / "helperd" / "securewave_helperd.cc"
LINUX_HELPER = ROOT / "securewave_app" / "packaging" / "linux" / "securewave-wg-quick"
LINUX_RUNBOOK = ROOT / "securewave_app" / "LINUX_VPN_SETUP.md"


def test_linux_runtime_uses_installed_helper_service_socket_for_wireguard():
    source = LINUX_RUNTIME.read_text(encoding="utf-8")

    assert 'kHelperSocketPath = "/run/securewave/helper.sock"' in source
    assert 'kWireGuardConfigFileName = "sw-wg.conf"' in source
    assert '"wireguard.up"' in source
    assert '"wireguard.down"' in source
    assert '"wireguard.counters"' in source
    assert "pkexec" not in source
    assert "sudo" not in source


def test_linux_runtime_writes_private_state_and_helperd_restricts_paths():
    source = LINUX_RUNTIME.read_text(encoding="utf-8")
    helperd = LINUX_HELPERD.read_text(encoding="utf-8")
    helper = LINUX_HELPER.read_text(encoding="utf-8")

    assert 'kWireGuardConfigFileName = "sw-wg.conf"' in source
    assert "build_state_path(" in source
    assert "config_file_for_protocol(protocol)" in source
    assert "g_file_set_contents(path, contents" in source
    assert "g_chmod(path, 0600)" in source
    assert "persist_active_protocol(state, protocol)" in source
    assert "ValidateConfigPath(config_path, \"sw-wg.conf\", peer_uid)" in helperd
    assert "ValidateConfigPath(config_path, \"securewave.ovpn\", peer_uid)" in helperd
    assert "ValidateRuntimeFilePath(pid_path, kOpenVpnPidName, peer_uid)" in helperd
    assert "IsApprovedRuntimePath" in helperd
    assert "/home/*/.config/securewave/*" in helper
    assert 'if [[ "$iface" != "sw-wg" ]]' in helper


def test_helperd_reports_failures_and_requires_route_evidence():
    helperd = LINUX_HELPERD.read_text(encoding="utf-8")

    assert "WireGuardRouteExists()" in helperd
    assert "WireGuard command completed but route evidence did not use sw-wg." in helperd
    assert "OpenVpnRouteExists()" in helperd
    assert "OpenVPN started but tunnel route evidence was not detected." in helperd
    assert "Ikev2RuntimeEvidence" in helperd
    assert "XfrmHasEsp" in helperd
    assert "protocol_unavailable" in helperd
    assert "IKEv2 is disabled until SecureWave has live production proof" in helperd


def test_wireguard_helper_stabilizes_policy_after_up_and_clears_on_down():
    helper = LINUX_HELPER.read_text(encoding="utf-8")

    assert "ensure_policy_state()" in helper
    assert 'wg-quick up "$config"' in helper
    assert 'nmcli device set "$iface" managed no' in helper
    assert "ensure_policy_state" in helper
    assert 'if [[ "$action" == "down" ]]' in helper
    assert 'wg-quick down "$config" >/dev/null 2>&1 || true' in helper
    assert "clear_policy_state 1" in helper


def test_linux_setup_doc_documents_service_model_without_scope_expansion():
    runbook = LINUX_RUNBOOK.read_text(encoding="utf-8")

    assert "root-owned SecureWave helper service" in runbook
    assert "/run/securewave/helper.sock" in runbook
    assert "systemctl status securewave-helper.service" in runbook
    assert "Connect in the app should not ask for" in runbook
    assert "sudo, pkexec, or a password" in runbook
    assert "Config File Permissions" in runbook
    assert "Manual Cleanup" in runbook
    assert "sudo systemctl restart securewave-helper.service" in runbook
    assert "Do not enable IKEv2 as available unless XFRM ESP evidence is proven" in runbook
    assert "PolicyKit" not in runbook
    assert "pkexec --disable-internal-agent" not in runbook
