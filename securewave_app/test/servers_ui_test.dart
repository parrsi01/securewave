import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

class _Storage extends SecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<void> saveToken(String accessToken) async {}

  @override
  Future<void> clearToken() async {}

  @override
  Future<void> clearVpnRuntimeState() async => values.clear();

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> saveString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Session extends AuthSession {
  _Session() : super(storage: _Storage());

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}

const _completeServer = ServerRegion(
  id: 'beta-one',
  name: 'SecureWave Beta',
  location: 'Nuremberg, Germany',
  city: 'Nuremberg',
  country: 'Germany',
  latencyMs: 31,
  loadPercent: 18.4,
  health: 'healthy',
  supportedProtocols: <String>['wireguard'],
);

void main() {
  testWidgets('one returned location and Auto-select look intentional',
      (tester) async {
    final container = await _pumpServers(tester, servers: [_completeServer]);
    addTearDown(container.dispose);

    expect(find.text('Servers'), findsWidgets);
    expect(
      find.text(
        'The Linux beta currently uses a limited, verified location catalog.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('server-auto-select')), findsOneWidget);
    expect(find.byKey(const ValueKey('server-location-0')), findsOneWidget);
    expect(find.text('SecureWave Beta'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('server-auto-select')),
        matching: find.text('Selected'),
      ),
      findsOneWidget,
    );
    expect(container.read(vpnStateProvider).selectedServerId, isNull);
  });

  testWidgets('explicit location selection preserves selectedServerId',
      (tester) async {
    final container = await _pumpServers(tester, servers: [_completeServer]);
    addTearDown(container.dispose);

    await tester.tap(find.byKey(const ValueKey('server-location-0')));
    await tester.pump();
    expect(container.read(vpnStateProvider).selectedServerId, 'beta-one');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('server-location-0')),
        matching: find.text('Selected'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('supplied city country latency load health and protocol render',
      (tester) async {
    final container = await _pumpServers(tester, servers: [_completeServer]);
    addTearDown(container.dispose);

    for (final value in const [
      'Nuremberg',
      'Germany',
      '31 ms',
      '18% load',
      'healthy',
      'WireGuard',
    ]) {
      expect(find.text(value), findsOneWidget);
    }
  });

  testWidgets('optional server fields are omitted cleanly', (tester) async {
    final container = await _pumpServers(
      tester,
      servers: const [
        ServerRegion(
          id: 'minimal',
          name: 'SecureWave Beta',
          supportedProtocols: <String>['wireguard'],
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(find.textContaining(' ms'), findsNothing);
    expect(find.textContaining('% load'), findsNothing);
    expect(find.text('Nuremberg'), findsNothing);
    expect(find.text('Germany'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and error catalogs have explicit states', (tester) async {
    var container = await _pumpServers(tester, servers: const []);
    addTearDown(container.dispose);
    expect(find.byKey(const ValueKey('servers-empty')), findsOneWidget);
    expect(find.text('No locations available'), findsOneWidget);

    container = await _pumpServers(
      tester,
      error: StateError('Catalog request failed safely.'),
    );
    addTearDown(container.dispose);
    expect(find.byKey(const ValueKey('servers-error')), findsOneWidget);
    expect(find.text('Locations unavailable'), findsOneWidget);
  });

  testWidgets('unavailable and unevidenced servers cannot be selected',
      (tester) async {
    final container = await _pumpServers(
      tester,
      servers: const [
        ServerRegion(
          id: 'offline',
          name: 'Offline location',
          health: 'offline',
          supportedProtocols: <String>['wireguard'],
        ),
        ServerRegion(
          id: 'unknown-protocol',
          name: 'Unevidenced location',
          health: 'healthy',
        ),
      ],
    );
    addTearDown(container.dispose);

    for (var index = 0; index < 2; index++) {
      final inkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(ValueKey('server-location-$index')),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWell.onTap, isNull);
    }
    expect(
        find.text('This location is currently unavailable.'), findsOneWidget);
    expect(
      find.text('WireGuard support is not verified for this location.'),
      findsOneWidget,
    );
  });

  testWidgets('stale selection recovers to Auto-select', (tester) async {
    final container = await _pumpServers(
      tester,
      servers: [_completeServer],
      selectedServerId: 'removed-location',
    );
    addTearDown(container.dispose);

    await tester.pump();
    expect(container.read(vpnStateProvider).selectedServerId, isNull);
    expect(find.byKey(const ValueKey('stale-server-notice')), findsOneWidget);
  });

  testWidgets('catalog does not expose endpoint key config or internal ID',
      (tester) async {
    final container = await _pumpServers(tester, servers: [_completeServer]);
    addTearDown(container.dispose);
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n');

    for (final forbidden in const [
      'beta-one',
      '198.51.100.8',
      'PrivateKey',
      '[Interface]',
      '[Peer]',
    ]) {
      expect(rendered, isNot(contains(forbidden)));
    }
  });

  testWidgets('server catalog has no overflow on mobile and desktop',
      (tester) async {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      final container = await _pumpServers(
        tester,
        size: size,
        servers: [_completeServer],
      );
      addTearDown(container.dispose);
      expect(tester.takeException(), isNull);
    }
  });
}

Future<ProviderContainer> _pumpServers(
  WidgetTester tester, {
  List<ServerRegion>? servers,
  Object? error,
  String? selectedServerId,
  Size size = const Size(1280, 800),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final storage = _Storage();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWith(
        (_) => const AppConfig(
          apiBaseUrl: 'https://api.example.test',
          demoMode: true,
        ),
      ),
      authSessionProvider.overrideWith((_) => _Session()),
      secureStorageProvider.overrideWithValue(storage),
      serversProvider.overrideWith((_) {
        if (error != null) return Future<List<ServerRegion>>.error(error);
        return Future.value(servers ?? const <ServerRegion>[]);
      }),
    ],
  );
  final notifier = container.read(vpnStateProvider.notifier);
  await notifier.ensureInitialized();
  if (selectedServerId != null) await notifier.selectServer(selectedServerId);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      key: UniqueKey(),
      container: container,
      child: const SecureWaveApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (size.width < 760) {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-navigation')),
        matching: find.text('Servers'),
      ),
    );
  } else {
    await tester.tap(find.byKey(const ValueKey('desktop-nav-servers')));
  }
  await tester.pumpAndSettle();
  return container;
}
