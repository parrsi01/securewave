import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_protocol_catalog.dart';
import 'package:securewave_app/core/services/protocol_selector.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  const selector = ProtocolSelector();

  test('rejects unsupported concrete protocol without WireGuard fallback', () {
    const caps = VpnCapabilities(
      wireGuard: true,
      openVpn: false,
      ikev2: false,
    );

    final resolution =
        selector.resolve(selected: VpnProtocol.openVpn, capabilities: caps);

    expect(resolution.isConnectable, isFalse);
    expect(resolution.effective, VpnProtocol.openVpn);
    expect(resolution.warning, isNull);
    expect(resolution.error, contains('OpenVPN runtime is not available'));
  });

  test('auto deterministically chooses WireGuard when multiple runtimes exist',
      () {
    const caps = VpnCapabilities(
      wireGuard: true,
      openVpn: true,
      ikev2: true,
    );

    final resolution =
        selector.resolve(selected: VpnProtocol.auto, capabilities: caps);

    expect(resolution.isConnectable, isTrue);
    expect(resolution.effective, VpnProtocol.wireGuard);
    expect(resolution.backendProtocol, VpnProtocol.wireGuard);
    expect(resolution.warning, contains('Automatic selected WireGuard'));
    expect(resolution.error, isNull);
  });

  test('auto can resolve when exactly one runtime is available', () {
    const caps = VpnCapabilities(
      wireGuard: false,
      openVpn: true,
      ikev2: false,
    );

    final resolution =
        selector.resolve(selected: VpnProtocol.auto, capabilities: caps);

    expect(resolution.isConnectable, isTrue);
    expect(resolution.effective, VpnProtocol.openVpn);
    expect(resolution.backendProtocol, VpnProtocol.openVpn);
  });

  test('rejects protocol disabled by backend even when runtime exists', () {
    const caps = VpnCapabilities(
      wireGuard: true,
      openVpn: true,
      ikev2: false,
    );
    final catalog = VpnProtocolCatalog.fromJson({
      'user_tier': 'free',
      'device_type': 'linux',
      'protocols': [
        {
          'protocol': 'wireguard',
          'enabled': true,
          'server_enabled': true,
          'plan_enabled': true,
          'platform_supported': true,
        },
        {
          'protocol': 'openvpn',
          'enabled': false,
          'server_enabled': false,
          'plan_enabled': true,
          'platform_supported': true,
          'reason': 'disabled_server_side',
        },
      ],
    });

    final resolution = selector.resolve(
      selected: VpnProtocol.openVpn,
      capabilities: caps,
      catalog: catalog,
    );

    expect(resolution.isConnectable, isFalse);
    expect(resolution.backendBlocked, isTrue);
    expect(resolution.runtimeBlocked, isFalse);
    expect(resolution.error, contains('backend'));
  });

  test('auto picks backend-enabled runtime instead of disabled local runtime',
      () {
    const caps = VpnCapabilities(
      wireGuard: true,
      openVpn: true,
      ikev2: false,
    );
    final catalog = VpnProtocolCatalog.fromJson({
      'user_tier': 'free',
      'device_type': 'linux',
      'protocols': [
        {
          'protocol': 'wireguard',
          'enabled': true,
          'server_enabled': true,
          'plan_enabled': true,
          'platform_supported': true,
        },
        {
          'protocol': 'openvpn',
          'enabled': false,
          'server_enabled': false,
          'plan_enabled': true,
          'platform_supported': true,
          'reason': 'disabled_server_side',
        },
      ],
    });

    final resolution = selector.resolve(
      selected: VpnProtocol.auto,
      capabilities: caps,
      catalog: catalog,
    );

    expect(resolution.isConnectable, isTrue);
    expect(resolution.effective, VpnProtocol.wireGuard);
    expect(resolution.backendProtocol, VpnProtocol.wireGuard);
  });

  test('auto returns explicit error when no protocol is available', () {
    const caps = VpnCapabilities(
      wireGuard: false,
      openVpn: false,
      ikev2: false,
    );

    final resolution =
        selector.resolve(selected: VpnProtocol.auto, capabilities: caps);

    expect(resolution.isConnectable, isFalse);
    expect(resolution.error, contains('No supported VPN runtime'));
  });
}
