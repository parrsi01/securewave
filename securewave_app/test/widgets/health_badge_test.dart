import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/debug/automation_keys.dart';
import 'package:securewave_app/ui/components/health_badge.dart';

// ── Minimal VpnService stub ───────────────────────────────────────────────────

class _StubVpnService implements VpnService {
  @override
  bool get isNativeAvailable => false;

  @override
  String? get availabilityMessage => null;

  @override
  Future<VpnCapabilities> getCapabilities() async => VpnCapabilities.none;
  @override
  void clearCapabilitiesCache() {}

  @override
  VpnStatus getStatus() => VpnStatus.disconnected;

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    Map<String, dynamic>? profile,
  }) async => VpnStatus.disconnected;

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;
}

// ── VpnStateNotifier stubs ────────────────────────────────────────────────────

class _HealthyVpnStateNotifier extends VpnStateNotifier {
  _HealthyVpnStateNotifier(super.ref) {
    state = const VpnState(
      status: VpnStatus.connected,
      validationStatus: VpnValidationStatus.healthy,
      validationScore: 98,
      validationLatencyMs: 32,
      validationPacketLoss: 0.0,
      validationIpVerified: true,
      validationDnsOk: true,
    );
  }
}

class _DegradedVpnStateNotifier extends VpnStateNotifier {
  _DegradedVpnStateNotifier(super.ref) {
    state = const VpnState(
      status: VpnStatus.connected,
      validationStatus: VpnValidationStatus.degraded,
      validationScore: 72,
      validationLatencyMs: 180,
      validationPacketLoss: 0.04,
      validationIpVerified: true,
      validationDnsOk: true,
      validationFailureType: VpnValidationFailureType.highLatency,
    );
  }

  bool retryValidationCalled = false;

  @override
  Future<void> retryValidation() async {
    retryValidationCalled = true;
  }
}

class _UnhealthyVpnStateNotifier extends VpnStateNotifier {
  _UnhealthyVpnStateNotifier(super.ref) {
    state = const VpnState(
      status: VpnStatus.connected,
      validationStatus: VpnValidationStatus.unhealthy,
      validationScore: 20,
      validationLatencyMs: null,
      validationPacketLoss: 1.0,
      validationIpVerified: false,
      validationDnsOk: false,
      validationFailureType: VpnValidationFailureType.noTunnel,
    );
  }

  bool forceReconnectCalled = false;

  @override
  Future<void> forceReconnect() async {
    forceReconnectCalled = true;
  }
}

// ── Test helpers ──────────────────────────────────────────────────────────────

