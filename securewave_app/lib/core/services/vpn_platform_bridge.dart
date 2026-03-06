import 'package:flutter/services.dart';

enum VpnPlatformBridgeState {
  disconnected,
  connecting,
  disconnecting,
  connected,
  error,
  unavailable,
}

VpnPlatformBridgeState _bridgeStateFromRaw(Object? raw) {
  switch ((raw?.toString() ?? '').trim().toLowerCase()) {
    case 'connected':
      return VpnPlatformBridgeState.connected;
    case 'connecting':
      return VpnPlatformBridgeState.connecting;
    case 'disconnecting':
      return VpnPlatformBridgeState.disconnecting;
    case 'error':
      return VpnPlatformBridgeState.error;
    case 'unavailable':
      return VpnPlatformBridgeState.unavailable;
    default:
      return VpnPlatformBridgeState.disconnected;
  }
}

class VpnPlatformBridgeStatus {
  const VpnPlatformBridgeStatus({
    required this.state,
    this.lastError,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.connectedSince,
  });

  final VpnPlatformBridgeState state;
  final String? lastError;
  final int rxBytes;
  final int txBytes;
  final DateTime? connectedSince;

  bool get isConnected => state == VpnPlatformBridgeState.connected;

  factory VpnPlatformBridgeStatus.fromMap(Map<dynamic, dynamic> raw) {
    int parseInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    String? parseString(Object? value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text;
    }

    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      if (value is int) {
        final millis = value < 100000000000 ? value * 1000 : value;
        return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
            .toLocal();
      }
      if (value is num) {
        final intValue = value.toInt();
        final millis = intValue < 100000000000 ? intValue * 1000 : intValue;
        return DateTime.fromMillisecondsSinceEpoch(
          millis,
          isUtc: true,
        ).toLocal();
      }
      return DateTime.tryParse(value.toString())?.toLocal();
    }

    return VpnPlatformBridgeStatus(
      state: _bridgeStateFromRaw(raw['state']),
      lastError: parseString(raw['lastError']),
      rxBytes: parseInt(raw['rxBytes']),
      txBytes: parseInt(raw['txBytes']),
      connectedSince: parseDate(raw['connectedSince']),
    );
  }
}

typedef VpnNativeTunnelStatus = VpnPlatformBridgeStatus;

class VpnPlatformBridgeDiagnostics {
  const VpnPlatformBridgeDiagnostics({
    required this.available,
    required this.extensionEmbedded,
    required this.appGroupConfigured,
    required this.tunnelManagerReady,
    this.appGroupIdentifier,
    this.providerBundleIdentifier,
    this.lastError,
  });

  final bool available;
  final bool extensionEmbedded;
  final bool appGroupConfigured;
  final bool tunnelManagerReady;
  final String? appGroupIdentifier;
  final String? providerBundleIdentifier;
  final String? lastError;

  factory VpnPlatformBridgeDiagnostics.fromMap(Map<dynamic, dynamic> raw) {
    bool parseBool(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      return (value?.toString() ?? '').trim().toLowerCase() == 'true';
    }

    String? parseString(Object? value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text;
    }

    return VpnPlatformBridgeDiagnostics(
      available: parseBool(raw['available']),
      extensionEmbedded: parseBool(raw['extensionEmbedded']),
      appGroupConfigured: parseBool(raw['appGroupConfigured']),
      tunnelManagerReady: parseBool(raw['tunnelManagerReady']),
      appGroupIdentifier: parseString(raw['appGroupIdentifier']),
      providerBundleIdentifier: parseString(raw['providerBundleIdentifier']),
      lastError: parseString(raw['lastError']),
    );
  }
}

class VpnPlatformBridge {
  VpnPlatformBridge({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('securewave/vpn_platform_bridge');

  final MethodChannel _channel;

  Future<void> connectWireGuard({
    required String serverId,
    required String endpointHost,
    required int endpointPort,
    required String clientPrivateKey,
    required String addressCidr,
    required List<String> dns,
    required List<String> allowedIps,
    required int keepaliveSeconds,
    String? presharedKey,
    required String serverPublicKey,
  }) async {
    await _channel.invokeMethod<void>('connectWireGuard', <String, Object?>{
      'serverId': serverId,
      'endpointHost': endpointHost,
      'endpointPort': endpointPort,
      'clientPrivateKey': clientPrivateKey,
      'addressCidr': addressCidr,
      'dns': dns,
      'allowedIps': allowedIps,
      'keepaliveSeconds': keepaliveSeconds,
      'presharedKey': presharedKey,
      'serverPublicKey': serverPublicKey,
    });
  }

  Future<void> disconnect() async {
    await _channel.invokeMethod<void>('disconnect');
  }

  Future<VpnPlatformBridgeStatus> status() async {
    final raw = await _channel.invokeMethod<dynamic>('status');
    if (raw is Map) {
      return VpnPlatformBridgeStatus.fromMap(raw);
    }
    return const VpnPlatformBridgeStatus(
      state: VpnPlatformBridgeState.disconnected,
    );
  }

  Future<bool> isAvailable() async {
    final raw = await _channel.invokeMethod<dynamic>('isAvailable');
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    return (raw?.toString() ?? '').trim().toLowerCase() == 'true';
  }

  Future<VpnPlatformBridgeDiagnostics> diagnostics() async {
    final raw = await _channel.invokeMethod<dynamic>('diagnostics');
    if (raw is Map) {
      return VpnPlatformBridgeDiagnostics.fromMap(raw);
    }
    return const VpnPlatformBridgeDiagnostics(
      available: false,
      extensionEmbedded: false,
      appGroupConfigured: false,
      tunnelManagerReady: false,
    );
  }
}
