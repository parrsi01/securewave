import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';

void main() {
  test('release configuration has an explicit non-local API URL', () {
    final config = AppConfig.defaults();
    expect(config.apiBaseUrl, startsWith('https://'));
    expect(config.apiBaseUrl, isNot(contains('localhost')));
    expect(config.demoMode, isFalse);
  });

  test('profile parser keeps only the WireGuard beta contract', () {
    final profile = VpnProfile.fromJson({
      'device_id': 7,
      'device_name': 'Linux',
      'device_type': 'linux',
      'server_id': 'hetzner-one',
      'server_location': 'SecureWave Beta',
      'wireguard_config': '[Interface]\nPrivateKey = redacted',
    });
    expect(profile.deviceId, 7);
    expect(profile.wireguardConfig, contains('[Interface]'));
    expect(profile.serverId, 'hetzner-one');
  });

  test('demo service is deterministic and never needs a network', () async {
    final service = DemoVpnService();
    expect(service.isAvailable, isTrue);
    expect(await service.connect(config: '# demo'), VpnStatus.connected);
    final first = await service.getTrafficStats();
    final second = await service.getTrafficStats();
    expect(first.rxBytes, 8192);
    expect(first.txBytes, 4096);
    expect(second.rxBytes, 16384);
    expect(second.txBytes, 8192);
    expect(await service.disconnect(), VpnStatus.disconnected);
  });
}
