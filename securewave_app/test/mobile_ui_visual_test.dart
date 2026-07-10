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
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'read' ? 'test-token' : null,
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

  testWidgets('mobile connected visual evidence', (tester) async {
    await _pumpEvidence(tester, const Size(390, 844), VpnStatus.connected);
    await expectLater(
      find.byType(SecureWaveApp),
      matchesGoldenFile(
        '../../artifacts/mobile-ui-refactor/mobile-connected-390x844.png',
      ),
    );
  }, tags: 'visual');

  testWidgets('desktop disconnected visual evidence', (tester) async {
    await _pumpEvidence(tester, const Size(1280, 800), VpnStatus.disconnected);
    await expectLater(
      find.byType(SecureWaveApp),
      matchesGoldenFile(
        '../../artifacts/mobile-ui-refactor/desktop-disconnected-1280x800.png',
      ),
    );
  }, tags: 'visual');
}

Future<void> _pumpEvidence(
  WidgetTester tester,
  Size size,
  VpnStatus status,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vpnServiceProvider.overrideWithValue(_EvidenceVpnService(status)),
        appConfigProvider.overrideWith((ref) => AppConfig(
              apiBaseUrl: 'https://api.securewave.example',
              portalUrl: 'https://securewave.example/account',
              upgradeUrl: 'https://securewave.example/upgrade',
              useMockApi: false,
              resetSessionOnBoot: false,
            )),
        currentUserProvider.overrideWith((ref) async => const UserAccount(
              id: 7,
              email: 'vpn.user@example.test',
              isActive: true,
              emailVerified: true,
              has2fa: true,
              subscriptionStatus: 'active',
            )),
        userPlanProvider.overrideWith((ref) async => const UserPlan(
              name: 'SecureWave Plus',
              isPremium: true,
              dataCapGb: 100,
              usedGb: 18.4,
            )),
        serversProvider.overrideWith((ref) async => const [
              ServerRegion(
                id: 'eu-west',
                name: 'Western Europe',
                city: 'Amsterdam',
                country: 'Netherlands',
                latencyMs: 31,
                supportedProtocols: ['wireguard', 'openvpn'],
              ),
            ]),
      ],
      child: const SecureWaveApp(),
    ),
  );
  await tester.pumpAndSettle();
}

class _EvidenceVpnService implements VpnService {
  _EvidenceVpnService(this.status);
  VpnStatus status;

  @override
  bool canConnectProtocol(VpnProtocol protocol) =>
      protocol != VpnProtocol.ikev2;
  @override
  Future<VpnStatus> connect(
          {required VpnProtocol protocol, String? config}) async =>
      status = VpnStatus.connected;
  @override
  Future<VpnStatus> disconnect() async => status = VpnStatus.disconnected;
  @override
  VpnStatus getStatus() => status;
  @override
  bool get isNativeAvailable => true;
  @override
  String? protocolUnavailableReason(VpnProtocol protocol) =>
      protocol == VpnProtocol.ikev2
          ? 'Unavailable in this test runtime.'
          : null;
}
