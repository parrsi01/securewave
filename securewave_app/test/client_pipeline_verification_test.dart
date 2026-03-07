import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/logging/app_logger.dart';
import 'package:securewave_app/core/models/diagnostics.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/traffic_snapshot.dart';
import 'package:securewave_app/core/models/tunnel_health_snapshot.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/diagnostics_service.dart';
import 'package:securewave_app/core/services/traffic_stats_service.dart';
import 'package:securewave_app/core/services/tunnel_status_service.dart';
import 'package:securewave_app/core/services/vm_environment.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/adblock_state.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/client_settings_state.dart';
import 'package:securewave_app/core/state/network_lock_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/features/account/account_page.dart';
import 'package:securewave_app/features/settings/settings_page.dart';
import 'package:securewave_app/features/vpn/vpn_page.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.logStream.value = <AppLogEntry>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('securewave/adblock'),
      (MethodCall methodCall) async => null,
    );
  });

  testWidgets('settings toggles update mapped runtime controllers',
      (WidgetTester tester) async {
    final api = RecordingApiClient();
    final vpn = RecordingVpnService();
    final container = _buildContainer(api: api, vpnService: vpn);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final switches = find.byType(Switch);

    await tester.tap(switches.at(0));
    await tester.pump();
    await tester.tap(switches.at(1));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(switches.at(2));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pump();
    await tester.tap(switches.at(3));
    await tester.pump();

    expect(container.read(clientSettingsProvider).autoConnect, isFalse);
    expect(container.read(clientSettingsProvider).autoReconnect, isFalse);
    expect(
      container.read(clientSettingsProvider).bestEffortKillSwitch,
      isFalse,
    );
    expect(container.read(adblockStateProvider).blockAds, isFalse);
  });

  testWidgets('vpn page connect and disconnect follow mapped pipeline',
      (WidgetTester tester) async {
    final api = RecordingApiClient();
    final vpn = RecordingVpnService();
    final container = _buildContainer(api: api, vpnService: vpn);
    addTearDown(container.dispose);

    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'session-token');
    container.read(vpnStateProvider.notifier).selectServer('us-chi');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: const VpnPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Quick Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(vpnStateProvider).status, VpnStatus.connected);
    expect(api.calls, containsAllInOrder(<String>[
      'GET /vpn/servers',
      'POST /vpn/profile',
    ]));
    expect(vpn.calls, contains('connect:wireguard'));

    await tester.tap(find.text('Disconnect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
    expect(vpn.calls, contains('disconnect'));
    expect(
      AppLogger.logStream.value
          .map((AppLogEntry entry) => entry.category)
          .contains(AppLogCategory.ui),
      isTrue,
    );
  });

  testWidgets('account page exposes backend devices and local sign out',
      (WidgetTester tester) async {
    final api = RecordingApiClient();
    final vpn = RecordingVpnService();
    final container = _buildContainer(api: api, vpnService: vpn);
    addTearDown(container.dispose);

    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'session-token');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: const AccountPage(),
        ),
      ),
    );
    final devices = await container.read(vpnDevicesProvider.future);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(devices, isNotEmpty);
    expect(devices.first['name'], 'Test Device');
    expect(api.calls, contains('GET /vpn/devices'));
    await tester.scrollUntilVisible(
      find.text('Sign out on this device'),
      250,
      scrollable: find.byType(Scrollable),
    );
    await tester.pump();

    await tester.tap(find.text('Sign out on this device'));
    await tester.pump();

    expect(container.read(authSessionProvider).isAuthenticated, isFalse);
  });

  test('stress connect and disconnect loop remains stable for 50 cycles',
      () async {
    final api = RecordingApiClient();
    final vpn = RecordingVpnService();
    final container = _buildContainer(api: api, vpnService: vpn);
    addTearDown(container.dispose);

    await container
        .read(authSessionProvider)
        .setSession(accessToken: 'session-token');
    final notifier = container.read(vpnStateProvider.notifier);
    notifier.selectServer('us-chi');

    for (var index = 0; index < 50; index++) {
      await notifier.connect();
      expect(container.read(vpnStateProvider).status, VpnStatus.connected);
      await notifier.disconnect();
      expect(container.read(vpnStateProvider).status, VpnStatus.disconnected);
    }

    expect(vpn.connectCount, 50);
    expect(vpn.disconnectCount, 50);
    expect(container.read(vpnStateProvider).errorMessage, isNull);
  });
}

ProviderContainer _buildContainer({
  required RecordingApiClient api,
  required RecordingVpnService vpnService,
}) {
  return ProviderContainer(
    overrides: <Override>[
      appConfigProvider.overrideWith(
        (Ref ref) => AppConfig(
          apiBaseUrl: 'https://example.com',
          portalUrl: 'https://portal.example.com',
          upgradeUrl: 'https://upgrade.example.com',
          adblockListUrl: 'https://adblock.example.com/list.txt',
          useMockApi: false,
          resetSessionOnBoot: false,
        ),
      ),
      apiClientProvider.overrideWithValue(api),
      vpnServiceProvider.overrideWithValue(vpnService),
      vmEnvironmentProvider.overrideWithValue(const VmEnvironment(
        isVirtualMachine: false,
        safeModeEnabled: false,
        reason: null,
      )),
      diagnosticsServiceProvider.overrideWith(
        (Ref ref) => FakeDiagnosticsService(ref),
      ),
      tunnelStatusServiceProvider.overrideWithValue(
        FakeTunnelStatusService(vpnService),
      ),
      trafficStatsServiceProvider.overrideWithValue(FakeTrafficStatsService()),
    ],
  );
}

