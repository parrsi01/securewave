import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

final externalLinksProvider = Provider<ExternalLinksService>((_) => ExternalLinksService());

class ExternalLinksService {
  static const MethodChannel _channel = MethodChannel('securewave/links');

  Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error('Failed to open URL', error: error, stackTrace: stackTrace);
    } on MissingPluginException {
      AppLogger.warning('Link channel not ready. URL: $url');
    }
  }
}
