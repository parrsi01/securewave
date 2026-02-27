import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('securewave/vpn');

  testWidgets('recovers status after native crash mid-session', (tester) async {
    var nativeConnected = false;
    var connectCalls = 0;

    Future<Object?> handler(MethodCall call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'getCapabilities':
          return <String, Object?>{
            'wireguard': true,
            'openvpn': true,
            'ikev2': true,
            'linux_wg_installed': true,
            'linux_elevation_available': true,
          };
        case 'connect':
          connectCalls += 1;
          nativeConnected = true;
          return null;
        case 'disconnect':
          nativeConnected = false;
          return null;
        case 'getStatus':
          return nativeConnected ? 'connected' : 'disconnected';
      }
      return null;
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = ChannelVpnService();
    await tester.pump();

    final status = await service.connect(
      protocol: VpnProtocol.wireGuard,
      profile: const <String, dynamic>{
        'wireguard_config': '[Interface]\nAddress=10.8.0.2/32\n',
      },
    );
    expect(status, VpnStatus.connected);
    expect(connectCalls, 1);

    // Simulate a native runner crash or process drop.
    nativeConnected = false;
    final refreshed = await service.refreshStatus();
    expect(refreshed, VpnStatus.disconnected);
  });

  testWidgets('avoids duplicate connect when native tunnel is already up',
      (tester) async {
    var nativeConnected = true;
    var connectCalls = 0;

    Future<Object?> handler(MethodCall call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'getCapabilities':
          return <String, Object?>{
            'wireguard': true,
            'openvpn': true,
            'ikev2': true,
            'linux_wg_installed': true,
            'linux_elevation_available': true,
          };
        case 'connect':
          connectCalls += 1;
          nativeConnected = true;
          return null;
        case 'disconnect':
          nativeConnected = false;
          return null;
        case 'getStatus':
          return nativeConnected ? 'connected' : 'disconnected';
      }
      return null;
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = ChannelVpnService();
    await tester.pump();

    final status = await service.connect(
      protocol: VpnProtocol.openVpn,
      profile: const <String, dynamic>{
        'ovpn_config': 'client\nremote 138.199.204.139 1194\n',
      },
    );
    expect(status, VpnStatus.connected);
    expect(connectCalls, 0);
  });

  testWidgets('supports reconnect and protocol switching sequence',
      (tester) async {
    var nativeConnected = false;
    final connectProtocols = <String>[];

    Future<Object?> handler(MethodCall call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'getCapabilities':
          return <String, Object?>{
            'wireguard': true,
            'openvpn': true,
            'ikev2': true,
            'linux_wg_installed': true,
            'linux_elevation_available': true,
          };
        case 'connect':
          final args = call.arguments as Map<dynamic, dynamic>;
          connectProtocols.add(args['protocol']?.toString() ?? '');
          nativeConnected = true;
          return null;
        case 'disconnect':
          nativeConnected = false;
          return null;
        case 'getStatus':
          return nativeConnected ? 'connected' : 'disconnected';
      }
      return null;
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = ChannelVpnService();
    await tester.pump();

    await service.connect(
      protocol: VpnProtocol.wireGuard,
      profile: const <String, dynamic>{
        'wireguard_config': '[Interface]\nAddress=10.8.0.2/32\n',
      },
    );
    await service.disconnect();

    await service.connect(
      protocol: VpnProtocol.openVpn,
      profile: const <String, dynamic>{
        'ovpn_config': 'client\nremote 138.199.204.139 1194\n',
      },
    );
    await service.disconnect();

    await service.connect(
      protocol: VpnProtocol.ikev2,
      profile: const <String, dynamic>{
        'server': '138.199.204.139',
        'username': 'test-user',
        'password': 'test-pass',
        'auth_method': 'eap-mschapv2',
      },
    );

    expect(connectProtocols, <String>['wireguard', 'openvpn', 'ikev2']);
  });
}
