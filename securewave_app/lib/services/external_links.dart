import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

final externalLinksProvider =
    Provider<ExternalLinksService>((_) => ExternalLinksService());

class ExternalLinksService {
  static const MethodChannel _channel = MethodChannel('securewave/links');

  Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      AppLogger.warning('Blocked an invalid external link request.');
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on PlatformException {
      AppLogger.warning('External link request failed.');
      return false;
    } on MissingPluginException {
      AppLogger.warning('External link channel is not ready.');
      return false;
    }
  }
}
