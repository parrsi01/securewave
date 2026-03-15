import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform_info/platform_info.dart';

import '../config/app_config.dart';
import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../logging/app_logger.dart';
import 'vpn_platform_bridge.dart';
import '../vpn/wireguard_native_config.dart';
import '../vpn/wireguard_linux_runtime_config.dart';

abstract class VpnService {
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, Map<String, dynamic>? profile});
  Future<VpnStatus> disconnect();
  VpnStatus getStatus();
  bool get isNativeAvailable;
  String? get availabilityMessage;
  Future<VpnCapabilities> getCapabilities();
}

class VpnServiceException implements Exception {
  VpnServiceException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'VpnServiceException($code): $message';
}

class VpnCapabilities {
  const VpnCapabilities({
    required this.wireGuard,
    required this.openVpn,
    required this.ikev2,
    this.windowsThreadSafe = false,
    this.androidVpnServiceBased = false,
    this.macosEntitlementReady = false,
    this.linuxWireGuardInstalled = true,
    this.linuxElevationAvailable = true,
    this.wireGuardInstallHint,
    this.openVpnInstallHint,
    this.ikev2InstallHint,
    this.linuxElevationHint,
    this.macosEntitlementWarning,
  });

  final bool wireGuard;
  final bool openVpn;
  final bool ikev2;

  final bool windowsThreadSafe;
  final bool androidVpnServiceBased;
  final bool macosEntitlementReady;
  final bool linuxWireGuardInstalled;
  final bool linuxElevationAvailable;

  final String? wireGuardInstallHint;
  final String? openVpnInstallHint;
  final String? ikev2InstallHint;
  final String? linuxElevationHint;
  final String? macosEntitlementWarning;

  bool supportsProtocol(VpnProtocol protocol) {
    switch (protocol) {
      case VpnProtocol.auto:
        return false;
      case VpnProtocol.wireGuard:
        return wireGuard;
      case VpnProtocol.openVpn:
        return openVpn;
      case VpnProtocol.ikev2:
        return ikev2;
    }
  }

  static const VpnCapabilities none = VpnCapabilities(
    wireGuard: false,
    openVpn: false,
    ikev2: false,
    windowsThreadSafe: false,
    androidVpnServiceBased: false,
    macosEntitlementReady: false,
    linuxWireGuardInstalled: false,
    linuxElevationAvailable: false,
  );
}

class VpnTrafficStats {
  const VpnTrafficStats({
    required this.connected,
    required this.rxBytes,
    required this.txBytes,
    this.interfaceName,
    this.protocol,
    this.timestampMs,
  });

  final bool connected;
  final int rxBytes;
  final int txBytes;
  final String? interfaceName;
  final String? protocol;
  final int? timestampMs;
}

class VpnRuntimeSnapshot {
  const VpnRuntimeSnapshot({
    required this.nativeStatus,
    required this.hasNativeTrafficStats,
    required this.sampleAvailable,
    required this.trafficConnected,
    required this.interfaceCompatible,
    required this.reportedProtocol,
    required this.rxBytes,
    required this.txBytes,
    this.interfaceName,
    this.timestampMs,
  });

  final VpnStatus nativeStatus;
  final bool hasNativeTrafficStats;
  final bool sampleAvailable;
  final bool trafficConnected;
  final bool interfaceCompatible;
  final VpnProtocol reportedProtocol;
  final int rxBytes;
  final int txBytes;
  final String? interfaceName;
  final int? timestampMs;
}

class ChannelVpnService implements VpnService {
  static final bool _simulationEnabled = const String.fromEnvironment(
        'SECUREWAVE_SIM_MODE',
        defaultValue: 'false',
      ).toLowerCase() ==
      'true';

