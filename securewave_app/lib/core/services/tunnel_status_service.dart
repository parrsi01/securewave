import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../models/tunnel_health_snapshot.dart';
import '../models/vpn_status.dart';

final tunnelStatusServiceProvider = Provider<TunnelStatusService>((ref) {
  return TunnelStatusService();
});

class TunnelStatusService {
  static const MethodChannel _channel =
      MethodChannel('securewave/tunnel_status');

  Future<TunnelHealthSnapshot> getStatus() async {
    try {
      final response =
          await _channel.invokeMapMethod<String, dynamic>('getTunnelStatus');
      if (response == null) {
        return TunnelHealthSnapshot.disconnected;
      }
      return TunnelHealthSnapshot(
        status: _parseStatus(response['status']?.toString()),
        interfaceName: response['interfaceName']?.toString(),
        interfaceOk: response['interfaceOk'] == true,
        routingOk: response['routingOk'] == true,
        details: response['details']?.toString(),
      );
    } on MissingPluginException {
      return TunnelHealthSnapshot.disconnected;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Tunnel status query failed',
        error: error,
        stackTrace: stackTrace,
        category: AppLogCategory.tunnel,
      );
      return TunnelHealthSnapshot.disconnected;
    }
  }

  VpnStatus _parseStatus(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'CONNECTING':
        return VpnStatus.connecting;
      case 'CONNECTED':
        return VpnStatus.connected;
      case 'DISCONNECTING':
        return VpnStatus.disconnecting;
      case 'RECONNECTING':
        return VpnStatus.reconnecting;
      case 'ERROR':
        return VpnStatus.error;
      case 'DISCONNECTED':
      default:
        return VpnStatus.disconnected;
    }
  }
}
