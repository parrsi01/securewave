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
    required this.useMockApi,
    required this.resetSessionOnBoot,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final bool useMockApi;
  final bool resetSessionOnBoot;
  static AppConfig? _cached;

  factory AppConfig.defaults() {
    // CRITICAL: Do NOT default to mock in release/profile builds
    const bool kIsDebugMode = bool.fromEnvironment('dart.vm.product') == false;
    return AppConfig(
      apiBaseUrl: _compileTimeOrFallback(
        'SECUREWAVE_API_BASE_URL',
        AppConstants.baseUrlFallback,
      ),
      portalUrl: _compileTimeOrFallback(
        'SECUREWAVE_PORTAL_URL',
        AppConstants.portalUrlFallback,
      ),
      upgradeUrl: _compileTimeOrFallback(
        'SECUREWAVE_UPGRADE_URL',
        AppConstants.upgradeUrlFallback,
      ),
      useMockApi: _parseBool(
        const String.fromEnvironment(
          'SECUREWAVE_USE_MOCK_API',
          defaultValue: kIsDebugMode ? 'true' : 'false',
        ),
      ),
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
      AppLogger.error('Config: .env load error',
          error: error, stackTrace: stackTrace);
    }

    final env = dotenv.isInitialized ? dotenv.env : const <String, String>{};
    final baseUrl = _envOrDefault(
      env,
      'SECUREWAVE_API_BASE_URL',
      _compileTimeOrFallback(
        'SECUREWAVE_API_BASE_URL',
        AppConstants.baseUrlFallback,
      ),
    );
    final portalUrl = _envOrDefault(
      env,
      'SECUREWAVE_PORTAL_URL',
      _compileTimeOrFallback(
        'SECUREWAVE_PORTAL_URL',
        AppConstants.portalUrlFallback,
      ),
    );
    final upgradeUrl = _envOrDefault(
      env,
      'SECUREWAVE_UPGRADE_URL',
      _compileTimeOrFallback(
        'SECUREWAVE_UPGRADE_URL',
        AppConstants.upgradeUrlFallback,
      ),
    );
    // CRITICAL: In release/profile, default to false unless explicitly enabled via env
    const bool kIsDebugMode = bool.fromEnvironment('dart.vm.product') == false;
    const bool kIsReleaseMode = bool.fromEnvironment('dart.vm.product');
    var useMock = _parseBool(
      env['SECUREWAVE_USE_MOCK_API'] ??
          const String.fromEnvironment('SECUREWAVE_USE_MOCK_API',
              defaultValue: kIsDebugMode ? 'true' : 'false'),
    );
    if (kIsReleaseMode && useMock) {
      AppLogger.warning('Config: mock API disabled in release builds.');
      useMock = false;
    }
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
      useMockApi: useMock,
      resetSessionOnBoot: resetSessionOnBoot,
    );
    return _cached!;
  }

  static String _envOrDefault(
      Map<String, String> env, String key, String fallback) {
    final value = env[key];
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  static String _compileTimeOrFallback(String key, String fallback) {
    final value = switch (key) {
      'SECUREWAVE_API_BASE_URL' =>
        const String.fromEnvironment('SECUREWAVE_API_BASE_URL'),
      'SECUREWAVE_PORTAL_URL' =>
        const String.fromEnvironment('SECUREWAVE_PORTAL_URL'),
      'SECUREWAVE_UPGRADE_URL' =>
        const String.fromEnvironment('SECUREWAVE_UPGRADE_URL'),
      _ => '',
    };
    return value.trim().isEmpty ? fallback : value;
  }

  static bool _parseBool(String value) {
    return value.toLowerCase() == 'true' ||
        value == '1' ||
        value.toLowerCase() == 'yes';
  }
}
