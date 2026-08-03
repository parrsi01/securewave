import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../logging/app_logger.dart';

final appConfigProvider = StateProvider<AppConfig>((_) => AppConfig.defaults());

class AppConfig {
  static const bool _isReleaseBuild =
      bool.fromEnvironment('dart.vm.product', defaultValue: false);

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
    // Daily-use builds default to the live control plane. Mock data is opt-in
    // through SECUREWAVE_USE_MOCK_API for isolated UI tests and demos.
    return AppConfig(
      apiBaseUrl: normalizeApiBaseUrl(
        _compileTimeOrFallback(
          'SECUREWAVE_API_BASE_URL',
          AppConstants.baseUrlFallback,
        ),
      ),
      portalUrl: _compileTimeOrFallback(
        'SECUREWAVE_PORTAL_URL',
        AppConstants.portalUrlFallback,
      ),
      upgradeUrl: _compileTimeOrFallback(
        'SECUREWAVE_UPGRADE_URL',
        AppConstants.upgradeUrlFallback,
      ),
      useMockApi: _isReleaseBuild
          ? false
          : _parseBool(const String.fromEnvironment(
              'SECUREWAVE_USE_MOCK_API',
              defaultValue: 'false',
            )),
      resetSessionOnBoot: false,
    );
  }

  static Future<AppConfig> load() async {
    if (_cached != null) return _cached!;
    if (!_isReleaseBuild) {
      try {
        if (!dotenv.isInitialized) {
          await dotenv.load(fileName: '.env', isOptional: true);
        }
      } catch (error, stackTrace) {
        AppLogger.warning('Config: .env load failed, using defaults');
        AppLogger.error('Config: .env load error',
            error: error, stackTrace: stackTrace);
      }
    }

    // A release bundle must not inherit a developer .env asset. Release
    // builds receive the API explicitly through dart-define and otherwise use
    // the live fallback below.
    final env = !_isReleaseBuild && dotenv.isInitialized
        ? dotenv.env
        : const <String, String>{};
    final baseUrl = normalizeApiBaseUrl(_envOrDefault(
      env,
      'SECUREWAVE_API_BASE_URL',
      _compileTimeOrFallback(
        'SECUREWAVE_API_BASE_URL',
        AppConstants.baseUrlFallback,
      ),
    ));
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
    var useMock = _parseBool(
      env['SECUREWAVE_USE_MOCK_API'] ??
          const String.fromEnvironment('SECUREWAVE_USE_MOCK_API',
              defaultValue: 'false'),
    );
    if (_isReleaseBuild && useMock) {
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
    return value.trim();
  }

  /// Normalize the base URL used by every relative API request.
  ///
  /// The backend is mounted below `/api`, while ApiClient paths intentionally
  /// omit that prefix. A host-only override would therefore send requests to
  /// the wrong route, so it is upgraded to `/api`; non-API paths are rejected
  /// instead of being silently accepted.
  static String normalizeApiBaseUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('API base URL must not be empty.');
    }

    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      throw FormatException('API base URL is not an absolute URL: $value');
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw FormatException('API base URL must use HTTP or HTTPS: $value');
    }
    if (uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
          'API base URL must not contain credentials, query parameters, or fragments.');
    }

    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.isEmpty) path = '/api';
    if (path != '/api' && !path.endsWith('/api')) {
      throw FormatException(
          'API base URL must identify the backend /api path: $value');
    }

    final normalized = uri.replace(scheme: scheme, path: path).toString();
    if (_isReleaseBuild && (scheme != 'https' || _isLocalHost(uri.host))) {
      throw const FormatException(
          'Release builds require a non-local HTTPS API base URL.');
    }
    return normalized;
  }

  static bool _isLocalHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '::1' ||
        normalized == '0.0.0.0' ||
        normalized == '127.0.0.1' ||
        normalized.startsWith('127.');
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
