import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/bootstrap/boot_controller.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
  });

  testWidgets('no-token cold start is registration first with login switch',
      (tester) async {
    final config = AppConfig(
      apiBaseUrl: 'https://api.example.test',
      portalUrl: 'https://portal.example.test',
      upgradeUrl: 'https://upgrade.example.test',
      useMockApi: false,
      resetSessionOnBoot: false,
    );
    final container = ProviderScope(
      overrides: [
        appConfigProvider.overrideWith((ref) => config),
        apiClientProvider.overrideWithValue(ApiClient(config)),
        vpnServiceProvider.overrideWithValue(MockVpnService()),
        bootControllerProvider.overrideWith(
          (ref) => BootController(
            ref,
            configLoader: () async => config,
          ),
        ),
      ],
      child: const SecureWaveApp(),
    );

    await tester.pumpWidget(container);
    await tester.pumpAndSettle();

    expect(find.text('Create an account to start using SecureWave.'),
        findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Use an existing account'), findsOneWidget);

    await tester.tap(find.text('Use an existing account'));
    await tester.pump();
    expect(find.text('Sign in to manage your VPN session.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