class RecordingApiClient extends ApiClient {
  RecordingApiClient()
      : super(
          AppConfig(
            apiBaseUrl: 'https://example.com',
            portalUrl: 'https://portal.example.com',
            upgradeUrl: 'https://upgrade.example.com',
            adblockListUrl: 'https://adblock.example.com/list.txt',
            useMockApi: false,
            resetSessionOnBoot: false,
          ),
          session: AuthSession(),
          vmEnvironment: const VmEnvironment(
            isVirtualMachine: false,
            safeModeEnabled: false,
            reason: null,
          ),
          networkLock: const NetworkLockState(),
        );

  final List<String> calls = <String>[];

  @override
  Future<void> healthCheck({bool allowWhenLocked = false}) async {
    calls.add('GET /api/health');
  }

  @override
  Future<List<ServerRegion>> fetchServers({
    bool forceRefresh = false,
    bool allowWhenLocked = false,
  }) async {
    calls.add('GET /vpn/servers');
    return const <ServerRegion>[
      ServerRegion(
        id: 'us-chi',
        name: 'Chicago, IL',
        country: 'United States',
        latencyMs: 24,
      ),
    ];
  }

  @override
  Future<UserPlan> fetchUserPlan({
    bool forceRefresh = false,
    bool allowWhenLocked = false,
  }) async {
    return const UserPlan(
      name: 'Premium',
      isPremium: true,
      dataCapGb: 100,
      usedGb: 12.5,
    );
  }

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    calls.add('POST /auth/login');
    return AuthTokens(accessToken: 'token-$email', refreshToken: 'refresh');
  }

  @override
  Future<AuthTokens?> register({
    required String email,
    required String password,
  }) async {
    calls.add('POST /auth/register');
    return AuthTokens(accessToken: 'token-$email', refreshToken: 'refresh');
  }

  @override
  Future<String> fetchVpnProfile({
    String? serverId,
    bool allowWhenLocked = false,
  }) async {
    calls.add('POST /vpn/profile');
    return 'profile-for-$serverId';
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDevices({
    bool allowWhenLocked = false,
  }) async {
    calls.add('GET /vpn/devices');
    return <Map<String, dynamic>>[
      <String, dynamic>{'id': 'device-1', 'name': 'Test Device'},
    ];
  }
}

class RecordingVpnService implements VpnService {
  final List<String> calls = <String>[];
  VpnStatus _status = VpnStatus.disconnected;

  int get connectCount =>
      calls.where((String call) => call.startsWith('connect:')).length;
  int get disconnectCount =>
      calls.where((String call) => call == 'disconnect').length;

  @override
  bool get isNativeAvailable => true;

  @override
  List<VpnProtocol> get supportedProtocols => const <VpnProtocol>[
        VpnProtocol.wireGuard,
      ];

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
  }) async {
    calls.add('connect:${vpnProtocolStorageValue(protocol)}');
    _status = VpnStatus.connected;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    calls.add('disconnect');
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;
}

class FakeDiagnosticsService extends DiagnosticsService {
  FakeDiagnosticsService(super.ref);

  @override
  Future<List<DiagnosticResult>> run() async {
    return <DiagnosticResult>[
      DiagnosticResult(
        key: 'BACKEND_OK',
        label: 'Backend reachability',
        status: DiagnosticStatus.ok,
        message: 'Verification stub reports backend reachable.',
        checkedAt: DateTime.now(),
      ),
    ];
  }
}

class FakeTunnelStatusService extends TunnelStatusService {
  FakeTunnelStatusService(this._vpnService);

  final RecordingVpnService _vpnService;

  @override
  Future<TunnelHealthSnapshot> getStatus() async {
    if (_vpnService.getStatus() == VpnStatus.connected) {
      return const TunnelHealthSnapshot(
        status: VpnStatus.connected,
        interfaceName: 'utun0',
        interfaceOk: true,
        routingOk: true,
        details: 'Native tunnel verified.',
      );
    }
    return TunnelHealthSnapshot.disconnected;
  }
}

class FakeTrafficStatsService extends TrafficStatsService {
  int _rx = 1000;
  int _tx = 500;

  @override
  Future<TrafficSnapshot> sample({String? preferredInterface}) async {
    _rx += 256;
    _tx += 128;
    return TrafficSnapshot(
      receivedBytes: _rx,
      transmittedBytes: _tx,
      timestamp: DateTime.now(),
      interfaceName: preferredInterface ?? 'utun0',
    );
  }
}
