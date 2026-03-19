import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/constants/app_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppConfig.resetForTest);

  testWidgets('loads packaged .env config for desktop runtime',
      (WidgetTester tester) async {
    final config = await AppConfig.load(forceReload: true);

    expect(config.configSource, AppConfigSource.envAsset);
    expect(config.apiBaseUrl, 'https://138.199.204.139.nip.io/api');
    expect(config.portalUrl, 'https://138.199.204.139.nip.io/account');
    expect(
      config.upgradeUrl,
      'https://138.199.204.139.nip.io/subscription',
    );
    expect(config.resetSessionOnBoot, isFalse);
  });

  testWidgets('uses fallback only when the env asset is unavailable',
      (WidgetTester tester) async {
    final config = await AppConfig.load(
      forceReload: true,
      envFileName: 'missing.env',
    );

    expect(config.configSource, AppConfigSource.fallback);
    expect(config.apiBaseUrl, AppConstants.baseUrlFallback);
    expect(config.portalUrl, AppConstants.portalUrlFallback);
    expect(config.upgradeUrl, AppConstants.upgradeUrlFallback);
  });
}
