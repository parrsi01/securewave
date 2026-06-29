import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/user_account.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final store = <String, String?>{
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
        return switch (methodCall.method) {
          'read' => key == null ? null : store[key],
          'write' =>
            key == null ? null : store[key] = args['value']?.toString(),
          'delete' => key == null ? null : store.remove(key),
          'deleteAll' => store.clear(),
          'readAll' => Map<String, String>.fromEntries(
              store.entries
                  .where((entry) => entry.value != null)
                  .map((entry) => MapEntry(entry.key, entry.value!)),
            ),
          _ => null,
        };
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

  testWidgets('connection screen binds runtime session usage from provider',
      (tester) async {
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
          appConfigProvider.overrideWith(
            (ref) => AppConfig(
              apiBaseUrl: 'https://api.example.test',
              portalUrl: 'https://portal.example.test',
              upgradeUrl: 'https://upgrade.example.test',
              useMockApi: false,
              simulateTunnel: false,
              resetSessionOnBoot: false,
            ),
          ),
          vpnStateProvider.overrideWith((ref) => _SeededVpnStateNotifier(ref)),
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
          userPlanProvider.overrideWith(
            (ref) async => const UserPlan(
              name: 'Free',
              isPremium: false,
              dataCapGb: 5,
              usedGb: 1.2,
            ),
          ),
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

    expect(find.text('Session data'), findsWidgets);
    expect(find.text('3.0 KB'), findsWidgets);
    expect(find.text('sw-wg'), findsWidgets);
    expect(find.text('55.3 Mbps'), findsWidgets);
    expect(find.text('12.4 Mbps'), findsWidgets);
  });
}

class _SeededVpnStateNotifier extends VpnStateNotifier {
  _SeededVpnStateNotifier(super.ref) {
    state = const VpnState(
      status: VpnStatus.connected,
      sessionRxBytes: 2048,
      sessionTxBytes: 1024,
      sessionUsageReady: true,
      sessionCountersAvailable: true,
      sessionCounterInterface: 'sw-wg',
      dataRateDown: 6912500,
      dataRateUp: 1550000,
    );
  }
}
