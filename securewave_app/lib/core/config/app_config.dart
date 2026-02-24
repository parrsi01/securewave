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
    required this.resetSessionOnBoot,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final bool resetSessionOnBoot;
  static AppConfig? _cached;

  factory AppConfig.defaults() {
    return AppConfig(
      apiBaseUrl: AppConstants.baseUrlFallback,
      portalUrl: AppConstants.portalUrlFallback,
      upgradeUrl: AppConstants.upgradeUrlFallback,
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

    // Prefer build-time dart-defines for release builds. This avoids shipping a
    // hardcoded `.env` and makes CI/release pipelines deterministic.
    const defineBaseUrl =
        String.fromEnvironment('SECUREWAVE_API_BASE_URL', defaultValue: '');
    const definePortalUrl =
        String.fromEnvironment('SECUREWAVE_PORTAL_URL', defaultValue: '');
    const defineUpgradeUrl =
        String.fromEnvironment('SECUREWAVE_UPGRADE_URL', defaultValue: '');

    final baseUrl = _firstNonEmpty(
      defineBaseUrl,
      env['SECUREWAVE_API_BASE_URL'],
      AppConstants.baseUrlFallback,
    );
    final portalUrl = _firstNonEmpty(
      definePortalUrl,
      env['SECUREWAVE_PORTAL_URL'],
      AppConstants.portalUrlFallback,
    );
    final upgradeUrl = _firstNonEmpty(
      defineUpgradeUrl,
      env['SECUREWAVE_UPGRADE_URL'],
      AppConstants.upgradeUrlFallback,
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
      resetSessionOnBoot: resetSessionOnBoot,
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
    return value.toLowerCase() == 'true' || value == '1' || value.toLowerCase() == 'yes';
  }
}
