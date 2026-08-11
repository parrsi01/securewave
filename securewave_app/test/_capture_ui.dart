// Screenshot capture harness. Not named *_test.dart, so `flutter test` does not
// pick it up. Run explicitly:
//   flutter test test/_capture_ui.dart --update-goldens
// Set CAPTURE_DIR to choose the output folder (default: _captures/current).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

String get _dir => Platform.environment['CAPTURE_DIR'] ?? '_captures/current';

Future<void> _loadFonts() async {
  Future<void> load(String family, String dir, List<String> files) async {
    final loader = FontLoader(family);
    var any = false;
    for (final file in files) {
      final f = File('$dir/$file');
      if (!f.existsSync()) continue;
      any = true;
      loader.addFont(
        f
            .readAsBytes()
            .then((b) => ByteData.view(Uint8List.fromList(b).buffer)),
      );
    }
    if (any) await loader.load();
  }

  final material =
      '${Platform.environment['FLUTTER_ROOT'] ?? '/home/sp/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  await load('Roboto', material, [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', material, ['MaterialIcons-Regular.otf']);

  // pubspec font assets are not registered automatically inside `flutter test`,
  // so load the bundled brand font from disk.
  await load('PlusJakartaSans', 'assets/fonts', [
    'PlusJakartaSans-Regular.ttf',
    'PlusJakartaSans-Medium.ttf',
    'PlusJakartaSans-SemiBold.ttf',
    'PlusJakartaSans-Bold.ttf',
    'PlusJakartaSans-ExtraBold.ttf',
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  late Map<String, String?> store;

  void mockStorage() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall call) async => <String>['wifi'],
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) {
          events.success(<String>['wifi']);
        },
      ),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        final args = call.arguments is Map
            ? Map<String, dynamic>.from(call.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
        switch (call.method) {
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
                  .where((e) => e.value != null)
                  .map((e) => MapEntry(e.key, e.value!)),
            );
        }
        return null;
      },
    );
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    bool signedIn = true,
    bool settle = true,
    VpnService? service,
    List<ServerRegion>? servers,
  }) async {
    store = <String, String?>{if (signedIn) 'access_token': 'capture-token'};
    mockStorage();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vpnServiceProvider.overrideWithValue(
              service ?? _CaptureVpnService(VpnStatus.disconnected)),
          apiClientProvider.overrideWithValue(ApiClient(AppConfig.defaults())),
          appConfigProvider.overrideWith(
            (ref) => AppConfig(
              apiBaseUrl: 'https://api.securewave.app',
              portalUrl: 'https://portal.securewave.app',
              upgradeUrl: 'https://upgrade.securewave.app',
              useMockApi: false,
              resetSessionOnBoot: false,
            ),
          ),
          currentUserProvider.overrideWith(
            (ref) async => const UserAccount(
              id: 1,
              email: 'simon@securewave.app',
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
              usedGb: 1.8,
            ),
          ),
          serversProvider.overrideWith(
            (ref) async =>
                servers ??
                const [
                  ServerRegion(
                    id: 'de-fsn',
                    name: 'Falkenstein',
                    city: 'Falkenstein',
                    country: 'Germany',
                    latencyMs: 28,
                    supportedProtocols: ['wireguard'],
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
      // Advance a fixed number of frames for deterministic screenshot timing.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_dir/$name.png'),
    );
  }

  const desktop = Size(1280, 830);
  const narrow = Size(430, 860);

  testWidgets('auth login', (tester) async {
    await pump(tester, size: desktop, signedIn: false);
    await shot(tester, 'auth-login-desktop');
  });

  testWidgets('auth register', (tester) async {
    await pump(tester, size: desktop, signedIn: false);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await shot(tester, 'auth-register-desktop');
  });

  testWidgets('auth login narrow', (tester) async {
    await pump(tester, size: narrow, signedIn: false);
    await shot(tester, 'auth-login-narrow');
  });

  testWidgets('dashboard disconnected', (tester) async {
    await pump(tester, size: desktop);
    await shot(tester, 'dashboard-disconnected-desktop');
  });

  testWidgets('dashboard connected', (tester) async {
    await pump(
      tester,
      size: desktop,
      settle: false,
      service: _CaptureVpnService(VpnStatus.connected),
    );
    await shot(tester, 'dashboard-connected-desktop');
  });

  testWidgets('dashboard disconnected narrow', (tester) async {
    await pump(tester, size: narrow);
    await shot(tester, 'dashboard-disconnected-narrow');
  });

  testWidgets('dashboard connected narrow', (tester) async {
    await pump(
      tester,
      size: narrow,
      settle: false,
      service: _CaptureVpnService(VpnStatus.connected),
    );
    await shot(tester, 'dashboard-connected-narrow');
  });

  testWidgets('dashboard with empty catalog notice', (tester) async {
    await pump(tester, size: desktop, servers: const []);
    await shot(tester, 'dashboard-notice-desktop');
  });

  testWidgets('account', (tester) async {
    await pump(tester, size: desktop);
    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();
    await shot(tester, 'account-desktop');
  });

  testWidgets('account narrow', (tester) async {
    await pump(tester, size: narrow);
    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    await shot(tester, 'account-narrow');
  });

  testWidgets('diagnostics', (tester) async {
    await pump(tester, size: desktop);
    await tester.tap(find.text('DIAGNOSTICS'));
    await tester.pumpAndSettle();
    await shot(tester, 'diagnostics-desktop');
  });
}

class _CaptureVpnService implements VpnService {
  _CaptureVpnService(this._status);

  final VpnStatus _status;

  @override
  bool get isNativeAvailable => true;

  @override
  bool canConnectProtocol(VpnProtocol protocol) =>
      protocol == VpnProtocol.wireGuard;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) =>
      canConnectProtocol(protocol)
          ? null
          : '${vpnProtocolLabel(protocol)} is not available on this runtime.';

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
  }) async =>
      VpnStatus.connected;

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;

  @override
  VpnStatus getStatus() => _status;
}
