import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
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
    this.debugAutoLogin = false,
    this.debugEmail,
    this.debugPassword,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final bool useMockApi;
  final bool resetSessionOnBoot;
  final bool debugAutoLogin;
  final String? debugEmail;
  final String? debugPassword;
  static AppConfig? _cached;

  /// Linux distribution builds always use the real control plane and native
  /// helper.  Test-only callers can still construct an [AppConfig] with mock
  /// mode explicitly, but environment configuration must not turn a Linux
  /// customer build into a demo client.
  static bool get isLinuxRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  factory AppConfig.defaults() {
    // Daily-use builds default to the live control plane. Mock data is opt-in
    // through SECUREWAVE_USE_MOCK_API for isolated UI tests and demos.
    final liveLinuxRuntime = isLinuxRuntime;
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
      useMockApi: !liveLinuxRuntime &&
          _parseBool(const String.fromEnvironment(
            'SECUREWAVE_USE_MOCK_API',
            defaultValue: 'false',
          )),
      resetSessionOnBoot: false,
      debugAutoLogin: !liveLinuxRuntime &&
          !kReleaseMode &&
          _parseBool(const String.fromEnvironment(
            'SECUREWAVE_DEBUG_AUTO_LOGIN',
            defaultValue: 'false',
          )),
      debugEmail: const String.fromEnvironment('SECUREWAVE_DEBUG_EMAIL'),
      debugPassword: const String.fromEnvironment('SECUREWAVE_DEBUG_PASSWORD'),
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
    final baseUrl = _compileTimeOrEnvOrFallback(
      env,
      'SECUREWAVE_API_BASE_URL',
      AppConstants.baseUrlFallback,
    );
    final portalUrl = _compileTimeOrEnvOrFallback(
      env,
      'SECUREWAVE_PORTAL_URL',
      AppConstants.portalUrlFallback,
    );
    final upgradeUrl = _compileTimeOrEnvOrFallback(
      env,
      'SECUREWAVE_UPGRADE_URL',
      AppConstants.upgradeUrlFallback,
    );
    // Mock API must be explicitly requested in test/demo builds. It is never
    // permitted for a Linux customer runtime, including a debug-launched
    // binary that happens to inherit a demo .env file.
    final liveLinuxRuntime = isLinuxRuntime;
    var useMock = _parseBool(
      env['SECUREWAVE_USE_MOCK_API'] ??
          const String.fromEnvironment('SECUREWAVE_USE_MOCK_API',
              defaultValue: 'false'),
    );
    if ((kReleaseMode || liveLinuxRuntime) && useMock) {
      AppLogger.warning(
        'Config: mock API disabled for release/Linux customer builds.',
      );
      useMock = false;
    }
    final resetSessionOnBoot = _parseBool(
      env['SECUREWAVE_RESET_SESSION_ON_BOOT'] ??
          const String.fromEnvironment(
            'SECUREWAVE_RESET_SESSION_ON_BOOT',
            defaultValue: 'false',
          ),
    );
    final debugAutoLogin = !liveLinuxRuntime &&
        !kReleaseMode &&
        _parseBool(_envOrDefault(
          env,
          'SECUREWAVE_DEBUG_AUTO_LOGIN',
          const String.fromEnvironment(
            'SECUREWAVE_DEBUG_AUTO_LOGIN',
            defaultValue: 'false',
          ),
        ));
    final debugEmail = _envOrDefault(
      env,
      'SECUREWAVE_DEBUG_EMAIL',
      const String.fromEnvironment('SECUREWAVE_DEBUG_EMAIL'),
    );
    final debugPassword = _envOrDefault(
      env,
      'SECUREWAVE_DEBUG_PASSWORD',
      const String.fromEnvironment('SECUREWAVE_DEBUG_PASSWORD'),
    );

    _cached = AppConfig(
      apiBaseUrl: baseUrl,
      portalUrl: portalUrl,
      upgradeUrl: upgradeUrl,
      useMockApi: useMock,
      resetSessionOnBoot: resetSessionOnBoot,
      debugAutoLogin: debugAutoLogin,
      debugEmail: debugEmail.isEmpty ? null : debugEmail,
      debugPassword: debugPassword.isEmpty ? null : debugPassword,
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

  static String _compileTimeOrEnvOrFallback(
      Map<String, String> env, String key, String fallback) {
    final compileTime = _compileTimeOrFallback(key, '');
    if (compileTime.trim().isNotEmpty) return compileTime;
    return _envOrDefault(env, key, fallback);
  }

  static bool _parseBool(String value) {
    return value.toLowerCase() == 'true' ||
        value == '1' ||
        value.toLowerCase() == 'yes';
  }
}
