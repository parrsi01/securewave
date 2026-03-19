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
    String? capturedConfig;

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
          capturedConfig = args['config']?.toString();
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
        case 'getHealthStatus':
          return <String, Object?>{
            'connected': nativeConnected,
            'interface': interfaceFor(activeProtocol),
            'interface_up': nativeConnected,
            'route_present': nativeConnected,
            'policy_routing_present': nativeConnected,
            'fwmark_configured': nativeConnected,
            'networkmanager_unmanaged': nativeConnected,
            'ping_reachable': nativeConnected,
            'traffic_connected': nativeConnected,
            'handshake_present': nativeConnected,
            'handshake_recent': nativeConnected,
            'handshake_age_seconds': nativeConnected ? 5 : -1,
            'watchdog_running': nativeConnected,
            'reconnect_attempts': 0,
            'route_resets': 0,
            'critical_resets': 0,
            'current_downtime_ms': 0,
            'last_downtime_ms': 0,
            'total_downtime_ms': 0,
            'last_watchdog_action': nativeConnected ? 'healthy' : '',
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
        'wireguard_config': '''
[Interface]
PrivateKey = test-private
Address = 10.8.0.2/32

[Peer]
PublicKey = server-public
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.securewave.example:51820
''',
      },
    );
    expect(status, VpnStatus.connected);
    expect(connectCalls, 1);
    expect(capturedConfig, isNotNull);
    expect(capturedConfig, isNot(contains('# SECUREWAVE_ROUTE_GUARD_START')));
    expect(capturedConfig, contains('Endpoint = vpn.securewave.example:51820'));
    expect(capturedConfig, contains('AllowedIPs = 0.0.0.0/0'));

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
        case 'getHealthStatus':
          return <String, Object?>{
            'connected': nativeConnected,
            'interface': interfaceFor(activeProtocol),
            'interface_up': nativeConnected,
            'route_present': nativeConnected,
            'policy_routing_present': nativeConnected,
            'fwmark_configured': true,
            'networkmanager_unmanaged': true,
            'ping_reachable': nativeConnected,
            'traffic_connected': nativeConnected,
            'handshake_present': true,
            'handshake_recent': true,
            'handshake_age_seconds': 5,
            'watchdog_running': nativeConnected,
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

  testWidgets('parses Linux WireGuard health metadata from native bridge',
      (tester) async {
    Future<Object?> handler(MethodCall call) async {
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'getStatus':
          return 'connected';
        case 'getTrafficStats':
          return <String, Object?>{
            'connected': true,
            'protocol': 'wireguard',
            'interface': 'sw-wg',
            'rx_bytes': 8192,
            'tx_bytes': 4096,
            'timestamp_ms': 1,
          };
        case 'getHealthStatus':
          return <String, Object?>{
            'connected': true,
            'interface': 'sw-wg',
            'interface_up': true,
            'route_present': true,
            'policy_routing_present': true,
            'fwmark_configured': true,
            'networkmanager_unmanaged': true,
            'ping_reachable': true,
            'traffic_connected': true,
            'handshake_present': true,
            'handshake_recent': true,
            'handshake_age_seconds': 7,
            'watchdog_running': true,
            'reconnect_attempts': 2,
            'route_resets': 3,
            'critical_resets': 1,
            'current_downtime_ms': 250,
            'last_downtime_ms': 500,
            'total_downtime_ms': 750,
            'last_watchdog_action': 'policy_routing_reapplied',
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

    final snapshot = await service.fetchHealthSnapshot();
    expect(snapshot.interfaceUp, isTrue);
    expect(snapshot.routePresent, isTrue);
    expect(snapshot.policyRoutingPresent, isTrue);
    expect(snapshot.handshakeRecent, isTrue);
    expect(snapshot.handshakeAgeSeconds, 7);
    expect(snapshot.watchdogRunning, isTrue);
    expect(snapshot.routeResets, 3);
    expect(snapshot.reconnectAttempts, 2);
    expect(snapshot.currentDowntimeMs, 250);
    expect(snapshot.lastWatchdogAction, 'policy_routing_reapplied');
    expect(snapshot.verifiedTunnel, isTrue);
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
        case 'getHealthStatus':
          return <String, Object?>{
            'connected': nativeConnected,
            'interface': interfaceFor(activeProtocol),
            'interface_up': nativeConnected,
            'route_present': nativeConnected,
            'policy_routing_present': nativeConnected,
            'fwmark_configured': true,
            'networkmanager_unmanaged': true,
            'ping_reachable': nativeConnected,
            'traffic_connected': nativeConnected,
            'handshake_present': true,
            'handshake_recent': true,
            'handshake_age_seconds': 5,
            'watchdog_running': nativeConnected,
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
        case 'getHealthStatus':
          return <String, Object?>{
            'connected': nativeConnected,
            'interface': interfaceFor(activeProtocol),
            'interface_up': nativeConnected,
            'route_present': nativeConnected,
            'policy_routing_present': nativeConnected,
            'fwmark_configured': true,
            'networkmanager_unmanaged': true,
            'ping_reachable': nativeConnected,
            'traffic_connected': nativeConnected,
            'handshake_present': true,
            'handshake_recent': true,
            'handshake_age_seconds': 5,
            'watchdog_running': nativeConnected,
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
