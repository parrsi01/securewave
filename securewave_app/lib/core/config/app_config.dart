import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../logging/app_logger.dart';

final appConfigProvider = StateProvider<AppConfig>((_) => AppConfig.defaults());

class AppConfig {
  AppConfig({
    required this.apiBaseUrl,
    required this.portalUrl,
    required this.upgradeUrl,
    required this.adblockListUrl,
    required this.useMockApi,
    required this.resetSessionOnBoot,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final String adblockListUrl;
  final bool useMockApi;
  final bool resetSessionOnBoot;
  static AppConfig? _cached;

  factory AppConfig.defaults() {
    // CRITICAL: Do NOT default to mock in release/profile builds
    const bool kIsDebugMode = bool.fromEnvironment('dart.vm.product') == false;
    return AppConfig(
      apiBaseUrl: AppConstants.baseUrlFallback,
      portalUrl: AppConstants.portalUrlFallback,
      upgradeUrl: AppConstants.upgradeUrlFallback,
      adblockListUrl: AppConstants.adblockListUrlFallback,
      useMockApi: kIsDebugMode, // Only mock in debug by default
      resetSessionOnBoot: false,
    );
  }

  static Future<AppConfig> load() async {
    if (_cached != null) return _cached!;
    try {
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: '.env');
      }
    } catch (error, stackTrace) {
      AppLogger.warning('Config: .env load failed, using defaults');
      AppLogger.error('Config: .env load error', error: error, stackTrace: stackTrace);
    }

    final env = dotenv.isInitialized ? dotenv.env : const <String, String>{};
    final baseUrl = _envOrDefault(
      env,
      'SECUREWAVE_API_BASE_URL',
      AppConstants.baseUrlFallback,
    );
    final portalUrl = _envOrDefault(
      env,
      'SECUREWAVE_PORTAL_URL',
      AppConstants.portalUrlFallback,
    );
    final upgradeUrl = _envOrDefault(
      env,
      'SECUREWAVE_UPGRADE_URL',
      AppConstants.upgradeUrlFallback,
    );
    final adblockUrl = _envOrDefault(
      env,
      'SECUREWAVE_ADBLOCK_LIST_URL',
      AppConstants.adblockListUrlFallback,
    );
    // CRITICAL: In release/profile, default to false unless explicitly enabled via env
    const bool kIsDebugMode = bool.fromEnvironment('dart.vm.product') == false;
    final useMock = _parseBool(
      env['SECUREWAVE_USE_MOCK_API'] ??
          const String.fromEnvironment('SECUREWAVE_USE_MOCK_API',
            defaultValue: kIsDebugMode ? 'true' : 'false'),
    );
    final resetSessionOnBoot = _parseBool(
      env['SECUREWAVE_RESET_SESSION_ON_BOOT'] ??
          const String.fromEnvironment(
            'SECUREWAVE_RESET_SESSION_ON_BOOT',
            defaultValue: 'false',
          ),
    );

    _cached = AppConfig(
      apiBaseUrl: baseUrl,
      portalUrl: portalUrl,
      upgradeUrl: upgradeUrl,
      adblockListUrl: adblockUrl,
      useMockApi: useMock,
      resetSessionOnBoot: resetSessionOnBoot,
    );
    return _cached!;
  }

  static String _envOrDefault(Map<String, String> env, String key, String fallback) {
    final value = env[key];
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  static bool _parseBool(String value) {
    return value.toLowerCase() == 'true' || value == '1' || value.toLowerCase() == 'yes';
  }
}
