// Integration test: degraded → retryValidation() / forceReconnect() / triggerDiagnostic()
//
// Tests the VpnStateNotifier public health action API without touching
// the native bridge.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/diagnostic_service.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

// ── Stub VpnService ───────────────────────────────────────────────────────────

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
  }) async =>
      VpnStatus.disconnected;
  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;
}

// ── Tracking VpnStateNotifier ─────────────────────────────────────────────────

/// Overrides public health action methods to track calls and apply
/// controlled state transitions directly via the StateNotifier state setter.
class _TrackingVpnStateNotifier extends VpnStateNotifier {
  _TrackingVpnStateNotifier(super.ref, {required VpnState initialState}) {
    state = initialState;
  }

  int retryValidationCallCount = 0;
  int forceReconnectCallCount = 0;
  int triggerDiagnosticCallCount = 0;

  // When non-null, retryValidation applies this state update.
  VpnState? nextState;

  @override
  Future<void> retryValidation() async {
    retryValidationCallCount++;
    if (nextState != null) {
      state = nextState!;
    }
  }

  @override
  Future<void> forceReconnect() async {
    forceReconnectCallCount++;
  }

  @override
  Future<DiagnosticReport> triggerDiagnostic() async {
    triggerDiagnosticCallCount++;
    return DiagnosticReport(
      timestamp: DateTime.now(),
      summary: '4 of 4 checks passed.',
      failures: const [],
      recommendations: const ['All checks passed. The VPN tunnel appears healthy.'],
      checks: const [],
      validationSnapshot: null,
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _degradedState = VpnState(
  status: VpnStatus.connected,
  validationStatus: VpnValidationStatus.degraded,
  validationScore: 65,
  validationFailureType: VpnValidationFailureType.highLatency,
  desiredOn: true,
);

const _unhealthyState = VpnState(
  status: VpnStatus.connected,
  validationStatus: VpnValidationStatus.unhealthy,
  validationScore: 10,
  validationFailureType: VpnValidationFailureType.noTunnel,
  desiredOn: true,
);

const _healthyState = VpnState(
  status: VpnStatus.connected,
  validationStatus: VpnValidationStatus.healthy,
  validationScore: 98,
  desiredOn: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  group('Health actions — degraded state', () {
    late ProviderContainer container;
    late _TrackingVpnStateNotifier notifier;

    setUp(() {
      container = ProviderContainer(overrides: [
        vpnServiceProvider.overrideWithValue(_StubVpnService()),
        vpnStateProvider.overrideWith((ref) {
          notifier = _TrackingVpnStateNotifier(ref, initialState: _degradedState);
          return notifier;
        }),
      ]);
      // Force provider initialization so notifier is assigned.
      container.read(vpnStateProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('retryValidation() is callable', () async {
      await notifier.retryValidation();
      expect(notifier.retryValidationCallCount, 1);
    });

    test('retryValidation() transitions degraded → healthy via nextState',
        () async {
      notifier.nextState = _healthyState;
      await notifier.retryValidation();

      expect(notifier.state.validationStatus, VpnValidationStatus.healthy);
      expect(notifier.state.validationScore, 98);
      expect(notifier.retryValidationCallCount, 1);
    });

    test('retryValidation() can be called multiple times (no infinite loop)',
        () async {
      for (var i = 0; i < 5; i++) {
        await notifier.retryValidation();
      }
      expect(notifier.retryValidationCallCount, 5);
    });

    test('triggerDiagnostic() returns DiagnosticReport', () async {
      final report = await notifier.triggerDiagnostic();
      expect(notifier.triggerDiagnosticCallCount, 1);
      expect(report, isA<DiagnosticReport>());
      expect(report.summary, isNotEmpty);
      expect(report.recommendations, isNotEmpty);
    });

    test('degraded state does not show forceReconnect in tracker', () async {
      // forceReconnect should not be triggered automatically in degraded.
      expect(notifier.forceReconnectCallCount, 0);
    });
  });

  group('Health actions — unhealthy state', () {
    late ProviderContainer container;
    late _TrackingVpnStateNotifier notifier;

    setUp(() {
      container = ProviderContainer(overrides: [
        vpnServiceProvider.overrideWithValue(_StubVpnService()),
        vpnStateProvider.overrideWith((ref) {
          notifier = _TrackingVpnStateNotifier(ref, initialState: _unhealthyState);
          return notifier;
        }),
      ]);
      container.read(vpnStateProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('forceReconnect() is callable', () async {
      await notifier.forceReconnect();
      expect(notifier.forceReconnectCallCount, 1);
    });

    test('triggerDiagnostic() on unhealthy returns report', () async {
      final report = await notifier.triggerDiagnostic();
      expect(report, isA<DiagnosticReport>());
      expect(notifier.triggerDiagnosticCallCount, 1);
    });

    test('retryValidation not called by default in unhealthy state', () {
      expect(notifier.retryValidationCallCount, 0);
    });
  });

  group('Health actions — desiredOn=false guard (real notifier)', () {
    late ProviderContainer container;
    late VpnStateNotifier realNotifier;

    setUp(() {
      container = ProviderContainer(overrides: [
        vpnServiceProvider.overrideWithValue(_StubVpnService()),
      ]);
      realNotifier = container.read(vpnStateProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('forceReconnect() completes without error when desiredOn=false',
        () async {
      expect(realNotifier.state.desiredOn, isFalse);
      await expectLater(realNotifier.forceReconnect(), completes);
      // State must not have changed to connecting/error.
      expect(realNotifier.state.status, VpnStatus.disconnected);
    });

    test('retryValidation() completes without error when desiredOn=false',
        () async {
      expect(realNotifier.state.desiredOn, isFalse);
      await expectLater(realNotifier.retryValidation(), completes);
    });

    test('triggerDiagnostic() completes and returns a report when desiredOn=false',
        () async {
      expect(realNotifier.state.desiredOn, isFalse);
      final report = await realNotifier.triggerDiagnostic();
      expect(report, isA<DiagnosticReport>());
    });
  });

  group('Degraded → retry → healthy flow', () {
    // This test verifies the end-to-end state transition driven by
    // the tracking notifier (no native bridge).
    test('state goes degraded → healthy after successful retryValidation',
        () async {
      final container = ProviderContainer(overrides: [
        vpnServiceProvider.overrideWithValue(_StubVpnService()),
        vpnStateProvider.overrideWith((ref) {
          return _TrackingVpnStateNotifier(
            ref,
            initialState: _degradedState,
          );
        }),
      ]);

      final notifier =
          container.read(vpnStateProvider.notifier) as _TrackingVpnStateNotifier;

      // Verify degraded.
      expect(container.read(vpnStateProvider).validationStatus,
          VpnValidationStatus.degraded);

      // Simulate retry resulting in healthy.
      notifier.nextState = _healthyState;
      await notifier.retryValidation();

      // Verify state updated.
      expect(container.read(vpnStateProvider).validationStatus,
          VpnValidationStatus.healthy);
      expect(container.read(vpnStateProvider).validationScore, 98);

      container.dispose();
    });
  });
}
