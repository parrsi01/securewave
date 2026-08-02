import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
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

  setUp(() {
    store = <String, String?>{'access_token': 'test-token'};
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
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  testWidgets('server screen renders empty catalog state', (tester) async {
    await _pumpApp(
      tester,
      serversOverride: serversProvider.overrideWith((ref) async => const []),
    );

    await tester.tap(find.text('Servers').last);
    await tester.pumpAndSettle();

    expect(find.text('No regions available'), findsOneWidget);
    expect(find.text('Auto-select will stay active until the catalog returns.'),
        findsOneWidget);
  });

  testWidgets('server screen renders error state', (tester) async {
    await _pumpApp(
      tester,
      serversOverride: serversProvider.overrideWith(
        (ref) async => throw StateError('catalog failed'),
      ),
    );

    await tester.tap(find.text('Servers').last);
    await tester.pumpAndSettle();

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

  testWidgets('sign out cleans up a VPN state that is already in error',
      (tester) async {
    final vpnService = _SignOutTrackingVpnService();
    await _pumpApp(
      tester,
      vpnServiceOverride: vpnServiceProvider.overrideWithValue(vpnService),
      apiClientOverride: apiClientProvider.overrideWithValue(_NoopApiClient()),
    );

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(vpnService.disconnectCalls, 1);
    expect(find.text('Sign in'), findsOneWidget);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  Override? serversOverride,
  Override? planOverride,
  Override? vpnServiceOverride,
  Override? apiClientOverride,
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
  await tester.pumpAndSettle();
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

class _NoopApiClient extends ApiClient {
  _NoopApiClient() : super(AppConfig.defaults());

  @override
  Future<void> notifyVpnDisconnected() async {}
}
