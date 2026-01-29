import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/bootstrap/boot_controller.dart';

void main() {
  testWidgets('SecureWave app config provider initializes', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith(
          (ref) => AppConfig(
            apiBaseUrl: 'https://example.com',
            portalUrl: 'https://portal.example.com',
            upgradeUrl: 'https://upgrade.example.com',
            adblockListUrl: 'https://adblock.example.com/list.txt',
            useMockApi: true,
            resetSessionOnBoot: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final config = container.read(appConfigProvider);
    expect(config.apiBaseUrl, 'https://example.com');
    expect(config.useMockApi, isTrue);
    expect(config.resetSessionOnBoot, isFalse);
  });

  test('BootState has correct initial values', () {
    const state = BootState(status: BootStatus.initializing);
    expect(state.status, BootStatus.initializing);
    expect(state.errorMessage, isNull);
  });

  test('BootState copyWith works correctly', () {
    const state = BootState(status: BootStatus.initializing);
    final ready = state.copyWith(status: BootStatus.ready);
    expect(ready.status, BootStatus.ready);

    final failed = state.copyWith(status: BootStatus.failed, errorMessage: 'timeout');
    expect(failed.status, BootStatus.failed);
    expect(failed.errorMessage, 'timeout');
  });
}
