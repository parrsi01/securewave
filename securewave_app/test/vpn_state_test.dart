import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

class _MemoryStorage extends SecureStorage {
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

  @override
  Future<int?> getInt(String key) async => int.tryParse(values[key] ?? '');

  @override
  Future<void> saveInt(String key, int value) async {
    values[key] = value.toString();
  }
}

class _AuthenticatedSession extends AuthSession {
  _AuthenticatedSession() : super(storage: _MemoryStorage());

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}

class _RecordingVpnService implements VpnService {
  _RecordingVpnService({this.connectGate});

  final Completer<void>? connectGate;
  VpnStatus status = VpnStatus.disconnected;
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<VpnStatus> connect({required String config}) async {
    connectCalls += 1;
    status = VpnStatus.connecting;
    await connectGate?.future;
    status = VpnStatus.connected;
    return status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    disconnectCalls += 1;
    status = VpnStatus.disconnected;
    return status;
  }

  @override
  Future<VpnTrafficStats> getTrafficStats() async =>
      VpnTrafficStats.unavailable;

  @override
  Future<VpnRuntimeStatus> refreshRuntimeStatus() async =>
      VpnRuntimeStatus(status: status);
}

class _PresetVpnNotifier extends VpnStateNotifier {
  _PresetVpnNotifier(super.ref, VpnState initial) {
    state = initial;
  }

  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<void> connect() async {
    connectCalls += 1;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
  }
}

const _wireGuardServer = ServerRegion(
  id: 'beta-one',
  name: 'SecureWave Beta',
  location: 'Nuremberg, Germany',
  health: 'healthy',
  supportedProtocols: <String>['wireguard'],
);

const _freePlan = UserPlan(
  name: 'Free',
  isPremium: false,
  dataCapGb: 5,
  usedGb: 1.6,
);

