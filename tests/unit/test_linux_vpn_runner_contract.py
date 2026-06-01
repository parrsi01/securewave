from pathlib import Path


RUNNER = Path("securewave_app/linux/runner/my_application.cc")


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
    assert "OpenVPN process started but no tunnel interface or tunnel route was detected." in source
    assert '{"ip", "route", "get", "1.1.1.1", nullptr}' in source
    assert '" dev tun"' in source
    assert '"/sys/class/net/tun0"' in source


def test_openvpn_start_and_stop_use_scoped_securewave_helper():
    source = _runner_source()

    assert 'const_cast<gchar*>("--disable-internal-agent")' in source
    assert 'const_cast<gchar*>("openvpn-start")' in source
    assert 'const_cast<gchar*>("openvpn-stop")' in source
    assert "verify_openvpn_started = TRUE" in source
    assert "verify_openvpn_stopped = TRUE" in source
    assert "OpenVPN stop command completed but process or tunnel route evidence remains." in source


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


def test_ikev2_start_verifies_strongswan_sa_after_initiate():
    source = _runner_source()

    assert "swanctl --initiate --child securewave" in source
    assert "swanctl --list-sas | grep -q securewave" in source
    assert "swanctl --terminate --child securewave" in source


def test_linux_runner_exposes_protocol_traffic_stats():
    source = _runner_source()

    assert 'getTrafficStats' in source
    assert 'rx_bytes' in source
    assert 'tx_bytes' in source
    assert 'traffic_interface_for_protocol' in source
    assert '"/sys/class/net"' in source
