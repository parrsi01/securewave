import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
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

  test(
      'auto returns explicit error and does not choose WireGuard by default when multiple runtimes exist',
      () {
    const caps = VpnCapabilities(
      wireGuard: true,
      openVpn: true,
      ikev2: true,
    );

    final resolution =
        selector.resolve(selected: VpnProtocol.auto, capabilities: caps);

    expect(resolution.isConnectable, isFalse);
    expect(resolution.effective, VpnProtocol.auto);
    expect(resolution.backendProtocol, VpnProtocol.auto);
    expect(
      resolution.error,
      contains('Automatic protocol selection is disabled'),
    );
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
