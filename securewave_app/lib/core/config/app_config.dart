import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../logging/app_logger.dart';

final appConfigProvider = StateProvider<AppConfig>((_) => AppConfig.defaults());

enum AppConfigSource { dartDefine, envAsset, fallback }

extension on AppConfigSource {
  String get label => switch (this) {
        AppConfigSource.dartDefine => 'dart_define',
        AppConfigSource.envAsset => 'env_asset',
        AppConfigSource.fallback => 'fallback',
      };
}

class AppConfig {
  AppConfig({
    required this.apiBaseUrl,
    required this.portalUrl,
    required this.upgradeUrl,
    required this.resetSessionOnBoot,
    this.configSource = AppConfigSource.fallback,
    this.httpsPreferred = false,
  });

  final String apiBaseUrl;
  final String portalUrl;
  final String upgradeUrl;
  final bool resetSessionOnBoot;
  final AppConfigSource configSource;
  final bool httpsPreferred;
  static AppConfig? _cached;
  static const String _allowLoopbackKey = 'SECUREWAVE_ALLOW_LOCALHOST_API';
  static const String _defaultEnvFileName = '.env';

  factory AppConfig.defaults() {
    return AppConfig(
      apiBaseUrl: AppConstants.baseUrlFallback,
      portalUrl: AppConstants.portalUrlFallback,
      upgradeUrl: AppConstants.upgradeUrlFallback,
      resetSessionOnBoot: false,
      configSource: AppConfigSource.fallback,
      httpsPreferred: false,
    );
  }

  static Future<AppConfig> load({
    bool forceReload = false,
    String envFileName = _defaultEnvFileName,
  }) async {
    if (!forceReload && _cached != null) return _cached!;

    var assetEnv = const <String, String>{};
    var assetEnvLoaded = false;
    try {
      if (forceReload || !dotenv.isInitialized) {
        await dotenv.load(
          fileName: envFileName,
          isOptional: true,
        );
      }
      assetEnv = Map<String, String>.from(dotenv.env);
      assetEnvLoaded = _hasConfiguredBaseUrl(assetEnv);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Config: asset env load failed for `$envFileName`; '
        'falling back to dart-defines or defaults.',
      );
      AppLogger.error(
        'Config: asset env load error',
        error: error,
        stackTrace: stackTrace,
      );
    }

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

    final config = _resolveConfig(
      assetEnv: assetEnv,
      defineBaseUrl: defineBaseUrl,
      defineLiveBaseUrl: defineLiveBaseUrl,
      defineApiBaseUrl: defineApiBaseUrl,
      definePortalUrl: definePortalUrl,
      defineUpgradeUrl: defineUpgradeUrl,
    );

    if (kReleaseMode && config.apiBaseUrl.startsWith('http://')) {
      AppLogger.error(
        'INSECURE_FALLBACK: apiBaseUrl resolved to plaintext HTTP in release build. '
        'Credentials and tokens will be transmitted unencrypted. '
        'Set SECUREWAVE_API_BASE_URL dart-define or packaged .env to an HTTPS URL.',
      );
    }

