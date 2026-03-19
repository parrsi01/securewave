import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_protocol_catalog.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/debug/automation_keys.dart';
import 'package:securewave_app/ui/components/connect_button.dart';
import 'package:securewave_app/ui/layout/adaptive_shell_scaffold.dart';
import 'package:securewave_app/ui/screens/account_screen.dart';
import 'package:securewave_app/ui/screens/auth/login_screen.dart';
import 'package:securewave_app/ui/screens/auth/register_screen.dart';
import 'package:securewave_app/ui/screens/diagnostics_screen.dart';
import 'package:securewave_app/ui/screens/server_selection_screen.dart';
import 'package:securewave_app/ui/screens/settings_screen.dart';
import 'package:securewave_app/ui/widgets/vpn_ui_bindings.dart';

class _StaticVpnStateNotifier extends VpnStateNotifier {
  _StaticVpnStateNotifier(super.ref) {
    state = const VpnState(status: VpnStatus.disconnected);
  }
}

class _StaticVpnService implements VpnService {
  @override
  bool get isNativeAvailable => false;

  @override
  String? get availabilityMessage => null;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    Map<String, dynamic>? profile,
  }) async {
    return VpnStatus.connected;
  }

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;

  @override
  Future<VpnCapabilities> getCapabilities() async => VpnCapabilities.none;

  @override
  VpnStatus getStatus() => VpnStatus.disconnected;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String?> fakeStore;

  setUp(() {
    fakeStore = <String, String?>{};
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
            return key == null ? null : fakeStore[key];
          case 'write':
            if (key != null) fakeStore[key] = args['value']?.toString();
            return null;
          case 'delete':
            if (key != null) fakeStore.remove(key);
            return null;
          case 'deleteAll':
            fakeStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.fromEntries(
              fakeStore.entries
                  .where((entry) => entry.value != null)
                  .map((entry) => MapEntry(entry.key, entry.value!)),
            );
        }
        return null;
      },
    );
  });

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    List<Override> overrides = const <Override>[],
    Size size = const Size(1440, 1024),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(0.84),
          ),
          child: MaterialApp(home: child),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('login screen exposes stable automation keys', (tester) async {
    await pumpSurface(tester, const LoginScreen());

    expect(find.byKey(AutomationKeys.loginEmailFieldKey), findsOneWidget);
    expect(find.byKey(AutomationKeys.loginPasswordFieldKey), findsOneWidget);
    expect(find.byKey(AutomationKeys.loginSubmitButtonKey), findsOneWidget);
    expect(
      find.byKey(AutomationKeys.loginCreateAccountButtonKey),
      findsOneWidget,
    );
  });

  testWidgets('register screen exposes stable automation keys', (tester) async {
    await pumpSurface(tester, const RegisterScreen());

    expect(find.byKey(AutomationKeys.registerEmailFieldKey), findsOneWidget);
    expect(find.byKey(AutomationKeys.registerPasswordFieldKey), findsOneWidget);
    expect(find.byKey(AutomationKeys.registerConfirmFieldKey), findsOneWidget);
    expect(find.byKey(AutomationKeys.registerSubmitButtonKey), findsOneWidget);
    expect(
      find.byKey(AutomationKeys.registerBackToLoginButtonKey),
      findsOneWidget,
    );
  });

  testWidgets('desktop shell exposes routed navigation automation keys',
      (tester) async {
    await pumpSurface(
      tester,
      AdaptiveShellScaffold(
        currentIndex: 0,
        onDestinationSelected: (_) {},
        child: const SizedBox.shrink(),
      ),
    );

    expect(find.byKey(AutomationKeys.shellRootScaffoldKey), findsOneWidget);
    expect(
        find.byKey(AutomationKeys.navDestinationKey('Home')), findsOneWidget);
    expect(
      find.byKey(AutomationKeys.navDestinationKey('Servers')),
      findsOneWidget,
    );
    expect(
      find.byKey(AutomationKeys.navDestinationKey('Locations')),
      findsOneWidget,
    );
    expect(
      find.byKey(AutomationKeys.navDestinationKey('Settings')),
      findsOneWidget,
    );
    expect(
      find.byKey(AutomationKeys.navDestinationKey('Account')),
      findsOneWidget,
    );
  });

  testWidgets('connect button exposes the active connection action key',
      (tester) async {
    await pumpSurface(
      tester,
      Scaffold(
        body: Center(
          child: ConnectButton(
            visualState: ConnectionVisualState.disconnected,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(AutomationKeys.connectionRingButtonKey), findsOneWidget);
    expect(
      find.byKey(AutomationKeys.connectionStateKey('disconnected')),
      findsOneWidget,
    );
  });

  testWidgets('settings screen exposes diagnostics entry automation key',
      (tester) async {
    await pumpSurface(tester, const SettingsScreen());

    expect(find.byKey(AutomationKeys.settingsScreenKey), findsOneWidget);
    expect(find.byKey(AutomationKeys.diagnosticsTileKey), findsOneWidget);
  });

  testWidgets('diagnostics screen exposes root scroll automation key',
      (tester) async {
    await pumpSurface(
      tester,
      const DiagnosticsScreen(),
      overrides: [
        vpnStateProvider.overrideWith((ref) => _StaticVpnStateNotifier(ref)),
        vpnServiceProvider.overrideWithValue(_StaticVpnService()),
        vpnProtocolCatalogProvider.overrideWith(
          (ref) async => VpnProtocolCatalog.fromJson({
            'user_tier': 'free',
            'device_type': 'linux',
            'protocols': [
              {
                'protocol': 'wireguard',
                'enabled': true,
                'server_enabled': true,
                'plan_enabled': true,
                'platform_supported': true,
              },
            ],
          }),
        ),
      ],
    );

    expect(find.byKey(AutomationKeys.diagnosticsRootScrollKey), findsOneWidget);
    expect(find.text('CONNECTION'), findsOneWidget);
    expect(find.text('PIPELINE'), findsOneWidget);
  });

  testWidgets('account screen exposes sign-out automation keys',
      (tester) async {
    await pumpSurface(
      tester,
      const AccountScreen(),
      overrides: [
        userPlanProvider.overrideWith(
          (ref) async => const UserPlan(
            name: 'Free',
            isPremium: false,
            dataCapGb: 5,
            usedGb: 1,
            dataCapBytes: 5368709120,
            usedBytes: 1073741824,
            speedDownMbps: 25,
            speedUpMbps: 10,
          ),
        ),
      ],
    );

    final signOutFinder = find.byKey(AutomationKeys.accountSignOutButtonKey);
    expect(find.byKey(AutomationKeys.accountScreenKey), findsOneWidget);
    expect(signOutFinder, findsOneWidget);

    await tester.tap(signOutFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(AutomationKeys.accountConfirmSignOutButtonKey),
      findsOneWidget,
    );
  });

  testWidgets('server selection screen exposes server tile automation keys',
      (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 250));
    });

    await pumpSurface(
      tester,
      const ServerSelectionScreen(),
      overrides: [
        vpnServiceProvider.overrideWithValue(_StaticVpnService()),
        vpnStateProvider.overrideWith((ref) => _StaticVpnStateNotifier(ref)),
        serversProvider.overrideWith(
          (ref) async => const <ServerRegion>[
            ServerRegion(
              id: 'miami',
              name: 'Miami',
              city: 'Miami',
              country: 'United States',
              countryCode: 'US',
              region: 'North America',
              regionHealthStatus: 'up',
            ),
          ],
        ),
        userPlanProvider.overrideWith(
          (ref) async => const UserPlan(
            name: 'Free',
            isPremium: false,
            dataCapGb: 5,
            usedGb: 1,
            dataCapBytes: 5368709120,
            usedBytes: 1073741824,
            speedDownMbps: 25,
            speedUpMbps: 10,
          ),
        ),
      ],
    );

    expect(find.byKey(AutomationKeys.serverTileKey('miami')), findsOneWidget);
  });
}
