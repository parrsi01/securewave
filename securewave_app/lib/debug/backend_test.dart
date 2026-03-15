import 'package:http/http.dart' as http;

import '../core/logging/app_logger.dart';

Future<void> testBackend() async {
  try {
    final response = await http.get(
      Uri.parse('https://138.199.204.139.nip.io/api/health'),
    );
    AppLogger.info('BACKEND STATUS: ${response.statusCode}');
    AppLogger.info('BACKEND BODY: ${response.body}');
  } catch (error, stackTrace) {
    AppLogger.error(
      'Backend test failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
