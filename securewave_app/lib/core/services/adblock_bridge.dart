import 'package:flutter/services.dart';

import '../logging/app_logger.dart';
import '../state/adblock_state.dart';

class AdblockBridge {
  static const MethodChannel _channel = MethodChannel('securewave/adblock');

  Future<void> sendConfig(AdblockState state) async {
    try {
      await _channel.invokeMethod('updateConfig', {
        'block_ads': state.blockAds,
        'block_malware': state.blockMalware,
        'strict_mode': state.strictMode,
        'last_updated': state.lastUpdated?.toIso8601String(),
      });
    } on PlatformException catch (error, stackTrace) {
      AppLogger.error('Adblock config send failed', error: error, stackTrace: stackTrace);
    } on MissingPluginException {
      AppLogger.warning('Adblock channel not ready.');
    }
  }
}
