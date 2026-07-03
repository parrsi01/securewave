import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform_info/platform_info.dart';

import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../logging/app_logger.dart';

const ikev2ProductionDisabledMessage =
    'IKEv2 is disabled until SecureWave has live production proof for route, DNS, XFRM ESP, backend health, and cleanup.';

abstract class VpnService {
  Future<VpnStatus> connect({required VpnProtocol protocol, String? config});
  Future<VpnStatus> disconnect();
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol);
  VpnStatus getStatus();
  Future<VpnRuntimeStatus> refreshRuntimeStatus() async {
    return VpnRuntimeStatus(status: getStatus());
  }

  bool get isNativeAvailable;
  bool canConnectProtocol(VpnProtocol protocol);
  String? protocolUnavailableReason(VpnProtocol protocol);
}

class VpnRuntimeStatus {
  const VpnRuntimeStatus({
    required this.status,
    this.protocol,
  });

  final VpnStatus status;
  final VpnProtocol? protocol;

  factory VpnRuntimeStatus.fromJson(Map<Object?, Object?> json) {
    final status = switch (json['status']?.toString()) {
      'connected' => VpnStatus.connected,
      'connecting' => VpnStatus.connecting,
      'disconnecting' => VpnStatus.disconnecting,
      'error' => VpnStatus.error,
      _ => VpnStatus.disconnected,
    };
    final rawProtocol = json['protocol']?.toString();
    return VpnRuntimeStatus(
      status: status,
      protocol: rawProtocol == null || rawProtocol.isEmpty
          ? null
          : vpnProtocolFromStorage(rawProtocol),
    );
  }
}

class VpnTrafficStats {
  const VpnTrafficStats({
    required this.rxBytes,
    required this.txBytes,
    this.countersAvailable = true,
    this.interfaceName,
    this.unavailableReason,
  });

  final int rxBytes;
  final int txBytes;
  final bool countersAvailable;
  final String? interfaceName;
  final String? unavailableReason;

  int get totalBytes => rxBytes + txBytes;

  static const zero = VpnTrafficStats(rxBytes: 0, txBytes: 0);
  static const unavailable = VpnTrafficStats(
    rxBytes: 0,
    txBytes: 0,
    countersAvailable: false,
  );

  factory VpnTrafficStats.fromJson(Map<Object?, Object?> json) {
    int parse(Object? value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool parseBool(Object? value) {
      if (value is bool) return value;
      final normalized = value?.toString().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }

    final hasAvailability =
        json.containsKey('counters_available') || json.containsKey('available');
    final available = hasAvailability
        ? parseBool(json['counters_available'] ?? json['available'])
        : true;
    final interfaceName = json['interface']?.toString();
    final unavailableReason = json['unavailable_reason']?.toString();

    return VpnTrafficStats(
      rxBytes: parse(json['rx_bytes']),
      txBytes: parse(json['tx_bytes']),
      countersAvailable: available,
      interfaceName:
          interfaceName == null || interfaceName.isEmpty ? null : interfaceName,
      unavailableReason: unavailableReason == null || unavailableReason.isEmpty
          ? null
          : unavailableReason,
    );
  }
}

class VpnServiceException implements Exception {
  VpnServiceException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'VpnServiceException($code): $message';
}

class ChannelVpnService implements VpnService {
  ChannelVpnService({VpnService? fallback, bool allowFallback = false})
      : _fallback = fallback ?? MockVpnService(),
        _allowFallback = allowFallback {
    _nativeAvailable = _supportsNativeChannel();
    _refreshNativeAvailability();
  }

  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  final VpnService _fallback;
  final bool _allowFallback;
  VpnStatus _status = VpnStatus.disconnected;
  bool _nativeAvailable = false;
  bool _mockNoticeLogged = false;
  String? _lastNativeAvailabilityMessage;

  @override
  bool get isNativeAvailable => _nativeAvailable;

  @override
  bool canConnectProtocol(VpnProtocol protocol) {
    if (protocol == VpnProtocol.ikev2) return false;
    if (_allowFallback) return true;
    return true;
  }

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) {
    if (protocol == VpnProtocol.ikev2) return ikev2ProductionDisabledMessage;
    if (canConnectProtocol(protocol)) return null;
    return '${vpnProtocolLabel(protocol)} is not available on this runtime.';
  }

