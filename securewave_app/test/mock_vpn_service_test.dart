import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MockVpnService connects and disconnects with delays', () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);

    expect(service.canConnectProtocol(VpnProtocol.ikev2), isTrue);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2), isNull);
    expect(service.getStatus(), VpnStatus.disconnected);

    final connected = await service.connect(protocol: VpnProtocol.wireGuard);
    expect(connected, VpnStatus.connected);
    expect(service.getStatus(), VpnStatus.connected);

    final disconnected = await service.disconnect();
    expect(disconnected, VpnStatus.disconnected);
    expect(service.getStatus(), VpnStatus.disconnected);
  });

  test('ChannelVpnService blocks IKEv2 on Linux release runtime', () {
    final service = ChannelVpnService(allowFallback: false);

    expect(service.canConnectProtocol(VpnProtocol.wireGuard), isTrue);
    expect(service.canConnectProtocol(VpnProtocol.openVpn), isTrue);
    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(
      service.protocolUnavailableReason(VpnProtocol.ikev2),
      contains('strongSwan profile import/start path'),
    );
  }, testOn: 'linux');

  test('ChannelVpnService fails closed when IKEv2 connect is requested',
      () async {
    final service = ChannelVpnService(allowFallback: false);

    await expectLater(
      service.connect(protocol: VpnProtocol.ikev2, config: 'ikev2-profile'),
      throwsA(
        isA<VpnServiceException>()
            .having((error) => error.code, 'code', 'protocol_unavailable')
            .having((error) => error.message, 'message', contains('IKEv2')),
      ),
    );
    expect(service.getStatus(), VpnStatus.disconnected);
  }, testOn: 'linux');

  test('ChannelVpnService fails closed when OpenVPN runtime is missing',
      () async {
    const channel = MethodChannel('securewave/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isAvailable') return true;
      if (call.method == 'connect') {
        throw PlatformException(
          code: 'vpn_unavailable',
          message: 'openvpn not found. Install OpenVPN and retry.',
        );
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = ChannelVpnService(allowFallback: false);

    await expectLater(
      service.connect(protocol: VpnProtocol.openVpn, config: 'client'),
      throwsA(
        isA<VpnServiceException>()
            .having((error) => error.code, 'code', 'vpn_unavailable')
            .having((error) => error.message, 'message', contains('openvpn')),
      ),
    );
    expect(service.getStatus(), VpnStatus.disconnected);
  }, testOn: 'linux');

  test('ChannelVpnService does not silently mock when fallback is disabled',
      () async {
    const channel = MethodChannel('securewave/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isAvailable') return false;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final fallback = MockVpnService(
      connectDelay: Duration.zero,
      disconnectDelay: Duration.zero,
    );
    final service = ChannelVpnService(
      fallback: fallback,
      allowFallback: false,
    );

    await expectLater(
      service.connect(protocol: VpnProtocol.wireGuard, config: 'wg'),
      throwsA(
        isA<VpnServiceException>().having(
          (error) => error.code,
          'code',
          'vpn_unavailable',
        ),
      ),
    );
    expect(service.getStatus(), VpnStatus.disconnected);
    expect(fallback.getStatus(), VpnStatus.disconnected);
  });
}
