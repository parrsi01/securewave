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
    var activeProtocol = '';

    String interfaceFor(String protocol) {
      switch (protocol) {
        case 'wireguard':
          return 'sw-wg';
        case 'ikev2':
          return 'ipsec0';
        case 'openvpn':
          return 'tun0';
        default:
          return '';
      }
    }

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
          final args = Map<dynamic, dynamic>.from(call.arguments as Map);
          activeProtocol = args['protocol']?.toString() ?? '';
          return null;
        case 'disconnect':
          nativeConnected = false;
          activeProtocol = '';
          return null;
        case 'getStatus':
          return nativeConnected ? 'connected' : 'disconnected';
        case 'getTrafficStats':
          return <String, Object?>{
            'connected': nativeConnected,
            'protocol': activeProtocol,
            'interface': interfaceFor(activeProtocol),
            'rx_bytes': 1024,
            'tx_bytes': 512,
            'timestamp_ms': 1,
          };
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
    const activeProtocol = 'openvpn';

    String interfaceFor(String protocol) {
      switch (protocol) {
        case 'wireguard':
          return 'sw-wg';
        case 'ikev2':
          return 'ipsec0';
        case 'openvpn':
          return 'tun0';
        default:
          return '';
      }
    }

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
        case 'getTrafficStats':
          return <String, Object?>{
            'connected': nativeConnected,
            'protocol': activeProtocol,
            'interface': interfaceFor(activeProtocol),
            'rx_bytes': 2048,
            'tx_bytes': 1024,
            'timestamp_ms': 1,
          };
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

  testWidgets('reconnects when native tunnel protocol does not match request',
      (tester) async {
    var nativeConnected = true;
    var connectCalls = 0;
    var activeProtocol = 'openvpn';

    String interfaceFor(String protocol) {
      switch (protocol) {
        case 'wireguard':
          return 'sw-wg';
        case 'ikev2':
          return 'ipsec0';
        case 'openvpn':
          return 'tun0';
        default:
          return '';
      }
    }

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
          final args = Map<dynamic, dynamic>.from(call.arguments as Map);
          activeProtocol = args['protocol']?.toString() ?? '';
          return null;
        case 'disconnect':
          nativeConnected = false;
          activeProtocol = '';
          return null;
        case 'getStatus':
          return nativeConnected ? 'connected' : 'disconnected';
        case 'getTrafficStats':
          return <String, Object?>{
            'connected': nativeConnected,
            'protocol': activeProtocol,
            'interface': interfaceFor(activeProtocol),
            'rx_bytes': 4096,
            'tx_bytes': 2048,
            'timestamp_ms': 1,
          };
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
    expect(activeProtocol, 'wireguard');
  });

  testWidgets('supports reconnect and protocol switching sequence',
      (tester) async {
    var nativeConnected = false;
    final connectProtocols = <String>[];
    var activeProtocol = '';

    String interfaceFor(String protocol) {
      switch (protocol) {
        case 'wireguard':
          return 'sw-wg';
        case 'ikev2':
          return 'ipsec0';
        case 'openvpn':
          return 'tun0';
        default:
          return '';
      }
    }

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
          activeProtocol = args['protocol']?.toString() ?? '';
          nativeConnected = true;
          return null;
        case 'disconnect':
          nativeConnected = false;
          activeProtocol = '';
          return null;
        case 'getStatus':
          return nativeConnected ? 'connected' : 'disconnected';
        case 'getTrafficStats':
          return <String, Object?>{
            'connected': nativeConnected,
            'protocol': activeProtocol,
            'interface': interfaceFor(activeProtocol),
            'rx_bytes': 1024,
            'tx_bytes': 512,
            'timestamp_ms': 1,
          };
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
