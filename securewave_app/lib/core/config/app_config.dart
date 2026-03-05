import 'package:flutter/foundation.dart';
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

    final rawBaseUrl = _firstNonEmpty(
      defineBaseUrl,
      env['SECUREWAVE_API_BASE_URL'],
      AppConstants.baseUrlFallback,
    );
    final rawPortalUrl = _firstNonEmpty(
      definePortalUrl,
      env['SECUREWAVE_PORTAL_URL'],
      AppConstants.portalUrlFallback,
    );
    final rawUpgradeUrl = _firstNonEmpty(
      defineUpgradeUrl,
      env['SECUREWAVE_UPGRADE_URL'],
      AppConstants.upgradeUrlFallback,
    );
    final baseUrl = _normalizeApiBaseUrl(rawBaseUrl);
    final portalUrl = _normalizeAbsoluteUrl(
      rawPortalUrl,
      fallback: _deriveFromApiBase(baseUrl, '/account'),
    );
    final upgradeUrl = _normalizeAbsoluteUrl(
      rawUpgradeUrl,
      fallback: _deriveFromApiBase(baseUrl, '/subscription'),
    );
    final resetSessionOnBoot = _parseBool(
      env['SECUREWAVE_RESET_SESSION_ON_BOOT'] ??
          const String.fromEnvironment(
            'SECUREWAVE_RESET_SESSION_ON_BOOT',
            defaultValue: 'false',
          ),
    );

    if (kReleaseMode && baseUrl.startsWith('http://')) {
      AppLogger.error(
        'INSECURE_FALLBACK: apiBaseUrl resolved to plaintext HTTP in release build. '
        'Credentials and tokens will be transmitted unencrypted. '
        'Set SECUREWAVE_API_BASE_URL dart-define or .env to an HTTPS URL.',
      );
    }

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

  static String _normalizeApiBaseUrl(String value) {
    final parsed = _parseAbsoluteHttpUri(value);
    if (parsed == null) {
      return AppConstants.baseUrlFallback;
    }
    final segments =
        parsed.pathSegments.where((item) => item.isNotEmpty).toList();
    if (segments.isEmpty || segments.last.toLowerCase() != 'api') {
      segments.add('api');
    }
    final normalized = parsed.replace(
      path: '/${segments.join('/')}',
      query: null,
      fragment: null,
    );
    return normalized.toString();
  }

  static String _normalizeAbsoluteUrl(
    String value, {
    required String fallback,
  }) {
    final parsed = _parseAbsoluteHttpUri(value);
    if (parsed == null) return fallback;
    return parsed.replace(query: null, fragment: null).toString();
  }

  static Uri? _parseAbsoluteHttpUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || !parsed.hasScheme || parsed.host.trim().isEmpty) {
      return null;
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return null;
    return parsed;
  }

  static String _deriveFromApiBase(String apiBaseUrl, String path) {
    final parsed = _parseAbsoluteHttpUri(apiBaseUrl);
    if (parsed == null) return path;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return parsed
        .replace(path: normalizedPath, query: null, fragment: null)
        .toString();
  }

  static bool _parseBool(String value) {
    return value.toLowerCase() == 'true' ||
        value == '1' ||
        value.toLowerCase() == 'yes';
  }
}
