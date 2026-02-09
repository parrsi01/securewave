import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('vpnServiceProvider uses MockVpnService when mock API is enabled', () {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith(
          (ref) => AppConfig(
            apiBaseUrl: 'https://example.invalid',
            portalUrl: 'https://example.invalid',
            upgradeUrl: 'https://example.invalid',
            useMockApi: true,
            resetSessionOnBoot: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(vpnServiceProvider), isA<MockVpnService>());
  });

  test('vpnServiceProvider uses ChannelVpnService when mock API is disabled', () {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith(
          (ref) => AppConfig(
            apiBaseUrl: 'https://example.invalid',
            portalUrl: 'https://example.invalid',
            upgradeUrl: 'https://example.invalid',
            useMockApi: false,
            resetSessionOnBoot: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(vpnServiceProvider), isA<ChannelVpnService>());
  });
}
