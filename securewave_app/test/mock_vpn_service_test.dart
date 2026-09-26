import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ChannelVpnService starts fail closed until WireGuard probe succeeds',
      () async {
    const channel = MethodChannel('securewave/vpn');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isAvailable') return true;
      return true;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = ChannelVpnService();
    expect(service.canConnectProtocol(VpnProtocol.wireGuard), isFalse);

    expect(
      await service.refreshProtocolAvailability(
        VpnProtocol.wireGuard,
        backendEvidence: true,
      ),
      isTrue,
    );
    expect(service.canConnectProtocol(VpnProtocol.wireGuard), isTrue);
  }, testOn: 'linux');

  test('ChannelVpnService forwards only the WireGuard config', () async {
    const channel = MethodChannel('securewave/vpn');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isAvailable') return true;
      if (call.method == 'connect') return true;
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final service = ChannelVpnService();
    final status = await service.connect(
      protocol: VpnProtocol.wireGuard,
      config: '[Interface]\nPrivateKey = test\n',
      backendEvidence: true,
    );

    expect(status, VpnStatus.connected);
    final connect = calls.lastWhere((call) => call.method == 'connect');
    final arguments = Map<Object?, Object?>.from(connect.arguments as Map);
    expect(arguments['protocol'], 'wireguard');
    expect(arguments['config'], contains('PrivateKey'));
    expect(arguments['backend_evidence'], isTrue);
  }, testOn: 'linux');
}
