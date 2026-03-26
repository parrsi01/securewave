import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/services/health_log_service.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  late Directory tmpDir;
  late HealthLogService svc;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpDir = await Directory.systemTemp.createTemp('health_log_test_');
    svc = HealthLogService(
      maxFileSizeBytes: 4096,
      keepLines: 10,
      overrideDirectory: tmpDir.path,
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  HealthLogEntry makeEntry({
    VpnValidationStatus status = VpnValidationStatus.healthy,
    int score = 100,
    VpnValidationFailureType? failureType,
    int? latencyMs = 45,
    double packetLoss = 0.0,
  }) {
    return HealthLogEntry(
      timestamp: DateTime.now(),
      validationStatus: status,
      validationScore: score,
      failureType: failureType,
      latencyMs: latencyMs,
      packetLoss: packetLoss,
    );
  }

  group('HealthLogService', () {
    test('append and readRecent returns entry', () async {
      await svc.append(makeEntry());
      final entries = await svc.readRecent(count: 10);

      expect(entries, hasLength(1));
      expect(entries.first.validationStatus, VpnValidationStatus.healthy);
      expect(entries.first.validationScore, 100);
    });

    test('readRecent returns empty list when no file', () async {
      final entries = await svc.readRecent(count: 10);
      expect(entries, isEmpty);
    });

    test('multiple entries are ordered oldest-first', () async {
      await svc.append(makeEntry(status: VpnValidationStatus.healthy, score: 100));
      await svc.append(makeEntry(status: VpnValidationStatus.degraded, score: 72));
      await svc.append(makeEntry(status: VpnValidationStatus.unhealthy, score: 20));

      final entries = await svc.readRecent(count: 10);
      expect(entries, hasLength(3));
      expect(entries[0].validationScore, 100);
      expect(entries[1].validationScore, 72);
      expect(entries[2].validationScore, 20);
    });

    test('readRecent(count: 1) returns only the last entry', () async {
      await svc.append(makeEntry(score: 100));
      await svc.append(makeEntry(score: 50));

      final entries = await svc.readRecent(count: 1);
      expect(entries, hasLength(1));
      expect(entries.first.validationScore, 50);
    });

    test('round-trips failure type', () async {
      await svc.append(makeEntry(
        status: VpnValidationStatus.degraded,
        score: 60,
        failureType: VpnValidationFailureType.highLatency,
      ));
      final entries = await svc.readRecent(count: 1);
      expect(entries.first.failureType, VpnValidationFailureType.highLatency);
    });

    test('round-trips null failure type', () async {
      await svc.append(makeEntry(failureType: null));
      final entries = await svc.readRecent(count: 1);
      expect(entries.first.failureType, isNull);
    });

    test('rotation trims to keepLines when over maxFileSizeBytes', () async {
      final smallSvc = HealthLogService(
        maxFileSizeBytes: 1, // always trigger rotation
        keepLines: 3,
        overrideDirectory: tmpDir.path,
      );
      for (var i = 0; i < 10; i++) {
        await smallSvc.append(makeEntry(score: i));
      }
      final entries = await smallSvc.readRecent(count: 20);
      // After rotation keepLines=3 entries at most remain.
      expect(entries.length, lessThanOrEqualTo(3));
    });

    test('clear removes all entries', () async {
      await svc.append(makeEntry());
      await svc.clear();
      final entries = await svc.readRecent(count: 10);
      expect(entries, isEmpty);
    });

    test('HealthLogEntry.toJson has all expected keys', () {
      final e = makeEntry(
        status: VpnValidationStatus.degraded,
        score: 72,
        failureType: VpnValidationFailureType.packetLoss,
        latencyMs: 180,
        packetLoss: 0.04,
      );
      final json = e.toJson();
      expect(json['ts'], isA<String>());
      expect(json['status'], 'degraded');
      expect(json['score'], 72);
      expect(json['failure_type'], 'packetLoss');
      expect(json['latency_ms'], 180);
      expect(json['packet_loss'], 0.04);
    });

    test('HealthLogEntry.fromJson round-trips all fields', () {
      final original = makeEntry(
        status: VpnValidationStatus.unhealthy,
        score: 10,
        failureType: VpnValidationFailureType.noTunnel,
        latencyMs: null,
        packetLoss: 1.0,
      );
      final json = original.toJson();
      final restored = HealthLogEntry.fromJson(
          json.map((k, v) => MapEntry(k, v)));
      expect(restored.validationStatus, original.validationStatus);
      expect(restored.validationScore, original.validationScore);
      expect(restored.failureType, original.failureType);
      expect(restored.latencyMs, original.latencyMs);
      expect(restored.packetLoss, original.packetLoss);
    });
  });
}
