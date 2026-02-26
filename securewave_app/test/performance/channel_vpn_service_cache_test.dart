import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('securewave/vpn');

  testWidgets('ChannelVpnService caches capabilities and availability checks',
      (tester) async {
    var now = DateTime.utc(2026, 2, 22, 2, 0, 0);
    final calls = <String, int>{};

    Future<Object?> handler(MethodCall call) async {
      calls.update(call.method, (value) => value + 1, ifAbsent: () => 1);
      switch (call.method) {
        case 'isAvailable':
          return true;
        case 'getCapabilities':
          return <String, Object?>{
            'wireguard': true,
            'openvpn': true,
            'ikev2': true,
            'windows_thread_safe': false,
            'android_vpnservice_based': false,
            'macos_entitlements_ready': false,
          };
        case 'connect':
        case 'disconnect':
          return null;
      }
      return null;
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = ChannelVpnService(
      capabilitiesCacheTtl: const Duration(seconds: 5),
      availabilityCacheTtl: const Duration(seconds: 5),
      clock: () => now,
    );

    // Allow constructor best-effort availability refresh to run.
    await tester.pump();

    final startupAvailabilityCalls = calls['isAvailable'] ?? 0;
    expect(startupAvailabilityCalls, 1);

    final firstCaps = await service.getCapabilities();
    final secondCaps = await service.getCapabilities();
    expect(firstCaps.openVpn, isTrue);
    expect(secondCaps.ikev2, isTrue);
    expect(calls['getCapabilities'], 1,
        reason: 'Second call should hit in-memory cache.');

    await service.connect(
      protocol: VpnProtocol.openVpn,
      profile: const <String, dynamic>{'ovpn_config': 'client\nremote 1.1.1.1'},
    );
    expect(calls['connect'], 1);
    expect(calls['getCapabilities'], 1,
        reason: 'Connect should reuse cached capabilities.');
    expect(calls['isAvailable'], startupAvailabilityCalls,
        reason: 'Connect should reuse cached availability within TTL.');

    await service.disconnect();
    expect(calls['disconnect'], 1);
    expect(calls['isAvailable'], startupAvailabilityCalls,
        reason: 'Disconnect should reuse cached availability within TTL.');

    // ignore: avoid_print
    print(
      'PERF channel_vpn_service_cache '
      'startup_isAvailable_calls=$startupAvailabilityCalls '
      'cached_getCapabilities_calls=${calls['getCapabilities'] ?? 0} '
      'cached_isAvailable_calls=${calls['isAvailable'] ?? 0}',
    );

    now = now.add(const Duration(seconds: 6));
    await service.getCapabilities();
    expect(calls['getCapabilities'], 2,
        reason: 'Capabilities cache must refresh after TTL expiry.');

    // ignore: avoid_print
    print(
      'PERF channel_vpn_service_cache_after_ttl '
      'getCapabilities_calls=${calls['getCapabilities'] ?? 0}',
    );
  });
}