Widget _buildBadge(
  VpnStateNotifier Function(Ref<VpnState>) notifierFactory,
) {
  return ProviderScope(
    overrides: [
      vpnServiceProvider.overrideWithValue(_StubVpnService()),
      vpnStateProvider.overrideWith(notifierFactory),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Center(child: HealthBadge()),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  // ── Existing tests (unchanged) ────────────────────────────────────────────

  group('HealthBadge — healthy', () {
    testWidgets('shows Healthy label and score 98', (tester) async {
      await tester.pumpWidget(_buildBadge(_HealthyVpnStateNotifier.new));
      await tester.pump();

      expect(find.byKey(AutomationKeys.healthBadgeKey), findsOneWidget);
      expect(find.byKey(AutomationKeys.healthScoreKey), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);
      expect(find.text('98'), findsOneWidget);
      expect(find.byKey(AutomationKeys.healthFailureReasonKey), findsNothing);
    });

    testWidgets('details panel hidden by default', (tester) async {
      await tester.pumpWidget(_buildBadge(_HealthyVpnStateNotifier.new));
      await tester.pump();

      expect(find.byKey(AutomationKeys.healthDetailsPanelKey), findsNothing);
    });

    testWidgets('details panel appears on tap and shows latency', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBadge(_HealthyVpnStateNotifier.new));
      await tester.pump();

      await tester.tap(find.byKey(AutomationKeys.healthBadgeKey));
      await tester.pump();

      expect(
        find.byKey(AutomationKeys.healthDetailsPanelKey),
        findsOneWidget,
      );
      expect(find.text('32 ms'), findsOneWidget);
    });

    testWidgets('no action buttons shown when healthy', (tester) async {
      await tester.pumpWidget(_buildBadge(_HealthyVpnStateNotifier.new));
      await tester.pump();

      expect(
          find.byKey(AutomationKeys.healthRetryChecksButtonKey), findsNothing);
      expect(
          find.byKey(AutomationKeys.healthReconnectButtonKey), findsNothing);
      expect(find.byKey(AutomationKeys.healthRunDiagnosticButtonKey),
          findsNothing);
    });
  });

  group('HealthBadge — degraded', () {
    testWidgets('shows Degraded label, score 72, failure reason', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBadge(_DegradedVpnStateNotifier.new));
      await tester.pump();

      expect(find.text('Degraded'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
      expect(
        find.byKey(AutomationKeys.healthFailureReasonKey),
        findsOneWidget,
      );
      expect(find.text('High latency detected'), findsOneWidget);
    });

    testWidgets('details panel shows latency and packet loss', (tester) async {
      await tester.pumpWidget(_buildBadge(_DegradedVpnStateNotifier.new));
      await tester.pump();

      await tester.tap(find.byKey(AutomationKeys.healthBadgeKey));
      await tester.pump();

      expect(
        find.byKey(AutomationKeys.healthDetailsPanelKey),
        findsOneWidget,
      );
      expect(find.text('180 ms'), findsOneWidget);
      expect(find.text('4.0%'), findsOneWidget);
    });

    testWidgets('shows Retry Checks button when degraded', (tester) async {
      await tester.pumpWidget(_buildBadge(_DegradedVpnStateNotifier.new));
      await tester.pump();

      expect(
          find.byKey(AutomationKeys.healthRetryChecksButtonKey), findsOneWidget);
    });

    testWidgets('does not show Reconnect button when degraded', (tester) async {
      await tester.pumpWidget(_buildBadge(_DegradedVpnStateNotifier.new));
      await tester.pump();

      expect(
          find.byKey(AutomationKeys.healthReconnectButtonKey), findsNothing);
    });

    testWidgets('shows Run Full Diagnostic button when degraded',
        (tester) async {
      await tester.pumpWidget(_buildBadge(_DegradedVpnStateNotifier.new));
      await tester.pump();

      expect(find.byKey(AutomationKeys.healthRunDiagnosticButtonKey),
          findsOneWidget);
    });

    testWidgets('Retry Checks button calls retryValidation on notifier',
        (tester) async {
      late _DegradedVpnStateNotifier notifier;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vpnServiceProvider.overrideWithValue(_StubVpnService()),
            vpnStateProvider.overrideWith((ref) {
              notifier = _DegradedVpnStateNotifier(ref);
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: HealthBadge())),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(AutomationKeys.healthRetryChecksButtonKey));
      await tester.pumpAndSettle();

      expect(notifier.retryValidationCalled, isTrue);
    });
  });

  group('HealthBadge — unhealthy', () {
    testWidgets('shows Unhealthy label, score 20, failure reason', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBadge(_UnhealthyVpnStateNotifier.new));
      await tester.pump();

      expect(find.text('Unhealthy'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(
        find.byKey(AutomationKeys.healthFailureReasonKey),
        findsOneWidget,
      );
      expect(find.text('Tunnel unavailable'), findsOneWidget);
    });

    testWidgets('details panel shows IP/DNS No and packet loss 100%', (
      tester,
    ) async {
      await tester.pumpWidget(_buildBadge(_UnhealthyVpnStateNotifier.new));
      await tester.pump();

      await tester.tap(find.byKey(AutomationKeys.healthBadgeKey));
      await tester.pump();

      expect(
        find.byKey(AutomationKeys.healthDetailsPanelKey),
        findsOneWidget,
      );
      expect(find.text('100.0%'), findsOneWidget);
      // "No" appears for both IP verified and DNS secured
      expect(find.text('No'), findsWidgets);
      // Failure type row also shows the message
      expect(find.text('Tunnel unavailable'), findsWidgets);
    });

    testWidgets('shows Reconnect VPN button when unhealthy', (tester) async {
      await tester.pumpWidget(_buildBadge(_UnhealthyVpnStateNotifier.new));
      await tester.pump();

      expect(
          find.byKey(AutomationKeys.healthReconnectButtonKey), findsOneWidget);
    });

    testWidgets('does not show Retry Checks button when unhealthy',
        (tester) async {
      await tester.pumpWidget(_buildBadge(_UnhealthyVpnStateNotifier.new));
      await tester.pump();

      expect(
          find.byKey(AutomationKeys.healthRetryChecksButtonKey), findsNothing);
    });

    testWidgets('shows Run Full Diagnostic button when unhealthy',
        (tester) async {
      await tester.pumpWidget(_buildBadge(_UnhealthyVpnStateNotifier.new));
      await tester.pump();

      expect(find.byKey(AutomationKeys.healthRunDiagnosticButtonKey),
          findsOneWidget);
    });

    testWidgets('Reconnect VPN button calls forceReconnect on notifier',
        (tester) async {
      late _UnhealthyVpnStateNotifier notifier;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vpnServiceProvider.overrideWithValue(_StubVpnService()),
            vpnStateProvider.overrideWith((ref) {
              notifier = _UnhealthyVpnStateNotifier(ref);
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: HealthBadge())),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(AutomationKeys.healthReconnectButtonKey));
      await tester.pumpAndSettle();

      expect(notifier.forceReconnectCalled, isTrue);
    });
  });
}
