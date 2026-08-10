import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final externalLinksProvider =
    Provider<ExternalLinksService>((_) => ExternalLinksService());

class ExternalLinksService {
  static const MethodChannel _channel = MethodChannel('securewave/links');

  Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod<void>('openUrl', {'url': url});
    } on PlatformException {
      // The action is best-effort; the platform owns external URL handling.
    } on MissingPluginException {
      // Some test and development runners do not register the link channel.
    }
  }
}
