from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DART_SERVICE = ROOT / "securewave_app/lib/core/services/vpn_service.dart"
LINUX_RUNNER = ROOT / "securewave_app/linux/runner/my_application.cc"
WINDOWS_RUNNER = ROOT / "securewave_app/windows/runner/flutter_window.cpp"
MACOS_RUNNER = ROOT / "securewave_app/macos/Runner/AppDelegate.swift"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_linux_availability_probes_selected_protocol_through_helper():
    source = _read(LINUX_RUNNER)

    assert 'g_strcmp0(method, "isAvailable") == 0' in source
    assert 'const gchar* protocol = get_string_arg(args, "protocol")' in source
    assert 'helper_operation("probe", probe_args' in source
    assert '"protocol_unavailable"' in source
    assert "pkexec" not in source
    assert '"/bin/sh"' not in source


def test_windows_runtime_is_truthfully_wireguard_only():
    source = _read(WINDOWS_RUNNER)

    assert '*protocol == "wireguard"' in source
    assert "This Windows runtime implements WireGuard only." in source
    assert "TunnelServiceRunning()" in source
    assert "Windows WireGuard byte counters are not implemented" in source
    assert '"counters_available"' in source


def test_macos_runtime_remains_intentionally_unavailable():
    source = _read(MACOS_RUNNER)

    assert 'case "isAvailable":' in source
    assert "result(false)" in source
    assert '"status": "disconnected"' in source
    assert '"counters_available": false' in source
    assert "does not include a Network Extension tunnel provider" in source


def test_dart_service_fails_closed_by_platform_and_passes_protocol_to_native():
    source = _read(DART_SERVICE)

    assert "ChannelVpnService({VpnService? fallback, bool allowFallback = false})" in source
    assert "if (os == 'linux') return true;" in source
    assert "os == 'windows' || os == 'android' || os == 'ios'" in source
    assert "return protocol == VpnProtocol.wireGuard;" in source
    assert "final available = await refreshProtocolAvailability(protocol);" in source
    assert "{'protocol': vpnProtocolStorageValue(protocol)}" in source
    assert "(_protocolAvailability[protocol] ?? false)" in source
    assert "_protocolAvailabilityMessages[protocol]" in source
    assert "return protocol == null" in source
    assert "_nativeAvailable = false;" in source
