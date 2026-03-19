import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/vpn/real_vpn_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('vpnServiceProvider always uses ChannelVpnService', () {
    final container = ProviderContainer(overrides: [
      appConfigProvider.overrideWith(
        (ref) => AppConfig(
          apiBaseUrl: 'https://example.invalid',
          portalUrl: 'https://example.invalid',
          upgradeUrl: 'https://example.invalid',
          resetSessionOnBoot: false,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    expect(container.read(vpnServiceProvider), isA<ChannelVpnService>());
  });

  test('vpnAdapterProvider uses RealVpnAdapter by default', () {
    final container = ProviderContainer(overrides: [
      appConfigProvider.overrideWith(
        (ref) => AppConfig(
          apiBaseUrl: 'https://example.invalid',
          portalUrl: 'https://example.invalid',
          upgradeUrl: 'https://example.invalid',
          resetSessionOnBoot: false,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    expect(container.read(vpnAdapterProvider), isA<RealVpnAdapter>());
  });
}
