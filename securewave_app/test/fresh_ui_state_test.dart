import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/constants/app_constants.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/user_account.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String?> store;
  late List<MethodCall> linkCalls;

  setUp(() {
    store = <String, String?>{'access_token': 'test-token'};
    linkCalls = <MethodCall>[];
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
                  .where((entry) => entry.value != null)
                  .map((entry) => MapEntry(entry.key, entry.value!)),
            );
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('securewave/links'),
      (call) async {
        linkCalls.add(call);
        return true;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('securewave/links'),
      null,
    );
  });

  testWidgets('home surfaces the empty catalog state', (tester) async {
    await _pumpApp(
      tester,
      serversOverride: serversProvider.overrideWith((ref) async => const []),
    );

    expect(find.text('No regions available'), findsOneWidget);
    expect(find.text('Auto-select will stay active until the catalog returns.'),
        findsOneWidget);
  });

  testWidgets('home surfaces the catalog error state', (tester) async {
    await _pumpApp(
      tester,
      serversOverride: serversProvider.overrideWith(
        (ref) async => throw StateError('catalog failed'),
      ),
    );

    expect(find.text('Regions unavailable'), findsOneWidget);
    expect(find.textContaining('catalog failed'), findsOneWidget);
  });

  testWidgets('zero-cap usage renders without broken values', (tester) async {
    await _pumpApp(
      tester,
      planOverride: userPlanProvider.overrideWith(
        (ref) async => const UserPlan(
          name: 'Free',
          isPremium: false,
          dataCapGb: 0,
          usedGb: 1.2,
        ),
      ),
    );

    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();

    expect(find.text('Usage'), findsWidgets);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('connected dashboard renders without a looping decoration',
      (tester) async {
    await _pumpApp(
      tester,
      vpnServiceOverride:
          vpnServiceProvider.overrideWithValue(_ConnectedVpnService()),
    );

    expect(find.text('DISCONNECT'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('Help opens the verified support URL through the Linux channel',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    expect(linkCalls, hasLength(1));
    expect(linkCalls.single.method, 'openUrl');
    expect(
      linkCalls.single.arguments,
      {'url': AppConstants.supportUrlFallback},
    );
  });

  testWidgets('legacy hidden selections cannot leave Connect disabled',
      (tester) async {
    store['vpn_protocol'] = 'openvpn';
    store['selected_server_id'] = 'retired-server';
    final vpnService = _ConnectTrackingVpnService();

    await _pumpApp(
      tester,
      vpnServiceOverride: vpnServiceProvider.overrideWithValue(vpnService),
      apiClientOverride: apiClientProvider.overrideWithValue(_NoopApiClient()),
      serversOverride: serversProvider.overrideWith(
        (ref) async => const [
          ServerRegion(
            id: 'current-server',
            name: 'Current region',
            country: 'Germany',
            latencyMs: 18,
            supportedProtocols: ['wireguard'],
          ),
        ],
      ),
    );

    expect(find.text('WireGuard · Current region'), findsOneWidget);
    await tester.tap(find.text('CONNECT'));
    await tester.pumpAndSettle();

    expect(vpnService.connectCalls, 1);
    expect(vpnService.lastProtocol, VpnProtocol.wireGuard);
    expect(store['vpn_protocol'], isNull);
    expect(store['selected_server_id'], isNull);
    expect(find.text('DISCONNECT'), findsOneWidget);
  });

  testWidgets('sign out cleans up a VPN state that is already in error',
      (tester) async {
    final vpnService = _SignOutTrackingVpnService();
    await _pumpApp(
      tester,
      vpnServiceOverride: vpnServiceProvider.overrideWithValue(vpnService),
      apiClientOverride: apiClientProvider.overrideWithValue(_NoopApiClient()),
    );

    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(vpnService.disconnectCalls, 1);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  Override? serversOverride,
  Override? planOverride,
  Override? vpnServiceOverride,
  Override? apiClientOverride,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vpnServiceOverride ??
            vpnServiceProvider.overrideWithValue(MockVpnService()),
        apiClientOverride ??
            apiClientProvider
                .overrideWithValue(ApiClient(AppConfig.defaults())),
        appConfigProvider.overrideWith(
          (ref) => AppConfig(
            apiBaseUrl: 'https://api.example.test',
            portalUrl: 'https://portal.example.test',
            upgradeUrl: 'https://upgrade.example.test',
            useMockApi: false,
            resetSessionOnBoot: false,
          ),
        ),
        currentUserProvider.overrideWith(
          (ref) async => const UserAccount(
            id: 1,
            email: 'person@example.test',
            isActive: true,
            emailVerified: true,
            has2fa: false,
            subscriptionStatus: 'free',
          ),
        ),
        planOverride ??
            userPlanProvider.overrideWith(
              (ref) async => const UserPlan(
                name: 'Free',
                isPremium: false,
                dataCapGb: 5,
                usedGb: 1.2,
              ),
            ),
        serversOverride ??
            serversProvider.overrideWith(
              (ref) async => const [
                ServerRegion(
                  id: 'us-chi',
                  name: 'Chicago',
                  country: 'United States',
                  latencyMs: 24,
                ),
              ],
            ),
      ],
      child: const SecureWaveApp(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Screenshot tests can request deterministic fixed-frame advancement.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }
}

class _ConnectedVpnService implements VpnService {
  @override
  bool get isNativeAvailable => true;

  @override
  bool canConnectProtocol(VpnProtocol protocol) =>
      protocol == VpnProtocol.wireGuard;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
  }) async =>
      VpnStatus.connected;

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;

  @override
  VpnStatus getStatus() => VpnStatus.connected;
}

class _SignOutTrackingVpnService implements VpnService {
  int disconnectCalls = 0;

  @override
  bool get isNativeAvailable => true;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
  }) async =>
      VpnStatus.connected;

  @override
  Future<VpnStatus> disconnect() async {
    disconnectCalls += 1;
    return VpnStatus.disconnected;
  }

  @override
  VpnStatus getStatus() => VpnStatus.error;
}

class _ConnectTrackingVpnService implements VpnService {
  int connectCalls = 0;
  VpnProtocol? lastProtocol;
  VpnStatus _status = VpnStatus.disconnected;

  @override
  bool get isNativeAvailable => false;

  @override
  bool canConnectProtocol(VpnProtocol protocol) =>
      protocol == VpnProtocol.wireGuard;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) =>
      canConnectProtocol(protocol) ? null : 'Protocol unavailable.';

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
  }) async {
    connectCalls += 1;
    lastProtocol = protocol;
    _status = VpnStatus.connected;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;
}

class _NoopApiClient extends ApiClient {
  _NoopApiClient() : super(AppConfig.defaults());

  @override
  Future<void> notifyVpnDisconnected() async {}

  @override
  Future<void> notifyVpnConnected({
    String? serverId,
    VpnProtocol? protocol,
  }) async {}
}