  @override
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, String? config}) async {
    if (_status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      if (!canConnectProtocol(protocol)) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'protocol_unavailable',
          protocolUnavailableReason(protocol) ??
              '${vpnProtocolLabel(protocol)} is not available on this runtime.',
        );
      }
      final os = platform.operatingSystem.name.toLowerCase();
      final available = await _refreshNativeAvailability();
      if (!available) {
        if (os == 'ios') {
          _status = VpnStatus.disconnected;
          throw VpnServiceException(
            'vpn_unavailable',
            _lastNativeAvailabilityMessage ??
                'Native VPN tunnel unavailable on this iOS build.',
          );
        }
        if (_allowFallback) {
          _logMockUse('Native VPN unavailable; falling back to demo tunnel.');
          _status = await _fallback.connect(protocol: protocol, config: config);
          return _status;
        }
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'vpn_unavailable',
          _lastNativeAvailabilityMessage ??
              'Native VPN tunnel unavailable on this device. Install required VPN components and retry.',
        );
      }
      if (config == null || config.trim().isEmpty) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'invalid_config',
          'Missing ${vpnProtocolLabel(protocol)} configuration. Please refresh and try again.',
        );
      }
      await _channel.invokeMethod('connect', {
        'protocol': vpnProtocolStorageValue(protocol),
        'config': config,
      });
      _status = VpnStatus.connected;
    } on PlatformException catch (error) {
      final os = platform.operatingSystem.name.toLowerCase();
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        if (os == 'ios') {
          _status = VpnStatus.disconnected;
          throw VpnServiceException(
            error.code,
            error.message ?? 'Native VPN is not configured on this device.',
            details: error.details,
          );
        }
        if (_allowFallback) {
          _logMockUse('Native VPN not configured; using demo tunnel.');
          _status = await _fallback.connect(protocol: protocol, config: config);
        } else {
          _status = VpnStatus.disconnected;
          throw VpnServiceException(
            error.code,
            error.message ?? 'Native VPN is not configured on this device.',
            details: error.details,
          );
        }
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
      final os = platform.operatingSystem.name.toLowerCase();
      if (os == 'ios') {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'vpn_unavailable',
          'Native VPN plugin missing for this iOS build.',
        );
      }
      if (_allowFallback) {
        _logMockUse('Native VPN plugin missing; using demo tunnel.');
        _status = await _fallback.connect(protocol: protocol, config: config);
      } else {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'vpn_unavailable',
          'Native VPN plugin missing for this platform/build.',
        );
      }
    } catch (_) {
      _status = VpnStatus.disconnected;
      rethrow;
    }
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnected ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.disconnecting;
    try {
      final os = platform.operatingSystem.name.toLowerCase();
      final available = await _refreshNativeAvailability();
      if (!available) {
        if (os == 'ios') {
          _status = VpnStatus.disconnected;
          return _status;
        }
        if (_allowFallback) {
          _logMockUse('Native VPN unavailable; using demo disconnect.');
          _status = await _fallback.disconnect();
          return _status;
        }
        _status = VpnStatus.disconnected;
        return _status;
      }
      await _channel.invokeMethod('disconnect');
      _status = VpnStatus.disconnected;
    } on PlatformException catch (error) {
      final os = platform.operatingSystem.name.toLowerCase();
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        if (os == 'ios') {
          _status = VpnStatus.disconnected;
          return _status;
        }
        if (_allowFallback) {
          _logMockUse('Native VPN not configured; using demo disconnect.');
          _status = await _fallback.disconnect();
        } else {
          _status = VpnStatus.disconnected;
        }
      } else {
        throw VpnServiceException(
          error.code,
          error.message ?? 'Unable to stop VPN tunnel.',
          details: error.details,
        );
      }
    } on MissingPluginException {
      _nativeAvailable = false;
      final os = platform.operatingSystem.name.toLowerCase();
      if (os == 'ios') {
        _status = VpnStatus.disconnected;
        return _status;
      }
      if (_allowFallback) {
        _logMockUse('Native VPN plugin missing; using demo disconnect.');
        _status = await _fallback.disconnect();
      } else {
        _status = VpnStatus.disconnected;
      }
    }
    return _status;
  }

  @override
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async {
    if (!_nativeAvailable) return VpnTrafficStats.unavailable;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getTrafficStats',
        {'protocol': vpnProtocolStorageValue(protocol)},
      );
      if (result == null) return VpnTrafficStats.unavailable;
      return VpnTrafficStats.fromJson(result);
    } on PlatformException catch (error) {
      AppLogger.warning('Native VPN traffic stats unavailable.');
      AppLogger.error('VPN traffic stats error', error: error);
      return VpnTrafficStats.unavailable;
    } on MissingPluginException {
      _nativeAvailable = false;
      return VpnTrafficStats.unavailable;
    }
  }

  @override
  VpnStatus getStatus() => _status;

  @override
  Future<VpnRuntimeStatus> refreshRuntimeStatus() async {
    if (!_supportsNativeChannel()) {
      _nativeAvailable = false;
      return VpnRuntimeStatus(status: _status);
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getStatus',
      );
      if (result == null) return VpnRuntimeStatus(status: _status);
      final snapshot = VpnRuntimeStatus.fromJson(result);
      _status = snapshot.status;
      return snapshot;
    } on MissingPluginException {
      _nativeAvailable = false;
      return VpnRuntimeStatus(status: _status);
    } on PlatformException catch (error) {
      AppLogger.warning('Native VPN status unavailable.');
      AppLogger.error('VPN status error', error: error);
      return VpnRuntimeStatus(status: _status);
    }
  }

  bool _supportsNativeChannel() {
    if (kIsWeb) return false;
    final os = platform.operatingSystem.name.toLowerCase();
    return os == 'android' ||
        os == 'ios' ||
        os == 'macos' ||
        os == 'windows' ||
        os == 'linux';
  }

  Future<bool> _refreshNativeAvailability() async {
    if (!_supportsNativeChannel()) {
      _nativeAvailable = false;
      return _nativeAvailable;
    }
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      if (available != null) {
        _nativeAvailable = available;
      } else {
        _nativeAvailable = true;
      }
      if (_nativeAvailable) {
        _lastNativeAvailabilityMessage = null;
      }
    } on MissingPluginException {
      _nativeAvailable = false;
      _lastNativeAvailabilityMessage =
          'Native VPN plugin missing for this platform/build.';
    } on PlatformException catch (error) {
      _lastNativeAvailabilityMessage = error.message;
      _nativeAvailable = false;
    }
    return _nativeAvailable;
  }

  bool _isNativeUnavailableError(PlatformException error) {
    return error.code == 'vpn_not_configured' ||
        error.code == 'vpn_unavailable';
  }

  void _logMockUse(String message) {
    if (_mockNoticeLogged) return;
    _mockNoticeLogged = true;
    AppLogger.warning(message);
  }
}

