import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/logging/app_logger.dart';

void main() {
  setUp(() {
    AppLogger.logStream.value = <AppLogEntry>[];
    AppLogger.errorStream.value = null;
  });

  test('redacts sensitive structured log fields', () {
    AppLogger.vpn(
      'API',
      'PROFILE_GENERATED',
      fields: <String, Object?>{
        'email': 'user@example.com',
        'access_token': 'token-123',
        'server_id': 'de-nue-1',
      },
    );

    final entry = AppLogger.logStream.value.single.message;
    expect(entry, contains('email=[REDACTED]'));
    expect(entry, contains('access_token=[REDACTED]'));
    expect(entry, contains('server_id=de-nue-1'));
    expect(entry, isNot(contains('user@example.com')));
    expect(entry, isNot(contains('token-123')));
  });
}
