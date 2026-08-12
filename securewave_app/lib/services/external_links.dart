import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

final externalLinksProvider = Provider<ExternalLinksService>(
  (_) => ExternalLinksService(),
);

class ExternalLinksService {
  static const MethodChannel _channel = MethodChannel('securewave/links');

  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      AppLogger.warning('Refused non-HTTPS or malformed external link.');
      return;
    }
    try {
      await _channel.invokeMethod<void>('openUrl', {'url': uri.toString()});
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error(
        'Failed to open URL',
        error: error,
        stackTrace: stackTrace,
      );
    } on MissingPluginException {
      AppLogger.warning('Link channel not ready.');
    }
  }
}
