import 'package:flutter/services.dart';

import '../logging/app_logger.dart';
import '../models/vpn_protocol.dart';

const String openVpnRuntimeNotLinkedErrorCode = 'OPENVPN_RUNTIME_NOT_LINKED';

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

class ProtocolCapability {
  const ProtocolCapability({
    required this.supported,
    required this.runtimeAvailable,
    this.reason,
  });

  final bool supported;
  final bool runtimeAvailable;
  final String? reason;

  bool get available => supported && runtimeAvailable;

  factory ProtocolCapability.fromMap(Map<dynamic, dynamic> raw) {
    bool parseBool(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      return (value?.toString() ?? '').trim().toLowerCase() == 'true';
    }

    final reason = raw['reason']?.toString().trim();
    return ProtocolCapability(
      supported: parseBool(raw['supported']),
      runtimeAvailable: parseBool(raw['runtimeAvailable']),
      reason: reason == null || reason.isEmpty ? null : reason,
    );
  }
}

class VpnPlatformBridgeStatus {
  const VpnPlatformBridgeStatus({
    required this.state,
    this.lastError,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.connectedSince,
    this.protocol,
    this.interfaceName,
  });

  final VpnPlatformBridgeState state;
  final String? lastError;
  final int rxBytes;
  final int txBytes;
  final DateTime? connectedSince;
  final String? protocol;
  final String? interfaceName;

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
      protocol: parseString(raw['protocol']),
      interfaceName: parseString(raw['interface']),
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
    required this.personalVpnReady,
    required this.wireGuardCapability,
    required this.openVpnCapability,
    required this.ikev2Capability,
    required this.openVpnRuntimeLinked,
    this.appGroupIdentifier,
    this.providerBundleIdentifier,
    this.activeProtocol,
    this.configuredProtocol,
    this.openVpnInstallHint,
    this.lastError,
  });

  final bool available;
  final bool extensionEmbedded;
  final bool appGroupConfigured;
  final bool tunnelManagerReady;
  final bool personalVpnReady;
  final ProtocolCapability wireGuardCapability;
  final ProtocolCapability openVpnCapability;
  final ProtocolCapability ikev2Capability;
  final bool openVpnRuntimeLinked;
  final String? appGroupIdentifier;
  final String? providerBundleIdentifier;
  final String? activeProtocol;
  final String? configuredProtocol;
  final String? openVpnInstallHint;
  final String? lastError;

  bool get wireGuardSupported => wireGuardCapability.supported;
  bool get openVpnSupported => openVpnCapability.supported;
  bool get ikev2Supported => ikev2Capability.supported;
  bool get wireGuardRuntimeAvailable => wireGuardCapability.runtimeAvailable;
  bool get openVpnRuntimeAvailable => openVpnCapability.runtimeAvailable;
  bool get ikev2RuntimeAvailable => ikev2Capability.runtimeAvailable;

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

    bool protocolFlag(
      String key, {
      required Map<dynamic, dynamic> protocols,
    }) {
      if (protocols.containsKey(key)) {
        return parseBool(protocols[key]);
      }
      return parseBool(raw[key]);
    }

    final rawProtocols = raw['supportedProtocols'] ?? raw['protocols'];
    final protocols =
        rawProtocols is Map ? rawProtocols : const <Object, Object>{};
    final rawProtocolCapabilities = raw['protocolCapabilities'];
    final protocolCapabilities = rawProtocolCapabilities is Map
        ? rawProtocolCapabilities
        : const <Object, Object>{};

    ProtocolCapability parseCapability(String key) {
      final rawCapability = protocolCapabilities[key];
      if (rawCapability is Map) {
        return ProtocolCapability.fromMap(rawCapability);
      }

      final supported = protocolFlag(key, protocols: protocols);
      final runtimeAvailable = switch (key) {
        'openvpn' => supported && parseBool(raw['openVpnRuntimeLinked']),
        _ => supported,
      };
      final reason = runtimeAvailable
          ? null
          : key == 'openvpn'
              ? (parseString(raw['openVpnInstallHint']) ??
                  parseString(raw['lastError']))
              : parseString(raw['lastError']);
      return ProtocolCapability(
        supported: supported,
        runtimeAvailable: runtimeAvailable,
        reason: reason,
      );
    }

    return VpnPlatformBridgeDiagnostics(
      available: parseBool(raw['available']),
      extensionEmbedded: parseBool(raw['extensionEmbedded']),
      appGroupConfigured: parseBool(raw['appGroupConfigured']),
      tunnelManagerReady: parseBool(raw['tunnelManagerReady']),
      personalVpnReady: parseBool(raw['personalVpnReady']),
      wireGuardCapability: parseCapability('wireguard'),
      openVpnCapability: parseCapability('openvpn'),
      ikev2Capability: parseCapability('ikev2'),
      openVpnRuntimeLinked: parseBool(raw['openVpnRuntimeLinked']),
      appGroupIdentifier: parseString(raw['appGroupIdentifier']),
      providerBundleIdentifier: parseString(raw['providerBundleIdentifier']),
      activeProtocol: parseString(raw['activeProtocol']),
      configuredProtocol: parseString(raw['configuredProtocol']),
      openVpnInstallHint: parseString(raw['openVpnInstallHint']),
      lastError: parseString(raw['lastError']),
    );
  }
}

class VpnPlatformBridge {
  VpnPlatformBridge({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('securewave/vpn_platform_bridge');

  final MethodChannel _channel;

  Future<void> connect({
    required VpnProtocol protocol,
    required Map<String, Object?> profile,
  }) async {
    if (protocol == VpnProtocol.openVpn) {
      final diagnostics = await this.diagnostics();
      final capability = diagnostics.openVpnCapability;
      if (!capability.available) {
        final code = capability.supported && !capability.runtimeAvailable
            ? openVpnRuntimeNotLinkedErrorCode
            : 'protocol_unavailable';
        final message = capability.reason ??
            diagnostics.openVpnInstallHint ??
            'OpenVPN runtime is not available on this Apple build.';
        AppLogger.vpn(
          'APPLE_BRIDGE',
          'OPENVPN_CONNECT_BLOCKED',
          level: 900,
          fields: <String, Object?>{
            'code': code,
            'supported': capability.supported,
            'runtime_available': capability.runtimeAvailable,
            'active_protocol': diagnostics.activeProtocol,
            'configured_protocol': diagnostics.configuredProtocol,
          },
        );
        throw PlatformException(
          code: code,
          message: message,
          details: <String, Object?>{
            'supported': capability.supported,
            'runtime_available': capability.runtimeAvailable,
            if (capability.reason != null) 'reason': capability.reason,
          },
        );
      }
    }
    await _channel.invokeMethod<void>('connect', <String, Object?>{
      'protocol': vpnProtocolStorageValue(protocol),
      ...profile,
    });
  }

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
    bool usePacketTunnelFallback = false,
  }) async {
    await connect(
      protocol: VpnProtocol.wireGuard,
      profile: <String, Object?>{
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
        'usePacketTunnelFallback': usePacketTunnelFallback,
      },
    );
  }

  Future<void> stopVPN() async {
    await _channel.invokeMethod<void>('stopVPN');
  }

  Future<void> disconnect() async {
    await stopVPN();
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
      personalVpnReady: false,
      wireGuardCapability: ProtocolCapability(
        supported: false,
        runtimeAvailable: false,
      ),
      openVpnCapability: ProtocolCapability(
        supported: false,
        runtimeAvailable: false,
      ),
      ikev2Capability: ProtocolCapability(
        supported: false,
        runtimeAvailable: false,
      ),
      openVpnRuntimeLinked: false,
    );
  }
}
