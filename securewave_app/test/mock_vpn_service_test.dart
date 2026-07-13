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

  test('ChannelVpnService starts Linux protocol availability fail closed', () {
    final service = ChannelVpnService(allowFallback: false);

    expect(service.canConnectProtocol(VpnProtocol.wireGuard), isFalse);
    expect(service.canConnectProtocol(VpnProtocol.openVpn), isFalse);
    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2), isNotNull);
  }, testOn: 'linux');

  test('ChannelVpnService enables Linux IKEv2 only after its helper probe',
      () async {
    const channel = MethodChannel('securewave/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      return arguments['protocol'] == 'ikev2';
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = ChannelVpnService(allowFallback: false);
    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(
      await service.refreshProtocolAvailability(VpnProtocol.ikev2),
      isTrue,
    );
    expect(service.canConnectProtocol(VpnProtocol.ikev2), isTrue);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2), isNull);
  }, testOn: 'linux');

  test(
    'ChannelVpnService returns selected Linux helper probe result',
    () async {
      const channel = MethodChannel('securewave/vpn');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final arguments = Map<Object?, Object?>.from(call.arguments as Map);
        final protocol = arguments['protocol'];
        if (protocol == 'wireguard') return true;
        if (protocol == 'ikev2') {
          throw PlatformException(
            code: 'protocol_unavailable',
            message: 'IKEv2 helper probe could not find swanctl.',
          );
        }
        return false;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final service = ChannelVpnService(allowFallback: false);
      expect(
        await service.refreshProtocolAvailability(VpnProtocol.wireGuard),
        isTrue,
      );
      expect(service.isNativeAvailable, isTrue);

      expect(
        await service.refreshProtocolAvailability(VpnProtocol.ikev2),
        isFalse,
      );
      expect(service.isNativeAvailable, isTrue);
      expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
      expect(
        service.protocolUnavailableReason(VpnProtocol.ikev2),
        'IKEv2 helper probe could not find swanctl.',
      );
    },
    testOn: 'linux',
  );
}
