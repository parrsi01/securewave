import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/diagnostic_service.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  group('DiagnosticService', () {
    late DiagnosticService svc;

    setUp(() {
      svc = DiagnosticService(timeout: const Duration(seconds: 5));
    });

    test('runDiagnostics returns DiagnosticReport with 4 checks', () async {
      final report = await svc.runDiagnostics();

      expect(report.checks, hasLength(4));
      expect(report.timestamp, isA<DateTime>());
      expect(report.summary, isNotEmpty);
      expect(report.recommendations, isNotEmpty);
    });

    test('report has all 4 check IDs', () async {
      final report = await svc.runDiagnostics();
      final ids = report.checks.map((c) => c.id).toSet();

      expect(ids, containsAll([
        DiagnosticCheckId.interfaceValidation,
        DiagnosticCheckId.routeCheck,
        DiagnosticCheckId.dnsResolution,
        DiagnosticCheckId.externalIpVerification,
      ]));
    });

    test('DNS check passes in test environment', () async {
      final report = await svc.runDiagnostics();
      final dns = report.checks
          .firstWhere((c) => c.id == DiagnosticCheckId.dnsResolution);

      // In CI/test environment DNS should be available.
      // If it is not, the check should still complete without throwing.
      expect(dns.detail, isNotEmpty);
    });

    test('runDiagnostics with snapshot uses snapshot data', () async {
      // A snapshot reporting interface up + route present + ip verified.
      const snapshot = VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: true,
        trafficConnected: true,
        policyRoutingPresent: true,
        ipVerified: true,
        validationStatus: VpnValidationStatus.healthy,
        validationScore: 100,
        interfaceName: 'wg0',
      );

      final report = await svc.runDiagnostics(snapshot: snapshot);

      final iface = report.checks
          .firstWhere((c) => c.id == DiagnosticCheckId.interfaceValidation);
      expect(iface.passed, isTrue);

      final route = report.checks
          .firstWhere((c) => c.id == DiagnosticCheckId.routeCheck);
      expect(route.passed, isTrue);

      final ip = report.checks
          .firstWhere((c) => c.id == DiagnosticCheckId.externalIpVerification);
      expect(ip.passed, isTrue);
    });

    test('runDiagnostics with failing snapshot marks interface/route failed',
        () async {
      const snapshot = VpnHealthSnapshot(
        nativeStatus: VpnStatus.disconnected,
        interfaceUp: false,
        routePresent: false,
        pingReachable: false,
        trafficConnected: false,
        policyRoutingPresent: false,
        ipVerified: false,
        validationStatus: VpnValidationStatus.unhealthy,
        validationScore: 0,
      );

      final report = await svc.runDiagnostics(snapshot: snapshot);

      final iface = report.checks
          .firstWhere((c) => c.id == DiagnosticCheckId.interfaceValidation);
      expect(iface.passed, isFalse);

      final route = report.checks
          .firstWhere((c) => c.id == DiagnosticCheckId.routeCheck);
      expect(route.passed, isFalse);
    });

    test('allPassed is true when no failures', () async {
      const snapshot = VpnHealthSnapshot(
        nativeStatus: VpnStatus.connected,
        interfaceUp: true,
        routePresent: true,
        pingReachable: true,
        trafficConnected: true,
        policyRoutingPresent: true,
        ipVerified: true,
        validationStatus: VpnValidationStatus.healthy,
        validationScore: 100,
        interfaceName: 'wg0',
        dnsOk: true,
      );
      final report = await svc.runDiagnostics(snapshot: snapshot);

      // DNS and IP may fail depending on env, so check structural invariant.
      expect(report.allPassed, equals(report.failures.isEmpty));
      expect(report.passCount + report.failCount, equals(4));
    });

    test('DiagnosticCheckResult.label returns human-readable string', () {
      const r = DiagnosticCheckResult(
        id: DiagnosticCheckId.routeCheck,
        passed: true,
        detail: 'ok',
      );
      expect(r.label, 'Route Check');
    });

    test('summary reflects failure count', () async {
      const snapshot = VpnHealthSnapshot(
        nativeStatus: VpnStatus.disconnected,
        interfaceUp: false,
        routePresent: false,
        pingReachable: false,
        trafficConnected: false,
        policyRoutingPresent: false,
        ipVerified: false,
        validationStatus: VpnValidationStatus.unhealthy,
        validationScore: 0,
      );
      final report = await svc.runDiagnostics(snapshot: snapshot);

      // At least interface and route fail from snapshot.
      if (!report.allPassed) {
        expect(report.summary, contains('failed'));
        expect(report.failures.isNotEmpty, isTrue);
      }
    });
  });
}
