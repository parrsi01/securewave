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
    this.skipLoginForDevelopment = false,
    required this.resetSessionOnBoot,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final bool useMockApi;
  final bool skipLoginForDevelopment;
  final bool resetSessionOnBoot;
  static AppConfig? _cached;

  factory AppConfig.defaults() {
    // Daily-use builds default to the live control plane. Mock data is opt-in
    // through SECUREWAVE_USE_MOCK_API for isolated UI tests and demos.
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
          defaultValue: 'false',
        ),
      ),
      skipLoginForDevelopment: false,
      resetSessionOnBoot: false,
    );
  }

  static Future<AppConfig> load() async {
    if (_cached != null) return _cached!;
    try {
      if (!dotenv.isInitialized) {
        // Runtime configuration is optional. Release artifacts must not need
        // a generated or secret-bearing asset just to start.
        await dotenv.load(fileName: '.env', isOptional: true);
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
    // Mock API must be explicitly requested in every build mode.
    const bool kIsReleaseMode = bool.fromEnvironment('dart.vm.product');
    var useMock = _parseBool(
      env['SECUREWAVE_USE_MOCK_API'] ??
          const String.fromEnvironment('SECUREWAVE_USE_MOCK_API',
              defaultValue: 'false'),
    );
    final skipLoginRequested = _parseBool(
      env['SECUREWAVE_SKIP_LOGIN'] ??
          const String.fromEnvironment('SECUREWAVE_SKIP_LOGIN',
              defaultValue: 'false'),
    );
    if (kIsReleaseMode && useMock) {
      AppLogger.warning('Config: mock API disabled in release builds.');
      useMock = false;
    }
    final skipLoginForDevelopment =
        !kIsReleaseMode && useMock && skipLoginRequested;
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
      skipLoginForDevelopment: skipLoginForDevelopment,
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