    _logResolvedConfig(
      config,
      envFileName: envFileName,
      assetEnvLoaded: assetEnvLoaded,
    );
    _cached = config;
    return _cached!;
  }

  @visibleForTesting
  static AppConfig resolveForTest({
    Map<String, String> assetEnv = const <String, String>{},
    String defineBaseUrl = '',
    String defineLiveBaseUrl = '',
    String defineApiBaseUrl = '',
    String definePortalUrl = '',
    String defineUpgradeUrl = '',
    String defineResetSessionOnBoot = 'false',
    String definePreferHttps = 'false',
    String defineAllowLoopbackApi = 'false',
  }) {
    return _resolveConfig(
      assetEnv: assetEnv,
      defineBaseUrl: defineBaseUrl,
      defineLiveBaseUrl: defineLiveBaseUrl,
      defineApiBaseUrl: defineApiBaseUrl,
      definePortalUrl: definePortalUrl,
      defineUpgradeUrl: defineUpgradeUrl,
      defineResetSessionOnBoot: defineResetSessionOnBoot,
      definePreferHttps: definePreferHttps,
      defineAllowLoopbackApi: defineAllowLoopbackApi,
    );
  }

  @visibleForTesting
  static void resetForTest() {
    _cached = null;
    dotenv.clean();
  }

  static String _firstNonEmpty(
    String? a, [
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

  static AppConfig _resolveConfig({
    required Map<String, String> assetEnv,
    String defineBaseUrl = '',
    String defineLiveBaseUrl = '',
    String defineApiBaseUrl = '',
    String definePortalUrl = '',
    String defineUpgradeUrl = '',
    String defineResetSessionOnBoot = const String.fromEnvironment(
      'SECUREWAVE_RESET_SESSION_ON_BOOT',
      defaultValue: 'false',
    ),
    String definePreferHttps = const String.fromEnvironment(
      'SECUREWAVE_PREFER_HTTPS',
      defaultValue: 'false',
    ),
    String defineAllowLoopbackApi = const String.fromEnvironment(
      _allowLoopbackKey,
      defaultValue: 'false',
    ),
  }) {
    final rawDefinedBaseUrl = _firstNonEmpty(
      defineBaseUrl,
      defineLiveBaseUrl,
      defineApiBaseUrl,
    );
    final rawAssetBaseUrl = _firstNonEmpty(
      assetEnv['SECUREWAVE_API_BASE_URL'],
      assetEnv['LIVE_API_BASE_URL'],
      assetEnv['API_BASE_URL'],
    );
    final allowLoopbackApi = _parseBool(
      assetEnv[_allowLoopbackKey] ?? defineAllowLoopbackApi,
    );
    final baseResolution = _resolveApiBaseUrl(
      rawDefinedBaseUrl,
      rawAssetBaseUrl,
      allowLoopback: allowLoopbackApi && !kReleaseMode,
    );
    final rawPortalUrl = _firstNonEmpty(
      definePortalUrl,
      assetEnv['SECUREWAVE_PORTAL_URL'],
    );
    final rawUpgradeUrl = _firstNonEmpty(
      defineUpgradeUrl,
      assetEnv['SECUREWAVE_UPGRADE_URL'],
    );
    final portalUrl = _normalizeAbsoluteUrl(
      rawPortalUrl,
      fallback: AppConstants.portalUrlFallback,
    );
    final upgradeUrl = _normalizeAbsoluteUrl(
      rawUpgradeUrl,
      fallback: AppConstants.upgradeUrlFallback,
    );
    final resetSessionOnBoot = _parseBool(
      assetEnv['SECUREWAVE_RESET_SESSION_ON_BOOT'] ?? defineResetSessionOnBoot,
    );
    final httpsPreferred = _parseBool(
      assetEnv['SECUREWAVE_PREFER_HTTPS'] ?? definePreferHttps,
    );

    return AppConfig(
      apiBaseUrl: baseResolution.baseUrl,
      portalUrl: portalUrl,
      upgradeUrl: upgradeUrl,
      resetSessionOnBoot: resetSessionOnBoot,
      configSource: baseResolution.source,
      httpsPreferred: httpsPreferred,
    );
  }

  static _ResolvedApiBaseUrl _resolveApiBaseUrl(
    String rawDefinedBaseUrl,
    String rawAssetBaseUrl, {
    required bool allowLoopback,
  }) {
    if (rawDefinedBaseUrl.trim().isNotEmpty) {
      final normalized = _tryNormalizeApiBaseUrl(
        rawDefinedBaseUrl,
        allowLoopback: allowLoopback,
      );
      if (normalized != null) {
        return _ResolvedApiBaseUrl(
          baseUrl: normalized,
          source: AppConfigSource.dartDefine,
        );
      }
      AppLogger.warning(
        'Config: ignoring invalid SECUREWAVE_API_BASE_URL dart-define and using fallback resolution.',
      );
    }

    if (rawAssetBaseUrl.trim().isNotEmpty) {
      final normalized = _tryNormalizeApiBaseUrl(
        rawAssetBaseUrl,
        allowLoopback: allowLoopback,
      );
      if (normalized != null) {
        return _ResolvedApiBaseUrl(
          baseUrl: normalized,
          source: AppConfigSource.envAsset,
        );
      }
      AppLogger.warning(
        'Config: ignoring invalid packaged .env API base URL and using fallback defaults.',
      );
    }

    return const _ResolvedApiBaseUrl(
      baseUrl: AppConstants.baseUrlFallback,
      source: AppConfigSource.fallback,
    );
  }

  static String? _tryNormalizeApiBaseUrl(
    String value, {
    bool allowLoopback = false,
  }) {
    final parsed = _parseAbsoluteHttpUri(
      value,
      allowLoopback: allowLoopback,
    );
    if (parsed == null) return null;
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

  static bool _hasConfiguredBaseUrl(Map<String, String> env) {
    return _firstNonEmpty(
      env['SECUREWAVE_API_BASE_URL'],
      env['LIVE_API_BASE_URL'],
      env['API_BASE_URL'],
    ).isNotEmpty;
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

  static bool _parseBool(String value) {
    return value.toLowerCase() == 'true' ||
        value == '1' ||
        value.toLowerCase() == 'yes';
  }

  static void _logResolvedConfig(
    AppConfig config, {
    required String envFileName,
    required bool assetEnvLoaded,
  }) {
    AppLogger.info(
      'Config loaded source=${config.configSource.label} '
      'env_asset=$envFileName '
      'env_asset_loaded=$assetEnvLoaded '
      'api_origin=${_urlOrigin(config.apiBaseUrl)}',
    );
  }

  static String _urlOrigin(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null) return 'invalid';
    final port = parsed.hasPort ? ':${parsed.port}' : '';
    return '${parsed.scheme}://${parsed.host}$port';
  }
}

class _ResolvedApiBaseUrl {
  const _ResolvedApiBaseUrl({
    required this.baseUrl,
    required this.source,
  });

  final String baseUrl;
  final AppConfigSource source;
}
