import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Stub flutter_secure_storage platform channel (unavailable in test harness)
    final store = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final args = methodCall.arguments is Map
            ? Map<String, dynamic>.from(methodCall.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
        switch (methodCall.method) {
          case 'read':
            return key == null ? null : store[key];
          case 'write':
            if (key != null) store[key] = args['value']?.toString();
            return null;
          case 'delete':
            if (key != null) store.remove(key);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          case 'readAll':
            return Map<String, String>.fromEntries(
              store.entries
                  .where((e) => e.value != null)
                  .map((e) => MapEntry(e.key, e.value!)),
            );
        }
        return null;
      },
    );
  });

  test('VpnStateNotifier transitions through connect and disconnect', () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('us-chi');

    await notifier.connect();
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await notifier.disconnect();
    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
  });

  test('VpnStateNotifier allows auto-select server', () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('de-nue-1');
    expect(container.read(vpnStateProvider).selectedServerId, 'de-nue-1');
    notifier.selectServer(null);
    expect(container.read(vpnStateProvider).selectedServerId, isNull);

    await notifier.connect();

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.connected);
  });

  test(
      'VpnStateNotifier cannot remain connected when kill switch hooks present and network drops',
      () async {
    final service = MockVpnService(
        connectDelay: Duration.zero, disconnectDelay: Duration.zero);
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await SecureStorage().saveString(
      SecureStorage.vpnProfileConfigKey,
      'PostUp = sh -c "iptables -I OUTPUT -j REJECT"\n',
    );
    await notifier.handleConnectivityChange(hasNetwork: false);
    expect(container.read(vpnStateProvider).status, VpnStatus.error);
  });

  test('VpnStateNotifier does not mark connected when native connect fails',
      () async {
    final service = _FailingVpnService();
    final container = ProviderContainer(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.connect();

    final state = container.read(vpnStateProvider);
    expect(state.status, VpnStatus.error);
    expect(state.lastTunnelStartOk, isFalse);
  });
}

class _FailingVpnService implements VpnService {
  @override
  bool get isNativeAvailable => false;

  @override
  Future<VpnStatus> connect({required VpnProtocol protocol, String? config}) {
    throw VpnServiceException('vpn_connect_failed', 'native connect failed');
  }

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;

  @override
  VpnStatus getStatus() => VpnStatus.disconnected;
}
