import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';

final appConfigProvider = StateProvider<AppConfig>((_) => AppConfig.defaults());

class AppConfig {
  AppConfig({
    required this.apiBaseUrl,
    required this.portalUrl,
    required this.upgradeUrl,
    required this.adblockListUrl,
    required this.useMockApi,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final String adblockListUrl;
  final bool useMockApi;

  factory AppConfig.defaults() {
    return AppConfig(
      apiBaseUrl: AppConstants.baseUrlFallback,
      portalUrl: AppConstants.portalUrlFallback,
      upgradeUrl: AppConstants.upgradeUrlFallback,
      adblockListUrl: AppConstants.adblockListUrlFallback,
      useMockApi: true,
    );
  }

  static Future<AppConfig> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Defaults keep the app booting even without a .env file.
    }

    final baseUrl = dotenv.env['SECUREWAVE_API_BASE_URL'] ??
        const String.fromEnvironment(
          'SECUREWAVE_API_BASE_URL',
          defaultValue: AppConstants.baseUrlFallback,
        );
    final portalUrl = dotenv.env['SECUREWAVE_PORTAL_URL'] ??
        const String.fromEnvironment(
          'SECUREWAVE_PORTAL_URL',
          defaultValue: AppConstants.portalUrlFallback,
        );
    final upgradeUrl = dotenv.env['SECUREWAVE_UPGRADE_URL'] ??
        const String.fromEnvironment(
          'SECUREWAVE_UPGRADE_URL',
          defaultValue: AppConstants.upgradeUrlFallback,
        );
    final adblockUrl = dotenv.env['SECUREWAVE_ADBLOCK_LIST_URL'] ??
        const String.fromEnvironment(
          'SECUREWAVE_ADBLOCK_LIST_URL',
          defaultValue: AppConstants.adblockListUrlFallback,
        );
    final useMock = _parseBool(
      dotenv.env['SECUREWAVE_USE_MOCK_API'] ??
          const String.fromEnvironment('SECUREWAVE_USE_MOCK_API', defaultValue: 'true'),
    );

    return AppConfig(
      apiBaseUrl: baseUrl,
      portalUrl: portalUrl,
      upgradeUrl: upgradeUrl,
      adblockListUrl: adblockUrl,
      useMockApi: useMock,
    );
  }

  static bool _parseBool(String value) {
    return value.toLowerCase() == 'true' || value == '1' || value.toLowerCase() == 'yes';
  }
}