  ChannelVpnService({
    Duration capabilitiesCacheTtl = const Duration(seconds: 3),
    Duration availabilityCacheTtl = const Duration(seconds: 2),
    DateTime Function()? clock,
  })  : _capabilitiesCacheTtl = capabilitiesCacheTtl,
        _availabilityCacheTtl = availabilityCacheTtl,
        _clock = clock ?? DateTime.now {
    _nativeAvailable = false;
    unawaited(
      _refreshNativeAvailability().catchError((Object error, StackTrace stack) {
        AppLogger.warning('Initial VPN availability refresh failed: $error');
        AppLogger.error(
          'Initial VPN availability refresh failed',
          error: error,
          stackTrace: stack,
        );
        return false;
      }),
    );
  }

  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  final VpnPlatformBridge _platformBridge = VpnPlatformBridge();
  final Duration _capabilitiesCacheTtl;
  final Duration _availabilityCacheTtl;
  final DateTime Function() _clock;
  VpnStatus _status = VpnStatus.disconnected;
  bool _nativeAvailable = false;
  String? _lastNativeAvailabilityMessage;
  VpnCapabilities? _cachedCapabilities;
  DateTime? _capabilitiesCachedAt;
  DateTime? _nativeAvailabilityCheckedAt;
  int _simRxBytes = 0;
  int _simTxBytes = 0;
  DateTime? _simLastTick;
  VpnProtocol? _simProtocol;

  @override
  bool get isNativeAvailable => _nativeAvailable;

  @override
  String? get availabilityMessage => _lastNativeAvailabilityMessage;

  bool get usesApplePlatformBridge => _usesAppleBridge();

  /// Whether this platform has a native `getTrafficStats` implementation.
  /// Linux/Android/iOS/macOS provide native stats in this client build.
  bool get hasNativeTrafficStats {
    if (_simulationEnabled) return true;
    if (_usesAppleBridge()) return true;
    if (!_supportsNativeChannel()) return false;
    final os = platform.operatingSystem.name.toLowerCase();
    return os == 'linux' || os == 'android' || os == 'ios' || os == 'macos';
  }

