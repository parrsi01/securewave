import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/services/api_service.dart';
import 'package:securewave_app/services/vpn_service.dart';

void main() {
  group('WireGuard API profile', () {
    test('reads the real server profile fields', () {
      final profile = WireGuardProfile.fromJson({
        'device_id': 17,
        'server_id': 'hetzner-eu-1',
        'server_location': 'Helsinki, Finland',
        'wireguard_config': '[Interface]\nAddress = 10.0.0.2/32',
      });

      expect(profile.deviceId, 17);
      expect(profile.serverId, 'hetzner-eu-1');
      expect(profile.location, 'Helsinki, Finland');
      expect(profile.config, contains('[Interface]'));
    });

    test('rejects an empty tunnel configuration', () {
      expect(
        () => WireGuardProfile.fromJson({'wireguard_config': '  '}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('WireGuard traffic counters', () {
    test('parses receive and transmit counters from the Linux helper', () {
      final stats = VpnTrafficStats.fromMap({
        'rx_bytes': '2048',
        'tx_bytes': 512,
        'counters_available': true,
      });

      expect(stats.available, isTrue);
      expect(stats.rxBytes, 2048);
      expect(stats.txBytes, 512);
    });

    test('does not report unavailable counters as zero usage', () {
      final stats = VpnTrafficStats.fromMap({
        'rx_bytes': 0,
        'tx_bytes': 0,
        'counters_available': false,
      });

      expect(stats.available, isFalse);
    });
  });
}
