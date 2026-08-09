import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/services/api_client.dart';

void main() {
  test('ServerRegion parses only supplied location catalog metadata', () {
    final server = ServerRegion.fromJson({
      'server_id': 'beta-one',
      'name': 'SecureWave Beta',
      'location': 'Nuremberg, Germany',
      'city': 'Nuremberg',
      'country': 'Germany',
      'latency_ms': 31,
      'load_percent': 18.4,
      'health': 'healthy',
      'supported_protocols': ['wireguard'],
    });

    expect(server.id, 'beta-one');
    expect(server.name, 'SecureWave Beta');
    expect(server.location, 'Nuremberg, Germany');
    expect(server.city, 'Nuremberg');
    expect(server.country, 'Germany');
    expect(server.latencyMs, 31);
    expect(server.loadPercent, 18.4);
    expect(server.health, 'healthy');
    expect(server.hasProtocolEvidenceFor(VpnProtocol.wireGuard), isTrue);
    expect(server.isWireGuardConnectable, isTrue);
  });

  test('ServerRegion leaves omitted optional metadata absent', () {
    final server = ServerRegion.fromJson({
      'server_id': 'beta-one',
      'location': 'SecureWave Beta',
      'protocol': 'wireguard',
    });

    expect(server.city, isNull);
    expect(server.country, isNull);
    expect(server.latencyMs, isNull);
    expect(server.loadPercent, isNull);
    expect(server.health, isNull);
    expect(server.isWireGuardConnectable, isTrue);
  });

  test('ServerRegion fails closed without WireGuard protocol evidence', () {
    final server = ServerRegion.fromJson({
      'server_id': 'beta-one',
      'location': 'SecureWave Beta',
      'supported_protocols': ['openvpn', 'ikev2'],
      'health': 'healthy',
    });

    expect(server.supportedProtocols, isEmpty);
    expect(server.isWireGuardConnectable, isFalse);
  });

  test('target payload adapts to the one-location server catalog', () {
    final target = SecureWaveTarget.fromJson({
      'server_id': 'beta-one',
      'name': 'SecureWave Beta',
      'location': 'Nuremberg, Germany',
      'health': 'healthy',
      'protocol': 'wireguard',
    });
    final server = target.toServerRegion();

    expect(server.id, 'beta-one');
    expect(server.location, 'Nuremberg, Germany');
    expect(server.health, 'healthy');
    expect(server.supportedProtocols, const ['wireguard']);
  });

  test('UserPlan parsing and math reject unsafe numeric output', () {
    final plan = UserPlan.fromJson({
      'plan_name': 'Free',
      'plan_tier': 'free',
      'data_cap_gb': 5,
      'used_gb': 9,
    });

    expect(plan.remainingGb, 0);
    expect(plan.usagePercent, 1);
    expect(plan.remainingGb.isFinite, isTrue);
    expect(plan.usagePercent.isFinite, isTrue);
  });
}