  Future<VpnTrafficStats?> fetchTrafficStats() async {
    if (_simulationEnabled) {
      _advanceSimTraffic();
      return VpnTrafficStats(
        connected: _status == VpnStatus.connected,
        rxBytes: _simRxBytes,
        txBytes: _simTxBytes,
        interfaceName: 'sim0',
        protocol: _simProtocol == null
            ? null
            : vpnProtocolStorageValue(_simProtocol!),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      );
    }
    if (!_supportsNativeChannel()) return null;
    try {
      if (_usesAppleBridge()) {
        final native = await _platformBridge.status();
        return VpnTrafficStats(
          connected: native.isConnected,
          rxBytes: native.rxBytes,
          txBytes: native.txBytes,
          interfaceName: native.isConnected ? 'utun' : null,
          protocol: vpnProtocolStorageValue(VpnProtocol.wireGuard),
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
      final raw = await _channel
          .invokeMethod<dynamic>('getTrafficStats')
          .timeout(const Duration(seconds: 2));
      if (raw is! Map) return null;
      final data = Map<String, dynamic>.from(raw);
      bool b(String key) {
        final value = data[key];
        if (value is bool) return value;
        if (value is num) return value != 0;
        return value?.toString().toLowerCase() == 'true';
      }

      int i(String key) {
        final value = data[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        return int.tryParse(value?.toString() ?? '') ?? 0;
      }

      String? s(String key) {
        final text = data[key]?.toString().trim();
        if (text == null || text.isEmpty) return null;
        return text;
      }

      final timestamp = data['timestamp_ms'];
      final timestampMs = switch (timestamp) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
      return VpnTrafficStats(
        connected: b('connected'),
        rxBytes: i('rx_bytes'),
        txBytes: i('tx_bytes'),
        interfaceName: s('interface'),
        protocol: s('protocol'),
        timestampMs: timestampMs,
      );
    } on TimeoutException {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  bool _interfaceLooksCompatible(String? interfaceName, VpnProtocol protocol) {
    final iface = interfaceName?.trim().toLowerCase();
    if (iface == null || iface.isEmpty) return false;
    switch (protocol) {
      case VpnProtocol.auto:
        return false;
      case VpnProtocol.wireGuard:
        return iface == 'sw-wg' || iface.startsWith('wg');
      case VpnProtocol.openVpn:
        return iface.startsWith('tun');
      case VpnProtocol.ikev2:
        return iface.startsWith('ipsec') || iface.startsWith('ppp');
    }
  }

  Future<bool> _hasMatchingConnectedTunnel(VpnProtocol protocol) async {
    if (!hasNativeTrafficStats) return true;
    final stats = await fetchTrafficStats();
    if (stats == null || !stats.connected) return false;
    final reportedProtocol = vpnProtocolFromStorage(stats.protocol);
    if (reportedProtocol != VpnProtocol.auto) {
      return reportedProtocol == protocol;
    }
    return _interfaceLooksCompatible(stats.interfaceName, protocol);
  }

  Future<String> _protocolMismatchMessage(VpnProtocol protocol) async {
    final stats = await fetchTrafficStats();
    final actualProtocol = stats?.protocol?.trim();
    final actualInterface = stats?.interfaceName?.trim();
    final actual = [
      if (actualProtocol != null && actualProtocol.isNotEmpty) actualProtocol,
      if (actualInterface != null && actualInterface.isNotEmpty)
        'interface $actualInterface',
    ].join(' / ');
    final requested = vpnProtocolLabel(protocol);
    if (actual.isEmpty) {
      return 'A different VPN tunnel is active and did not match the '
          'requested $requested session. Disconnect the stale tunnel and retry.';
    }
    return 'A different VPN tunnel is active ($actual). '
        'Disconnect it and retry $requested.';
  }

  bool _usesAppleBridge() {
    final os = platform.operatingSystem.name.toLowerCase();
    return os == 'ios' || os == 'macos';
  }

  VpnStatus _mapBridgeState(VpnPlatformBridgeState state) {
    return switch (state) {
      VpnPlatformBridgeState.connected => VpnStatus.connected,
      VpnPlatformBridgeState.connecting => VpnStatus.connecting,
      VpnPlatformBridgeState.disconnecting => VpnStatus.disconnecting,
      VpnPlatformBridgeState.error => VpnStatus.error,
      VpnPlatformBridgeState.disconnected ||
      VpnPlatformBridgeState.unavailable =>
        VpnStatus.disconnected,
    };
  }

  Future<VpnNativeTunnelStatus> _waitForBridgeState({
    required Set<VpnPlatformBridgeState> terminalStates,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final deadline = _clock().add(timeout);
    while (_clock().isBefore(deadline)) {
      final status = await _platformBridge.status();
      if (terminalStates.contains(status.state)) {
        return status;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    throw TimeoutException('Timed out waiting for Apple VPN bridge.');
  }

  /// Best-effort sync of tunnel status from the native layer.
  ///
  /// This is primarily used to avoid "stuck disconnected" states after an app
  /// restart when a tunnel/service may still be running.
  Future<VpnStatus> refreshStatus() async {
    if (!_supportsNativeChannel()) {
      _status = VpnStatus.disconnected;
      return _status;
    }
    try {
      if (_usesAppleBridge()) {
        final native = await _platformBridge.status();
        _status = _mapBridgeState(native.state);
        return _status;
      }
      final raw = await _channel.invokeMethod<String>('getStatus');
      final normalized = (raw ?? '').toLowerCase().trim();
      if (normalized == 'connected') {
        _status = VpnStatus.connected;
      } else if (normalized == 'connecting') {
        _status = VpnStatus.connecting;
      } else if (normalized == 'disconnecting') {
        _status = VpnStatus.disconnecting;
      } else if (normalized == 'error') {
        _status = VpnStatus.error;
      } else if (normalized == 'disconnected') {
        _status = VpnStatus.disconnected;
      }
    } on MissingPluginException {
      // No native implementation for this platform/build.
    } on PlatformException catch (error) {
      AppLogger.warning('Native VPN status check failed: ${error.code}');
    } catch (error, stackTrace) {
      AppLogger.warning('Native VPN status check failed unexpectedly');
      AppLogger.error(
        'Native VPN status check failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return _status;
  }

  Future<VpnRuntimeSnapshot> fetchRuntimeSnapshot({
    required VpnProtocol expectedProtocol,
  }) async {
    final nativeStatus = await refreshStatus();
    final stats = await fetchTrafficStats();
    final reportedProtocol = vpnProtocolFromStorage(stats?.protocol);
    var interfaceCompatible = true;

    if (stats != null && expectedProtocol != VpnProtocol.auto) {
      if (reportedProtocol != VpnProtocol.auto) {
        interfaceCompatible = reportedProtocol == expectedProtocol;
      } else if ((stats.interfaceName?.trim().isNotEmpty ?? false)) {
        interfaceCompatible =
            _interfaceLooksCompatible(stats.interfaceName, expectedProtocol);
      } else if (stats.connected || nativeStatus == VpnStatus.connected) {
        interfaceCompatible = false;
      }
    }

    return VpnRuntimeSnapshot(
      nativeStatus: nativeStatus,
      hasNativeTrafficStats: hasNativeTrafficStats,
      sampleAvailable: stats != null,
      trafficConnected: stats?.connected ?? false,
      interfaceCompatible: interfaceCompatible,
      reportedProtocol: reportedProtocol,
      rxBytes: stats?.rxBytes ?? 0,
      txBytes: stats?.txBytes ?? 0,
      interfaceName: stats?.interfaceName,
      timestampMs: stats?.timestampMs,
    );
  }

  @override
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, Map<String, dynamic>? profile}) async {
    if (_status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      if (protocol == VpnProtocol.auto) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'protocol_unresolved',
          'VPN protocol was not resolved. Select a concrete protocol and retry.',
        );
      }
      if (!_simulationEnabled && _supportsNativeChannel()) {
        final synced = await refreshStatus();
        if (synced == VpnStatus.connected &&
            await _hasMatchingConnectedTunnel(protocol)) {
          return _status;
        }
        _status = VpnStatus.disconnected;
      }
      _status = VpnStatus.connecting;
      final capabilities = await getCapabilities();
      if (!capabilities.supportsProtocol(protocol)) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'protocol_unavailable',
          _protocolUnavailableMessage(protocol, capabilities),
        );
      }
      final available = await _refreshNativeAvailability();
      if (!available) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'vpn_unavailable',
          _lastNativeAvailabilityMessage ??
              _protocolUnavailableMessage(protocol, capabilities),
        );
      }
      final payload = profile ?? const <String, dynamic>{};
      if (payload.isEmpty) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'invalid_profile',
          'Missing VPN profile. Please refresh and try again.',
        );
      }
      final preparedPayload = Map<String, dynamic>.from(payload);
      if (protocol == VpnProtocol.wireGuard &&
          !_usesAppleBridge() &&
          platform.operatingSystem.name.toLowerCase() == 'linux') {
        final rawConfig =
            (preparedPayload['wireguard_config']?.toString() ?? '').trim();
        if (rawConfig.isNotEmpty) {
          final config = await AppConfig.load();
          preparedPayload['wireguard_config'] =
              buildLinuxWireGuardRuntimeConfig(
            rawConfig,
            apiBaseUrl: config.apiBaseUrl,
          );
        }
      }
      AppLogger.vpn(
        'TUNNEL',
        'STARTING',
        fields: <String, Object?>{
          'protocol': vpnProtocolStorageValue(protocol),
          'server_id': preparedPayload['server_id'] ?? '-',
          'platform': platform.operatingSystem.name.toLowerCase(),
        },
      );
      if (_simulationEnabled) {
        _simProtocol = protocol;
        _simRxBytes = 0;
        _simTxBytes = 0;
        _simLastTick = _clock();
        _status = VpnStatus.connected;
        AppLogger.vpn(
          'TUNNEL',
          'ACTIVE',
          fields: <String, Object?>{
            'protocol': vpnProtocolStorageValue(protocol),
            'mode': 'simulation',
          },
        );
        return _status;
      }
      if (_usesAppleBridge()) {
        if (protocol != VpnProtocol.wireGuard) {
          _status = VpnStatus.disconnected;
          throw VpnServiceException(
            'protocol_unavailable',
            'Apple Network Extension bridge currently supports WireGuard only.',
          );
        }
        final request = (() {
          try {
            return WireGuardNativeConfig.fromProfilePayload(preparedPayload);
          } on StateError catch (error) {
            throw VpnServiceException('invalid_profile', error.message);
          }
        })();
        await _platformBridge.connectWireGuard(
          serverId: request.serverId,
          endpointHost: request.endpointHost,
          endpointPort: request.endpointPort,
          clientPrivateKey: request.clientPrivateKey,
          addressCidr: request.addressCidr,
          dns: request.dns,
          allowedIps: request.allowedIps,
          keepaliveSeconds: request.keepaliveSeconds,
          presharedKey: request.presharedKey,
          serverPublicKey: request.serverPublicKey,
        );
        final native = await _waitForBridgeState(
          terminalStates: const <VpnPlatformBridgeState>{
            VpnPlatformBridgeState.connected,
            VpnPlatformBridgeState.disconnected,
            VpnPlatformBridgeState.error,
            VpnPlatformBridgeState.unavailable,
          },
        );
        _status = _mapBridgeState(native.state);
        if (native.state != VpnPlatformBridgeState.connected) {
          throw VpnServiceException(
            native.state == VpnPlatformBridgeState.error
                ? 'vpn_connect_failed'
                : 'connect_incomplete',
            native.lastError ??
                'Apple Network Extension tunnel did not connect.',
          );
        }
        AppLogger.vpn(
          'TUNNEL',
          'ACTIVE',
          fields: <String, Object?>{
            'protocol': vpnProtocolStorageValue(protocol),
            'platform': platform.operatingSystem.name.toLowerCase(),
          },
        );
        return _status;
      }
      await _channel.invokeMethod('connect', {
        'protocol': vpnProtocolStorageValue(protocol),
        'profile': preparedPayload,
        if (protocol == VpnProtocol.wireGuard &&
            (preparedPayload['wireguard_config']?.toString() ?? '')
                .trim()
                .isNotEmpty)
          'config': preparedPayload['wireguard_config']?.toString(),
      }).timeout(const Duration(seconds: 30));
      if (platform.operatingSystem.name.toLowerCase() == 'linux') {
        final nativeStatus = await _channel
            .invokeMethod<String>('getStatus')
            .timeout(const Duration(seconds: 3));
        if ((nativeStatus ?? '').toLowerCase().trim() != 'connected') {
          _status = VpnStatus.disconnected;
          throw VpnServiceException(
            'vpn_connect_failed',
            'Native VPN runtime did not report an active tunnel after connect.',
          );
        }
        if (!await _hasMatchingConnectedTunnel(protocol)) {
          _status = VpnStatus.disconnected;
          throw VpnServiceException(
            'vpn_connect_protocol_mismatch',
            await _protocolMismatchMessage(protocol),
          );
        }
      }
      _status = VpnStatus.connected;
      AppLogger.vpn(
        'TUNNEL',
        'ACTIVE',
        fields: <String, Object?>{
          'protocol': vpnProtocolStorageValue(protocol),
          'platform': platform.operatingSystem.name.toLowerCase(),
        },
      );
    } on TimeoutException {
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        'vpn_timeout',
        'Native VPN operation timed out. Please retry.',
      );
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        _nativeAvailabilityCheckedAt = _clock();
        _invalidateCapabilitiesCache();
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          error.code,
          error.message ??
              _defaultUnavailableMessage(
                  platform.operatingSystem.name.toLowerCase()),
          details: error.details,
        );
      } else {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          error.code,
          error.message ?? 'Unable to start VPN tunnel.',
          details: error.details,
        );
      }
    } on MissingPluginException {
      _nativeAvailable = false;
      _nativeAvailabilityCheckedAt = _clock();
      _invalidateCapabilitiesCache();
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        'vpn_unavailable',
        'Native VPN plugin missing for this platform/build. '
            'Reinstall the app and retry.',
      );
    }
    return _status;
  }

  @override
  Future<VpnCapabilities> getCapabilities() async {
    if (_simulationEnabled) {
      const simulated = VpnCapabilities(
        wireGuard: true,
        openVpn: true,
        ikev2: true,
        windowsThreadSafe: true,
        androidVpnServiceBased: true,
        macosEntitlementReady: true,
        linuxWireGuardInstalled: true,
        linuxElevationAvailable: true,
      );
      _cacheCapabilities(simulated);
      return simulated;
    }
    final cached = _cachedCapabilities;
    if (cached != null &&
        _isCacheFresh(_capabilitiesCachedAt, _capabilitiesCacheTtl)) {
      return cached;
    }
    if (!_supportsNativeChannel()) return VpnCapabilities.none;
    final os = platform.operatingSystem.name.toLowerCase();
    if (_usesAppleBridge()) {
      final diagnostics = await fetchPlatformDiagnostics();
      final available = diagnostics?.available ?? false;
      final warning = diagnostics?.lastError ?? _defaultUnavailableMessage(os);
      final capabilities = VpnCapabilities(
        wireGuard: available,
        openVpn: false,
        ikev2: false,
        windowsThreadSafe: false,
        androidVpnServiceBased: false,
        macosEntitlementReady: os != 'macos' || available,
        linuxWireGuardInstalled: true,
        linuxElevationAvailable: true,
        wireGuardInstallHint: available ? null : warning,
        macosEntitlementWarning: os == 'macos' && !available ? warning : null,
      );
      _cacheCapabilities(capabilities);
      return capabilities;
    }
    try {
      final raw = await _channel
          .invokeMethod<dynamic>('getCapabilities')
          .timeout(const Duration(seconds: 2));
      if (raw is Map) {
        final data = Map<String, dynamic>.from(raw);
        bool b(String key) {
          final value = data[key];
          if (value == null) return false;
          if (value is bool) return value;
          if (value is num) return value != 0;
          return value.toString().toLowerCase() == 'true';
        }

        String? s(String key) {
          final value = data[key];
          final text = value?.toString();
          if (text == null || text.trim().isEmpty) return null;
          return text.trim();
        }

        final capabilities = VpnCapabilities(
          wireGuard: b('wireguard'),
          openVpn: b('openvpn'),
          ikev2: b('ikev2'),
          windowsThreadSafe: b('windows_thread_safe'),
          androidVpnServiceBased: b('android_vpnservice_based'),
          macosEntitlementReady: b('macos_entitlements_ready'),
          linuxWireGuardInstalled: os != 'linux' || b('linux_wg_installed'),
          linuxElevationAvailable:
              os != 'linux' || b('linux_elevation_available'),
          wireGuardInstallHint: s('wireguard_install_hint'),
          openVpnInstallHint: s('openvpn_install_hint'),
          ikev2InstallHint: s('ikev2_install_hint'),
          linuxElevationHint: s('linux_elevation_hint'),
          macosEntitlementWarning: s('macos_entitlement_warning'),
        );
        _cacheCapabilities(capabilities);
        return capabilities;
      }
    } on TimeoutException {
      // Fall back below.
    } on MissingPluginException {
      // Fall back below.
    } on PlatformException {
      // Fall back below.
    }

    final wgAvailable = await _refreshNativeAvailability();
    final linuxInstallHint =
        os == 'linux' && !wgAvailable ? _linuxInstallGuide() : null;
    final macosWarning =
        os == 'macos' && !wgAvailable ? _macosEntitlementWarning() : null;

    final fallbackCapabilities = VpnCapabilities(
      wireGuard: wgAvailable,
      openVpn: false,
      ikev2: false,
      windowsThreadSafe: os == 'windows',
      androidVpnServiceBased: os == 'android',
      macosEntitlementReady: os != 'macos' || wgAvailable,
      linuxWireGuardInstalled: os != 'linux' || wgAvailable,
      linuxElevationAvailable: os != 'linux' || wgAvailable,
      wireGuardInstallHint: linuxInstallHint,
      openVpnInstallHint: null,
      ikev2InstallHint: null,
      linuxElevationHint:
          os == 'linux' && !wgAvailable ? _linuxElevationGuide() : null,
      macosEntitlementWarning: macosWarning,
    );
    _cacheCapabilities(fallbackCapabilities);
    return fallbackCapabilities;
  }

  @override
  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.disconnecting;
    try {
      if (_simulationEnabled) {
        _advanceSimTraffic();
        _status = VpnStatus.disconnected;
        AppLogger.vpn(
          'TUNNEL',
          'DISCONNECTED',
          fields: const <String, Object?>{'mode': 'simulation'},
        );
        return _status;
      }
      final available = await _refreshNativeAvailability();
      if (!available) {
        _status = VpnStatus.disconnected;
        return _status;
      }
      if (_usesAppleBridge()) {
        await _platformBridge.disconnect();
        final native = await _waitForBridgeState(
          terminalStates: const <VpnPlatformBridgeState>{
            VpnPlatformBridgeState.disconnected,
            VpnPlatformBridgeState.error,
            VpnPlatformBridgeState.unavailable,
          },
          timeout: const Duration(seconds: 20),
        );
        _status = _mapBridgeState(native.state);
        if (_status == VpnStatus.error) {
          throw VpnServiceException(
            'vpn_disconnect_failed',
            native.lastError ??
                'Apple Network Extension tunnel failed to stop.',
          );
        }
        if (_status == VpnStatus.disconnected) {
          AppLogger.vpn(
            'TUNNEL',
            'DISCONNECTED',
            fields: <String, Object?>{
              'platform': platform.operatingSystem.name.toLowerCase(),
            },
          );
        }
        return _status;
      }
      await _channel
          .invokeMethod('disconnect')
          .timeout(const Duration(seconds: 20));
      _status = VpnStatus.disconnected;
      AppLogger.vpn(
        'TUNNEL',
        'DISCONNECTED',
        fields: <String, Object?>{
          'platform': platform.operatingSystem.name.toLowerCase(),
        },
      );
    } on TimeoutException {
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        'vpn_timeout',
        'Timed out while stopping the VPN tunnel.',
      );
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        _nativeAvailabilityCheckedAt = _clock();
        _invalidateCapabilitiesCache();
        _status = VpnStatus.disconnected;
      } else {
        throw VpnServiceException(
          error.code,
          error.message ?? 'Unable to stop VPN tunnel.',
          details: error.details,
        );
      }
    } on MissingPluginException {
      _nativeAvailable = false;
      _nativeAvailabilityCheckedAt = _clock();
      _invalidateCapabilitiesCache();
      _status = VpnStatus.disconnected;
    }
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;

  bool _supportsNativeChannel() {
    if (kIsWeb) return false;
    final os = platform.operatingSystem.name.toLowerCase();
    return os == 'android' ||
        os == 'ios' ||
        os == 'macos' ||
        os == 'windows' ||
        os == 'linux';
  }

  Future<bool> _refreshNativeAvailability({bool forceRefresh = false}) async {
    if (_simulationEnabled) {
      _nativeAvailable = true;
      _lastNativeAvailabilityMessage = null;
      _nativeAvailabilityCheckedAt = _clock();
      return true;
    }
    if (!forceRefresh &&
        _isCacheFresh(_nativeAvailabilityCheckedAt, _availabilityCacheTtl)) {
      return _nativeAvailable;
    }
    if (!_supportsNativeChannel()) {
      _nativeAvailable = false;
      _lastNativeAvailabilityMessage =
          'VPN is unavailable in this environment.';
      _nativeAvailabilityCheckedAt = _clock();
      return _nativeAvailable;
    }
    final os = platform.operatingSystem.name.toLowerCase();
    if (_usesAppleBridge()) {
      try {
        final available = await _platformBridge
            .isAvailable()
            .timeout(const Duration(seconds: 2));
        _nativeAvailable = available;
        if (_nativeAvailable) {
          _lastNativeAvailabilityMessage = null;
        } else {
          final diagnostics = await fetchPlatformDiagnostics();
          _lastNativeAvailabilityMessage =
              diagnostics?.lastError ?? _defaultUnavailableMessage(os);
        }
        _nativeAvailabilityCheckedAt = _clock();
        return _nativeAvailable;
      } on TimeoutException {
        _nativeAvailable = false;
        _lastNativeAvailabilityMessage =
            'VPN availability check timed out. Retry in a moment.';
        _nativeAvailabilityCheckedAt = _clock();
        return _nativeAvailable;
      } on MissingPluginException {
        _nativeAvailable = false;
        _lastNativeAvailabilityMessage =
            'Apple VPN bridge is missing for this platform/build.';
        _nativeAvailabilityCheckedAt = _clock();
        return _nativeAvailable;
      } on PlatformException catch (error) {
        _lastNativeAvailabilityMessage =
            error.message ?? _defaultUnavailableMessage(os);
        _nativeAvailable = false;
        _nativeAvailabilityCheckedAt = _clock();
        return _nativeAvailable;
      }
    }
    try {
      final available = await _channel
          .invokeMethod<bool>('isAvailable')
          .timeout(const Duration(seconds: 2));
      if (available != null) {
        _nativeAvailable = available;
      } else {
        _nativeAvailable = true;
      }
      if (_nativeAvailable) {
        _lastNativeAvailabilityMessage = null;
      } else {
        _lastNativeAvailabilityMessage = _defaultUnavailableMessage(os);
      }
      _nativeAvailabilityCheckedAt = _clock();
    } on TimeoutException {
      _nativeAvailable = false;
      _lastNativeAvailabilityMessage =
          'VPN availability check timed out. Retry in a moment.';
      _nativeAvailabilityCheckedAt = _clock();
    } on MissingPluginException {
      _nativeAvailable = false;
      _lastNativeAvailabilityMessage =
          'Native VPN plugin missing for this platform/build.';
      _nativeAvailabilityCheckedAt = _clock();
    } on PlatformException catch (error) {
      _lastNativeAvailabilityMessage =
          error.message ?? _defaultUnavailableMessage(os);
      _nativeAvailable = false;
      _nativeAvailabilityCheckedAt = _clock();
    }
    return _nativeAvailable;
  }

  bool _isCacheFresh(DateTime? cachedAt, Duration ttl) {
    if (cachedAt == null) return false;
    final age = _clock().difference(cachedAt);
    return age >= Duration.zero && age <= ttl;
  }

  void _cacheCapabilities(VpnCapabilities capabilities) {
    _cachedCapabilities = capabilities;
    _capabilitiesCachedAt = _clock();
  }

  void _invalidateCapabilitiesCache() {
    _cachedCapabilities = null;
    _capabilitiesCachedAt = null;
  }

  String _defaultUnavailableMessage(String os) {
    switch (os) {
      case 'linux':
        return _linuxInstallGuide();
      case 'windows':
        return 'No supported VPN runtime is currently available on this build.';
      case 'macos':
        return _macosEntitlementWarning();
      case 'android':
        return 'VPN runtime unavailable on this Android build. '
            'Ensure VpnService permissions are granted.';
      case 'ios':
        return 'VPN runtime unavailable on this iOS build. '
            'Check Network Extension entitlements and PacketTunnel embedding.';
      default:
        return 'Native VPN tunnel unavailable on this device.';
    }
  }

  String _linuxInstallGuide() {
    return 'WireGuard runtime is unavailable on Linux. '
        'Install wireguard-tools and retry:\n'
        '  Ubuntu/Debian: sudo apt-get install wireguard-tools\n'
        '  Fedora: sudo dnf install wireguard-tools\n'
        '  Arch: sudo pacman -S wireguard-tools';
  }

  String _linuxElevationGuide() {
    return 'Administrator elevation is unavailable on Linux. '
        'Install SecureWave helper/polkit setup (or PolicyKit pkexec with a '
        'desktop agent) to allow non-interactive tunnel resets.';
  }

  String _protocolUnavailableMessage(
    VpnProtocol protocol,
    VpnCapabilities capabilities,
  ) {
    if (protocol == VpnProtocol.wireGuard) {
      return capabilities.wireGuardInstallHint ??
          'WireGuard runtime is not available on this device.';
    }
    if (protocol == VpnProtocol.openVpn) {
      return capabilities.openVpnInstallHint ??
          'OpenVPN runtime is not available on this device.';
    }
    if (protocol == VpnProtocol.ikev2) {
      return capabilities.ikev2InstallHint ??
          'IKEv2/IPsec runtime is not available on this device.';
    }
    return '${vpnProtocolLabel(protocol)} is not available on this build. '
        'Select a different protocol or switch to Automatic.';
  }

  String _macosEntitlementWarning() {
    return 'macOS VPN requires Network Extension entitlements for Runner and '
        'PacketTunnel targets. This build is missing required entitlements.';
  }

  bool _isNativeUnavailableError(PlatformException error) {
    return error.code == 'vpn_not_configured' ||
        error.code == 'vpn_unavailable' ||
        error.code == 'vpn_permission_required' ||
        error.code == 'protocol_unavailable';
  }

  void _advanceSimTraffic() {
    if (_status != VpnStatus.connected) {
      _simLastTick = _clock();
      return;
    }
    final now = _clock();
    final last = _simLastTick ?? now;
    final elapsedMs = now.difference(last).inMilliseconds;
    if (elapsedMs <= 0) {
      _simLastTick = now;
      return;
    }
    _simLastTick = now;
    const rxRateBytesPerSec = 128 * 1024;
    const txRateBytesPerSec = 64 * 1024;
    _simRxBytes += ((rxRateBytesPerSec * elapsedMs) / 1000).round();
    _simTxBytes += ((txRateBytesPerSec * elapsedMs) / 1000).round();
  }

  Future<VpnNativeTunnelStatus?> fetchPlatformBridgeStatus() async {
    if (!_usesAppleBridge()) return null;
    try {
      return await _platformBridge.status();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<VpnPlatformBridgeDiagnostics?> fetchPlatformDiagnostics() async {
    if (!_usesAppleBridge()) return null;
    try {
      return await _platformBridge.diagnostics();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
