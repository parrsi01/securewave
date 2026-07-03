import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/user_account.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/linux_runtime_setup.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String?> store;

  setUp(() {
    store = <String, String?>{
      'access_token': 'test-token',
      'reset_session_done': 'true',
    };
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

  testWidgets('login screen shows SecureWave logo and brand', (tester) async {
    store.remove('access_token');

    await _pumpApp(tester);

    expect(find.bySemanticsLabel('SecureWave logo'), findsOneWidget);
    expect(find.text('SecureWave'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('register screen keeps logo and confirm password field',
      (tester) async {
    store.remove('access_token');

    await _pumpApp(tester);
    await tester.tap(find.text('Create a new account'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('SecureWave logo'), findsOneWidget);
    expect(find.text('SecureWave'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('server screen renders empty catalog state', (tester) async {
    await _pumpApp(
      tester,
      serversOverride: serversProvider.overrideWith((ref) async => const []),
    );

    await tester.tap(find.byIcon(Icons.public_rounded).last);
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

    await tester.tap(find.byIcon(Icons.public_rounded).last);
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

    await tester.tap(find.byIcon(Icons.person_rounded).last);
    await tester.pumpAndSettle();

    expect(find.text('Usage'), findsWidgets);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-meter')), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('premium unlimited usage renders modern meter', (tester) async {
    await _pumpApp(
      tester,
      planOverride: userPlanProvider.overrideWith(
        (ref) async => const UserPlan(
          name: 'Premium',
          isPremium: true,
          dataCapGb: 0,
          usedGb: 42.1,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.person_rounded).last);
    await tester.pumpAndSettle();

    expect(find.text('Premium'), findsWidgets);
    expect(find.text('Unlimited'), findsWidgets);
    expect(find.byKey(const ValueKey('usage-meter')), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('usage loading state renders without a meter', (tester) async {
    await _pumpApp(
      tester,
      settle: false,
      planOverride: userPlanProvider.overrideWith(
        (ref) => Completer<UserPlan>().future,
      ),
    );

    await tester.tap(find.byIcon(Icons.person_rounded).last);
    await tester.pump();

    expect(find.text('Loading usage'), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-meter')), findsNothing);
  });

  testWidgets('usage error state renders without broken values',
      (tester) async {
    await _pumpApp(
      tester,
      planOverride: userPlanProvider.overrideWith(
        (ref) async => throw StateError('usage failed'),
      ),
    );

    await tester.tap(find.byIcon(Icons.person_rounded).last);
    await tester.pumpAndSettle();

    expect(find.text('Usage could not be loaded.'), findsOneWidget);
    expect(find.byKey(const ValueKey('usage-meter')), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('presentation mode renders simulated tunnel disclosure',
      (tester) async {
    await _pumpApp(tester, simulateTunnel: true);

    expect(
      find.text(
        'Simulated tunnel — presentation mode. Not a real VPN.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('VPN connected'), findsNothing);
  });

  testWidgets('presentation mode labels connected state honestly',
      (tester) async {
    await _pumpApp(
      tester,
      simulateTunnel: true,
      vpnOverride: vpnStateProvider.overrideWith(
        (ref) => _ConnectedVpnStateNotifier(ref),
      ),
    );

    expect(
      find.text('Simulated (not encrypted)', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('VPN connected'), findsNothing);
  });

  testWidgets('connect screen shows native runtime verified status',
      (tester) async {
    await _pumpApp(
      tester,
      runtimeStatusOverride: nativeRuntimeStatusProvider.overrideWith(
        (ref) async => const VpnRuntimeStatus(
          status: VpnStatus.connected,
          protocol: VpnProtocol.openVpn,
        ),
      ),
    );

    expect(
      find.text('Runtime verified: OpenVPN tunnel is active.'),
      findsOneWidget,
    );
  });

  testWidgets('connect screen surfaces helper install action when missing',
      (tester) async {
    await _pumpApp(
      tester,
      extraOverrides: [
        linuxRuntimeInstallStateProvider.overrideWith(
          (ref) async => const LinuxRuntimeInstallState(
            installed: false,
            payloadAvailable: true,
            installedContract: 0,
            requiredContract: 7,
            message: 'SecureWave VPN helper is bundled but not installed.',
          ),
        ),
      ],
    );

    expect(
      find.text('SecureWave VPN helper is bundled but not installed.'),
      findsOneWidget,
    );
    expect(find.text('Install VPN helper'), findsOneWidget);
  });

  testWidgets('settings shows runtime helper install action when missing',
      (tester) async {
    await _pumpApp(
      tester,
      extraOverrides: [
        linuxRuntimeInstallStateProvider.overrideWith(
          (ref) async => const LinuxRuntimeInstallState(
            installed: false,
            payloadAvailable: true,
            installedContract: 0,
            requiredContract: 7,
            message: 'SecureWave VPN helper is bundled but not installed.',
          ),
        ),
      ],
    );

    await tester.tap(find.byIcon(Icons.tune_rounded).last);
    await tester.pumpAndSettle();

    expect(
      find.text('SecureWave VPN helper is bundled but not installed.'),
      findsOneWidget,
    );
    expect(find.text('Install VPN helper'), findsOneWidget);
    expect(find.text('Refresh runtime status'), findsOneWidget);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  Override? serversOverride,
  Override? planOverride,
  Override? vpnOverride,
  Override? runtimeStatusOverride,
  List<Override> extraOverrides = const [],
  bool simulateTunnel = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWith(
          (ref) => AppConfig(
            apiBaseUrl: 'https://api.example.test',
            portalUrl: 'https://portal.example.test',
            upgradeUrl: 'https://upgrade.example.test',
            useMockApi: false,
            simulateTunnel: simulateTunnel,
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
        if (vpnOverride != null) vpnOverride,
        if (runtimeStatusOverride != null) runtimeStatusOverride,
        ...extraOverrides,
      ],
      child: const SecureWaveApp(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _ConnectedVpnStateNotifier extends VpnStateNotifier {
  _ConnectedVpnStateNotifier(super.ref) {
    state = const VpnState(status: VpnStatus.connected);
  }
}
