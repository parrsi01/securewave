import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/bootstrap/boot_controller.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/protocol_availability.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/user_account.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/services/auth_session.dart';
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

  testWidgets(
      'VPN availability refresh is enabled at idle and disabled while connecting',
      (tester) async {
    await _pumpApp(
      tester,
      apiClientOverride: apiClientProvider.overrideWithValue(
        ApiClient(
          AppConfig(
            apiBaseUrl: 'https://api.example.test',
            portalUrl: 'https://portal.example.test',
            upgradeUrl: 'https://upgrade.example.test',
            useMockApi: true,
            resetSessionOnBoot: false,
          ),
        ),
      ),
      protocolAvailabilityOverride: protocolAvailabilityProvider.overrideWith(
        (ref) async => const {
          VpnProtocol.wireGuard: ProtocolAvailability(
            protocol: VpnProtocol.wireGuard,
            enabled: true,
            serverEnabled: true,
            platformSupported: true,
          ),
          VpnProtocol.openVpn: ProtocolAvailability(
            protocol: VpnProtocol.openVpn,
            enabled: false,
            serverEnabled: false,
            platformSupported: false,
          ),
          VpnProtocol.ikev2: ProtocolAvailability(
            protocol: VpnProtocol.ikev2,
            enabled: false,
            serverEnabled: false,
            platformSupported: false,
          ),
        },
      ),
      serversOverride: serversProvider.overrideWith(
        (ref) async => const [
          ServerRegion(
            id: 'us-chi',
            name: 'Chicago',
            country: 'United States',
            latencyMs: 24,
            supportedProtocols: ['wireguard'],
          ),
        ],
      ),
      vpnServiceOverride: vpnServiceProvider.overrideWithValue(
        MockVpnService(
          connectDelay: const Duration(milliseconds: 100),
          disconnectDelay: Duration.zero,
        ),
      ),
    );

    final refresh = find.widgetWithIcon(IconButton, Icons.refresh_rounded);
    expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);

    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  Override? serversOverride,
  Override? planOverride,
  Override? apiClientOverride,
  Override? protocolAvailabilityOverride,
  Override? vpnServiceOverride,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = AuthSession();
  await session.ensureInitialized();
  await session.setSession(accessToken: 'test-token');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => session),
        bootControllerProvider.overrideWith(
          (ref) => BootController(
            ref,
            initialState: const BootState(status: BootStatus.ready),
          ),
        ),
        apiClientOverride ??
            apiClientProvider.overrideWith(
              (ref) => ApiClient(AppConfig.defaults()),
            ),
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
        protocolAvailabilityOverride ??
            protocolAvailabilityProvider.overrideWith(
              (ref) async => const {},
            ),
        vpnServiceOverride ??
            vpnServiceProvider.overrideWithValue(MockVpnService()),
      ],
      child: const SecureWaveApp(),
    ),
  );
  await tester.pumpAndSettle();
}