void main() {
  test('VpnStateNotifier uses the existing connect and disconnect services',
      () async {
    final service = _RecordingVpnService();
    final storage = _MemoryStorage();
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith(
          (_) => const AppConfig(
            apiBaseUrl: 'https://api.example.test',
            demoMode: true,
          ),
        ),
        secureStorageProvider.overrideWithValue(storage),
        vpnServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.ensureInitialized();
    await notifier.connect();
    expect(service.connectCalls, 1);
    expect(container.read(vpnStateProvider).status, VpnStatus.connected);

    await notifier.disconnect();
    expect(service.disconnectCalls, 1);
    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
  });

  test('VpnStateNotifier ignores repeated interaction while connect is busy',
      () async {
    final gate = Completer<void>();
    final service = _RecordingVpnService(connectGate: gate);
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith(
          (_) => const AppConfig(
            apiBaseUrl: 'https://api.example.test',
            demoMode: true,
          ),
        ),
        secureStorageProvider.overrideWithValue(_MemoryStorage()),
        vpnServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.ensureInitialized();

    final first = notifier.connect();
    await Future<void>.delayed(Duration.zero);
    final second = notifier.connect();
    expect(service.connectCalls, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(service.connectCalls, 1);
  });

  test('selection preserves null auto-select and recovers stale servers',
      () async {
    final storage = _MemoryStorage();
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith(
          (_) => const AppConfig(
            apiBaseUrl: 'https://api.example.test',
            demoMode: true,
          ),
        ),
        secureStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(vpnStateProvider.notifier);
    await notifier.ensureInitialized();

    await notifier.selectServer('beta-one');
    expect(container.read(vpnStateProvider).selectedServerId, 'beta-one');
    expect(storage.values[SecureStorage.selectedServerKey], 'beta-one');

    expect(await notifier.recoverStaleServerSelection(['replacement']), isTrue);
    expect(container.read(vpnStateProvider).selectedServerId, isNull);
    expect(storage.values, isNot(contains(SecureStorage.selectedServerKey)));
  });

  for (final status in VpnStatus.values) {
    testWidgets('dashboard presents ${status.name} with text and icon',
        (tester) async {
      final notifier = await _pumpDashboard(
        tester,
        state: VpnState(
          status: status,
          healthLabel: status == VpnStatus.error ? 'Unavailable' : 'Waiting',
          errorMessage: status == VpnStatus.error
              ? 'The helper could not start WireGuard.'
              : null,
        ),
      );

      expect(find.text(_statusLabel(status)), findsWidgets);
      expect(find.byKey(const ValueKey('vpn-status-chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('connection-action')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(notifier.connectCalls, 0);
      expect(notifier.disconnectCalls, 0);
    });
  }

  testWidgets('dashboard action delegates connect and disconnect to notifier',
      (tester) async {
    var notifier = await _pumpDashboard(tester);
    await tester.tap(find.byKey(const ValueKey('connection-action')));
    await tester.pump();
    expect(notifier.connectCalls, 1);

    notifier = await _pumpDashboard(
      tester,
      state: const VpnState(status: VpnStatus.connected),
    );
    await tester.tap(find.byKey(const ValueKey('connection-action')));
    await tester.pump();
    expect(notifier.disconnectCalls, 1);
  });

  testWidgets('dashboard disables action while busy or without WG evidence',
      (tester) async {
    await _pumpDashboard(
      tester,
      state: const VpnState(status: VpnStatus.connecting),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('connection-action')),
          )
          .onPressed,
      isNull,
    );

    await _pumpDashboard(
      tester,
      servers: const [
        ServerRegion(
          id: 'unavailable',
          name: 'Unavailable beta target',
          health: 'offline',
          supportedProtocols: <String>['wireguard'],
        ),
      ],
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('connection-action')),
          )
          .onPressed,
      isNull,
    );
    expect(
        find.byKey(const ValueKey('connection-unavailable')), findsOneWidget);
  });

  testWidgets('dashboard renders auto-select and explicit server location',
      (tester) async {
    await _pumpDashboard(tester);
    expect(find.text('Auto-select'), findsWidgets);

    await _pumpDashboard(
      tester,
      state: const VpnState(selectedServerId: 'beta-one'),
    );
    expect(find.text('Nuremberg, Germany'), findsWidgets);
  });

  testWidgets('5 GB, exhausted, zero-cap, and unlimited plans stay bounded',
      (tester) async {
    await _pumpDashboard(tester);
    expect(find.text('3.4 GB remaining of 5 GB'), findsOneWidget);
    expect(_progress(tester), closeTo(0.32, 0.0001));

    await _pumpDashboard(
      tester,
      plan: const UserPlan(
        name: 'Free',
        isPremium: false,
        dataCapGb: 5,
        usedGb: 9,
      ),
    );
    expect(find.text('0 GB remaining of 5 GB'), findsOneWidget);
    expect(_progress(tester), 1);

    await _pumpDashboard(
      tester,
      plan: const UserPlan(
        name: 'Free',
        isPremium: false,
        dataCapGb: 0,
        usedGb: double.infinity,
      ),
    );
    expect(find.text('No data allowance'), findsOneWidget);
    expect(_progress(tester), 0);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);

    await _pumpDashboard(
      tester,
      plan: const UserPlan(
        name: 'Unlimited',
        isPremium: true,
        dataCapGb: 0,
        usedGb: 2,
      ),
    );
    expect(find.text('Unlimited data'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('allowance-progress')),
          )
          .value,
      isNull,
    );
  });

  testWidgets('dashboard contains no fake telemetry', (tester) async {
    await _pumpDashboard(tester);
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n')
        .toLowerCase();
    for (final forbidden in const [
      'public ip',
      'latency',
      'session duration',
      'upload rate',
      'download rate',
      'encryption grade',
      'protected',
    ]) {
      expect(rendered, isNot(contains(forbidden)));
    }
  });
}

Future<_PresetVpnNotifier> _pumpDashboard(
  WidgetTester tester, {
  VpnState state = const VpnState(),
  List<ServerRegion> servers = const [_wireGuardServer],
  UserPlan plan = _freePlan,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late _PresetVpnNotifier notifier;
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appConfigProvider.overrideWith(
          (_) => const AppConfig(
            apiBaseUrl: 'https://api.example.test',
            demoMode: true,
          ),
        ),
        authSessionProvider.overrideWith((_) => _AuthenticatedSession()),
        serversProvider.overrideWith((_) async => servers),
        userPlanProvider.overrideWith((_) async => plan),
        vpnStateProvider.overrideWith((ref) {
          notifier = _PresetVpnNotifier(ref, state);
          return notifier;
        }),
      ],
      child: const SecureWaveApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump();
  return notifier;
}

double? _progress(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('allowance-progress')),
    )
    .value;

String _statusLabel(VpnStatus status) => switch (status) {
      VpnStatus.disconnected => 'Disconnected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.connected => 'Connected',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.error => 'Connection error',
    };
