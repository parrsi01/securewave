import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../logging/app_logger.dart';

/// Returns the loaded [AppConfig] if [AppConfig.load] has already been awaited
/// in main() before ProviderScope initialises; falls back to [AppConfig.defaults]
/// on the first frame otherwise (typically only in tests).
final appConfigProvider =
    StateProvider<AppConfig>((_) => AppConfig._cached ?? AppConfig.defaults());

class AppConfig {
  AppConfig({
    required this.apiBaseUrl,
    required this.portalUrl,
    required this.upgradeUrl,
    required this.resetSessionOnBoot,
    this.devLoginEmail,
    this.devLoginPassword,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final bool resetSessionOnBoot;
  final String? devLoginEmail;
  final String? devLoginPassword;
  static AppConfig? _cached;

  factory AppConfig.defaults() {
    // For local desktop debugging, prefer the preview backend automatically.
    const localDebugApi = !kReleaseMode ? 'http://127.0.0.1:8080/api' : null;
    const localDebugPortal = !kReleaseMode ? 'http://127.0.0.1:8080/account' : null;
    const localDebugUpgrade = !kReleaseMode ? 'http://127.0.0.1:8080/subscription' : null;
    return AppConfig(
      apiBaseUrl: localDebugApi ?? AppConstants.baseUrlFallback,
      portalUrl: localDebugPortal ?? AppConstants.portalUrlFallback,
      upgradeUrl: localDebugUpgrade ?? AppConstants.upgradeUrlFallback,
      resetSessionOnBoot: false,
      devLoginEmail: null,
      devLoginPassword: null,
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

    // Prefer build-time dart-defines for release builds. This avoids shipping a
    // hardcoded `.env` and makes CI/release pipelines deterministic.
    const defineBaseUrl =
        String.fromEnvironment('SECUREWAVE_API_BASE_URL', defaultValue: '');
    const definePortalUrl =
        String.fromEnvironment('SECUREWAVE_PORTAL_URL', defaultValue: '');
    const defineUpgradeUrl =
        String.fromEnvironment('SECUREWAVE_UPGRADE_URL', defaultValue: '');

    const debugDefaultApi = !kReleaseMode ? 'http://127.0.0.1:8080/api' : AppConstants.baseUrlFallback;
    const debugDefaultPortal = !kReleaseMode ? 'http://127.0.0.1:8080/account' : AppConstants.portalUrlFallback;
    const debugDefaultUpgrade = !kReleaseMode ? 'http://127.0.0.1:8080/subscription' : AppConstants.upgradeUrlFallback;

    final baseUrl = _firstNonEmpty(
      defineBaseUrl,
      env['SECUREWAVE_API_BASE_URL'],
      debugDefaultApi,
    );
    final portalUrl = _firstNonEmpty(
      definePortalUrl,
      env['SECUREWAVE_PORTAL_URL'],
      debugDefaultPortal,
    );
    final upgradeUrl = _firstNonEmpty(
      defineUpgradeUrl,
      env['SECUREWAVE_UPGRADE_URL'],
      debugDefaultUpgrade,
    );
    final resetSessionOnBoot = _parseBool(
      env['SECUREWAVE_RESET_SESSION_ON_BOOT'] ??
          const String.fromEnvironment(
            'SECUREWAVE_RESET_SESSION_ON_BOOT',
            defaultValue: 'false',
          ),
    );
    final devLoginEmail = _optionalTrimmed(
      env['SECUREWAVE_DEV_LOGIN_EMAIL'],
      const String.fromEnvironment('SECUREWAVE_DEV_LOGIN_EMAIL',
          defaultValue: ''),
    );
    final devLoginPassword = _optionalTrimmed(
      env['SECUREWAVE_DEV_LOGIN_PASSWORD'],
      const String.fromEnvironment('SECUREWAVE_DEV_LOGIN_PASSWORD',
          defaultValue: ''),
    );

    _cached = AppConfig(
      apiBaseUrl: baseUrl,
      portalUrl: portalUrl,
      upgradeUrl: upgradeUrl,
      resetSessionOnBoot: resetSessionOnBoot,
      devLoginEmail: devLoginEmail,
      devLoginPassword: devLoginPassword,
    );

    // Warn loudly if a release build fell through to the hardcoded fallback URL.
    // This means SECUREWAVE_API_BASE_URL was not provided via dart-define or .env.
    if (kReleaseMode && baseUrl == AppConstants.baseUrlFallback) {
      AppLogger.error(
        'Config: INSECURE_FALLBACK — release build is using the hardcoded bare-IP '
        'fallback URL. Provide SECUREWAVE_API_BASE_URL via --dart-define or .env.',
      );
    }

    AppLogger.info(
      'Config loaded: apiBaseUrl=${_cached!.apiBaseUrl} '
      'portalUrl=${_cached!.portalUrl} '
      'upgradeUrl=${_cached!.upgradeUrl} '
      'resetSessionOnBoot=${_cached!.resetSessionOnBoot} '
      'mode=${kReleaseMode ? "release" : kProfileMode ? "profile" : "debug"}',
    );
    return _cached!;
  }

  static String _firstNonEmpty(String a, String? b, String c) {
    if (a.trim().isNotEmpty) return a.trim();
    final bb = (b ?? '').trim();
    if (bb.isNotEmpty) return bb;
    return c;
  }

  static bool _parseBool(String value) {
    return value.toLowerCase() == 'true' ||
        value == '1' ||
        value.toLowerCase() == 'yes';
  }

  static String? _optionalTrimmed(String? a, [String? b]) {
    final first = (a ?? '').trim();
    if (first.isNotEmpty) return first;
    final second = (b ?? '').trim();
    if (second.isNotEmpty) return second;
    return null;
  }
}