class MockVpnService implements VpnService {
  MockVpnService({
    this.connectDelay = const Duration(seconds: 2),
    this.disconnectDelay = const Duration(seconds: 1),
  });

  final Duration connectDelay;
  final Duration disconnectDelay;
  VpnStatus _status = VpnStatus.disconnected;
  bool _logged = false;

  @override
  bool get isNativeAvailable => false;

  @override
  bool canConnectProtocol(VpnProtocol protocol) => true;

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) => null;

  @override
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, String? config}) async {
    if (_status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _logMockUse();
    _status = VpnStatus.connecting;
    await Future.delayed(connectDelay);
    _status = VpnStatus.connected;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnected ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _logMockUse();
    _status = VpnStatus.disconnecting;
    await Future.delayed(disconnectDelay);
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async {
    if (_status != VpnStatus.connected) return VpnTrafficStats.unavailable;
    return const VpnTrafficStats(
      rxBytes: 0,
      txBytes: 0,
      countersAvailable: false,
      unavailableReason: 'Mock tunnel does not expose real interface counters.',
    );
  }

  @override
  VpnStatus getStatus() => _status;

  @override
  Future<VpnRuntimeStatus> refreshRuntimeStatus() async {
    return VpnRuntimeStatus(status: _status);
  }

  void _logMockUse() {
    if (_logged) return;
    _logged = true;
    AppLogger.warning('Mock VPN tunnel active: native bridge unavailable.');
  }
}
