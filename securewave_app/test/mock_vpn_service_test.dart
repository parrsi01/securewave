import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/models/vpn_status.dart';

void main() {
  test('deferred protocols remain unavailable even in the mock runtime',
      () async {
    final service = MockVpnService(connectDelay: Duration.zero);

    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(
      () => service.connect(protocol: VpnProtocol.ikev2),
      throwsA(isA<VpnServiceException>()),
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test('MockVpnService connects and disconnects with delays', () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);

    expect(service.canConnectProtocol(VpnProtocol.openVpn), isFalse);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2), isNotNull);
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

  test('ChannelVpnService does not probe deferred protocols', () async {
    const channel = MethodChannel('securewave/vpn');
    final calls = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      calls.add(arguments);
      return arguments['protocol'] == 'ikev2' &&
          arguments['backend_evidence'] == true;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = ChannelVpnService(allowFallback: false);
    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(
      await service.refreshProtocolAvailability(VpnProtocol.ikev2),
      isFalse,
    );
    expect(calls, isEmpty);
    expect(
      await service.refreshProtocolAvailability(
        VpnProtocol.ikev2,
        backendEvidence: true,
      ),
      isFalse,
    );
    expect(calls, isEmpty);
    expect(service.canConnectProtocol(VpnProtocol.ikev2), isFalse);
    expect(service.protocolUnavailableReason(VpnProtocol.ikev2), isNotNull);
  }, testOn: 'linux');

  test(
    'ChannelVpnService returns the WireGuard helper probe result',
    () async {
      const channel = MethodChannel('securewave/vpn');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final arguments = Map<Object?, Object?>.from(call.arguments as Map);
        final protocol = arguments['protocol'];
        if (protocol == 'wireguard') return true;
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

      expect(service.isNativeAvailable, isTrue);
      expect(
        service.protocolUnavailableReason(VpnProtocol.ikev2),
        contains('deferred'),
      );
    },
    testOn: 'linux',
  );

  test('ChannelVpnService forwards the WireGuard profile', () async {
    const channel = MethodChannel('securewave/vpn');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = ChannelVpnService(allowFallback: false);
    await service.connect(
      protocol: VpnProtocol.wireGuard,
      config: '[Interface]\nPrivateKey = test\n',
    );

    final connect = calls.lastWhere((call) => call.method == 'connect');
    final arguments = Map<Object?, Object?>.from(connect.arguments as Map);
    expect(arguments['protocol'], 'wireguard');
    expect(arguments['config'], contains('PrivateKey'));
  }, testOn: 'linux');
}
