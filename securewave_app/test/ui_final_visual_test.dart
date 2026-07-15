import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/protocol_availability.dart';
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
      (call) async {
        if (call.method != 'read') return null;
        final args = call.arguments is Map
            ? Map<Object?, Object?>.from(call.arguments as Map)
            : const <Object?, Object?>{};
        return args['key'] == 'access_token' ? 'test-token' : null;
      },
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

  testWidgets('narrow connected surface is deterministic', (tester) async {
    await _pumpEvidence(tester, const Size(390, 844), VpnStatus.connected);

    expect(find.text('VPN connected'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(_goldenRootKey),
      matchesGoldenFile('goldens/ui-final-narrow-connected.png'),
    );
  });

  testWidgets('desktop disconnected surface is deterministic', (tester) async {
    await _pumpEvidence(tester, const Size(1280, 800), VpnStatus.disconnected);

    expect(find.text('VPN disconnected'), findsOneWidget);
    expect(find.text('Connect'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(_goldenRootKey),
      matchesGoldenFile('goldens/ui-final-desktop-disconnected.png'),
    );
  });

  testWidgets('unsupported catalog evidence stays unavailable', (tester) async {
    await _pumpEvidence(
      tester,
      const Size(390, 844),
      VpnStatus.disconnected,
      servers: const [
        ServerRegion(
          id: 'openvpn-only',
          name: 'OpenVPN only',
          supportedProtocols: ['openvpn'],
        ),
      ],
    );

    expect(find.textContaining('no usable WireGuard evidence'), findsOneWidget);
    final connectFinder = find.ancestor(
      of: find.text('Connect'),
      matching: find.byType(FilledButton),
    );
    final connect = tester.widget<FilledButton>(connectFinder);
    expect(connect.onPressed, isNull);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(_goldenRootKey),
      matchesGoldenFile('goldens/ui-final-narrow-unavailable.png'),
    );
  });

  testWidgets('compact desktop viewport has no overflow', (tester) async {
    await _pumpEvidence(tester, const Size(800, 600), VpnStatus.disconnected);

    expect(find.text('VPN disconnected'), findsOneWidget);
    expect(find.text('Connect'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide desktop viewport keeps primary controls accessible',
      (tester) async {
    await _pumpEvidence(tester, const Size(1600, 1000), VpnStatus.disconnected);

    expect(find.text('VPN disconnected'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Servers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpEvidence(
  WidgetTester tester,
  Size size,
  VpnStatus status, {
  List<ServerRegion> servers = const [
    ServerRegion(
      id: 'eu-west',
      name: 'Western Europe',
      city: 'Amsterdam',
      country: 'Netherlands',
      latencyMs: 31,
      supportedProtocols: ['wireguard', 'openvpn'],
    ),
  ],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vpnServiceProvider.overrideWithValue(_VisualVpnService(status)),
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
            id: 7,
            email: 'vpn.user@example.test',
            isActive: true,
            emailVerified: true,
            has2fa: true,
            subscriptionStatus: 'active',
          ),
        ),
        userPlanProvider.overrideWith(
          (ref) async => const UserPlan(
            name: 'SecureWave Plus',
            isPremium: true,
            dataCapGb: 100,
            usedGb: 18.4,
          ),
        ),
        serversProvider.overrideWith((ref) async => servers),
        protocolAvailabilityProvider.overrideWith(
          (ref) async => {
            VpnProtocol.wireGuard: const ProtocolAvailability(
              protocol: VpnProtocol.wireGuard,
              enabled: true,
              serverEnabled: true,
              platformSupported: true,
            ),
          },
        ),
      ],
      child: const RepaintBoundary(
        key: _goldenRootKey,
        child: SecureWaveApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _goldenRootKey = ValueKey<String>('securewave-golden-root');

class _VisualVpnService extends VpnService {
  _VisualVpnService(this.status);

  VpnStatus status;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    String? openVpnUsername,
    String? openVpnPassword,
    bool backendEvidence = false,
  }) async {
    status = VpnStatus.connected;
    return status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    status = VpnStatus.disconnected;
    return status;
  }

  @override
  VpnStatus getStatus() => status;

  @override
  bool get isNativeAvailable => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;
}
