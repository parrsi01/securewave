import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/config/app_config.dart';

void main() {
  test('normalizes a live API host to the backend API path', () {
    expect(
      AppConfig.normalizeApiBaseUrl('https://api.securewaveapp.com'),
      'https://api.securewaveapp.com/api',
    );
  });

  test('removes trailing slashes without changing the API path', () {
    expect(
      AppConfig.normalizeApiBaseUrl('https://api.securewaveapp.com/api/'),
      'https://api.securewaveapp.com/api',
    );
  });

  test('allows an explicit local API for development builds', () {
    expect(
      AppConfig.normalizeApiBaseUrl('http://localhost:8000/api'),
      'http://localhost:8000/api',
    );
  });

  test('rejects a base URL that cannot address the backend API contract', () {
    expect(
      () => AppConfig.normalizeApiBaseUrl('https://api.securewaveapp.com/v1'),
      throwsFormatException,
    );
  });
}
