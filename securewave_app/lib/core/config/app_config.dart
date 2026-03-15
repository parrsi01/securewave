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
    this.httpsPreferred = false,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final bool resetSessionOnBoot;
  final bool httpsPreferred;
  static AppConfig? _cached;
  static const String _allowLoopbackKey = 'SECUREWAVE_ALLOW_LOCALHOST_API';

  factory AppConfig.defaults() {
    return AppConfig(
      apiBaseUrl: AppConstants.baseUrlFallback,
      portalUrl: AppConstants.portalUrlFallback,
      upgradeUrl: AppConstants.upgradeUrlFallback,
      resetSessionOnBoot: false,
      httpsPreferred: false,
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
    const defineLiveBaseUrl =
        String.fromEnvironment('LIVE_API_BASE_URL', defaultValue: '');
    const defineApiBaseUrl =
        String.fromEnvironment('API_BASE_URL', defaultValue: '');
    const definePortalUrl =
        String.fromEnvironment('SECUREWAVE_PORTAL_URL', defaultValue: '');
    const defineUpgradeUrl =
        String.fromEnvironment('SECUREWAVE_UPGRADE_URL', defaultValue: '');

    final rawBaseUrl = _firstNonEmpty(
      defineBaseUrl,
      defineLiveBaseUrl,
      defineApiBaseUrl,
      env['SECUREWAVE_API_BASE_URL'],
      env['LIVE_API_BASE_URL'],
      env['API_BASE_URL'],
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
    final allowLoopbackApi = _parseBool(
      env[_allowLoopbackKey] ??
          const String.fromEnvironment(
            _allowLoopbackKey,
            defaultValue: 'false',
          ),
    );
    final baseUrl = _normalizeApiBaseUrl(
      rawBaseUrl,
      allowLoopback: allowLoopbackApi && !kReleaseMode,
    );
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
    final httpsPreferred = _parseBool(
      env['SECUREWAVE_PREFER_HTTPS'] ??
          const String.fromEnvironment(
            'SECUREWAVE_PREFER_HTTPS',
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
      httpsPreferred: httpsPreferred,
    );
    return _cached!;
  }

  static String _firstNonEmpty(
    String a, [
    String? b,
    String? c,
    String? d,
    String? e,
    String? f,
    String? g,
  ]) {
    for (final candidate in <String?>[a, b, c, d, e, f, g]) {
      final value = (candidate ?? '').trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static String _normalizeApiBaseUrl(
    String value, {
    bool allowLoopback = false,
  }) {
    final parsed = _parseAbsoluteHttpUri(
      value,
      allowLoopback: allowLoopback,
    );
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

  static Uri? _parseAbsoluteHttpUri(
    String value, {
    bool allowLoopback = false,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || !parsed.hasScheme || parsed.host.trim().isEmpty) {
      return null;
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return null;
    if (!allowLoopback && _isLoopbackHost(parsed.host)) {
      AppLogger.warning(
        'Config: rejected loopback API host `${parsed.host}`. '
        'Use $_allowLoopbackKey=true only for explicit local debug runs.',
      );
      return null;
    }
    return parsed;
  }

  static bool _isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '[::1]';
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
