import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';

final appConfigProvider = StateProvider<AppConfig>((_) => AppConfig.defaults());

class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.demoMode = false});

  final String apiBaseUrl;
  final bool demoMode;

  /// Configuration used by the standalone demo entrypoint.
  ///
  /// Demo services never make a network request, so this URL is intentionally
  /// non-routable and cannot be mistaken for the real beta API.
  static const demoConfig = AppConfig(
    apiBaseUrl: 'https://demo.invalid',
    demoMode: true,
  );

  factory AppConfig.defaults() {
    const configured = String.fromEnvironment('SECUREWAVE_API_BASE_URL');
    const demo =
        bool.fromEnvironment('SECUREWAVE_DEMO_MODE', defaultValue: false);
    final api = configured.trim().isEmpty
        ? AppConstants.baseUrlFallback
        : configured.trim();
    _validateApiUrl(api);
    return const AppConfig(apiBaseUrl: configured, demoMode: demo).withApi(api);
  }

  static Future<AppConfig> load() async => AppConfig.defaults();

  AppConfig withApi(String api) =>
      AppConfig(apiBaseUrl: api, demoMode: demoMode);

  static void _validateApiUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        value.contains('localhost') ||
        value.contains('127.0.0.1')) {
      throw StateError(
          'SECUREWAVE_API_BASE_URL must be an absolute non-local API URL.');
    }
  }
}
