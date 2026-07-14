import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform_info/platform_info.dart';

import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../logging/app_logger.dart';

abstract class VpnService {
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    String? openVpnUsername,
    String? openVpnPassword,
    bool backendEvidence = false,
  });
  Future<VpnStatus> disconnect();
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async =>
      VpnTrafficStats.unavailable;
  VpnStatus getStatus();
  Future<VpnRuntimeStatus> refreshRuntimeStatus() async =>
      VpnRuntimeStatus(status: getStatus());
  bool get isNativeAvailable;
  bool canConnectProtocol(VpnProtocol protocol);
  Future<bool> refreshProtocolAvailability(
    VpnProtocol protocol, {
    bool backendEvidence = false,
  }) async =>
      canConnectProtocol(protocol);
  String? protocolUnavailableReason(VpnProtocol protocol);
}

class VpnRuntimeStatus {
  const VpnRuntimeStatus({required this.status, this.protocol});

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

  static const unavailable = VpnTrafficStats(
    rxBytes: 0,
    txBytes: 0,
    countersAvailable: false,
  );

  factory VpnTrafficStats.fromJson(Map<Object?, Object?> json) {
    int parseInt(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    bool parseBool(Object? value) =>
        value == true || value?.toString().toLowerCase() == 'true';
    final interfaceName = json['interface']?.toString();
    final unavailableReason = json['unavailable_reason']?.toString();
    return VpnTrafficStats(
      rxBytes: parseInt(json['rx_bytes']),
      txBytes: parseInt(json['tx_bytes']),
      countersAvailable: parseBool(
        json['counters_available'] ?? json['available'],
      ),
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

class ChannelVpnService extends VpnService {
  ChannelVpnService({VpnService? fallback, bool allowFallback = false})
      : _fallback = fallback ?? MockVpnService(),
        _allowFallback = allowFallback {
    _nativeAvailable = false;
  }

  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  final VpnService _fallback;
  final bool _allowFallback;
  VpnStatus _status = VpnStatus.disconnected;
  bool _nativeAvailable = false;
  final Map<VpnProtocol, bool> _protocolAvailability = {};
  final Map<VpnProtocol, String> _protocolAvailabilityMessages = {};
  bool _mockNoticeLogged = false;
  String? _lastNativeAvailabilityMessage;

  @override
  bool get isNativeAvailable => _nativeAvailable;

  @override
  bool canConnectProtocol(VpnProtocol protocol) {
    if (_allowFallback) return true;
    return _platformImplementsProtocol(protocol) &&
        (_protocolAvailability[protocol] ?? false);
  }

  bool _platformImplementsProtocol(VpnProtocol protocol) {
    final os = platform.operatingSystem.name.toLowerCase();
    if (os == 'linux') return true;
    if (os == 'windows' || os == 'android' || os == 'ios') {
      return protocol == VpnProtocol.wireGuard;
    }
    return false;
  }

  @override
  Future<bool> refreshProtocolAvailability(
    VpnProtocol protocol, {
    bool backendEvidence = false,
  }) async {
    if (_allowFallback) return true;
    if (!_platformImplementsProtocol(protocol)) {
      _protocolAvailability[protocol] = false;
      return false;
    }
    final evidenceRequired = protocol != VpnProtocol.wireGuard;
    if (evidenceRequired && !backendEvidence) {
      _protocolAvailability[protocol] = false;
      _protocolAvailabilityMessages[protocol] =
          '${vpnProtocolLabel(protocol)} requires fresh backend runtime and data-plane evidence.';
      _nativeAvailable = _protocolAvailability.values.any((value) => value);
      return false;
    }
    return _refreshNativeAvailability(
      protocol: protocol,
      backendEvidence: backendEvidence,
    );
  }

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) {
    if (canConnectProtocol(protocol)) return null;
    final os = platform.operatingSystem.name.toLowerCase();
    if (os == 'macos') {
      return 'VPN tunneling is unavailable on macOS because this build has no Network Extension provider.';
    }
    if (!_platformImplementsProtocol(protocol)) {
      return '${vpnProtocolLabel(protocol)} is not implemented by this $os runtime.';
    }
    return _protocolAvailabilityMessages[protocol] ??
        '${vpnProtocolLabel(protocol)} is unavailable because the native helper probe did not confirm this protocol.';
  }

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    String? openVpnUsername,
    String? openVpnPassword,
    bool backendEvidence = false,
  }) async {
    if (_status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      if (!_allowFallback && !_platformImplementsProtocol(protocol)) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'protocol_unavailable',
          protocolUnavailableReason(protocol) ??
              '${vpnProtocolLabel(protocol)} is not available on this runtime.',
        );
      }
      final os = platform.operatingSystem.name.toLowerCase();
      final available = await refreshProtocolAvailability(
        protocol,
        backendEvidence: backendEvidence,
      );
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
      if (protocol == VpnProtocol.openVpn &&
          (openVpnUsername == null ||
              openVpnUsername.trim().isEmpty ||
              openVpnPassword == null ||
              openVpnPassword.isEmpty)) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'invalid_config',
          'Missing fresh OpenVPN device credential. Refresh and try again.',
        );
      }
      await _channel.invokeMethod('connect', {
        'protocol': vpnProtocolStorageValue(protocol),
        'config': config,
        if (protocol == VpnProtocol.openVpn) ...{
          'openvpn_username': openVpnUsername,
          'openvpn_password': openVpnPassword,
        },
        if (backendEvidence) 'backend_evidence': true,
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
  VpnStatus getStatus() => _status;

  @override
  Future<VpnTrafficStats> getTrafficStats(VpnProtocol protocol) async {
    if (!_nativeAvailable) return VpnTrafficStats.unavailable;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getTrafficStats',
        {'protocol': vpnProtocolStorageValue(protocol)},
      );
      return result == null
          ? VpnTrafficStats.unavailable
          : VpnTrafficStats.fromJson(result);
    } on PlatformException catch (error) {
      AppLogger.warning(
        'Native VPN traffic counters unavailable: ${error.code}.',
      );
      return VpnTrafficStats.unavailable;
    } on MissingPluginException {
      _nativeAvailable = false;
      return VpnTrafficStats.unavailable;
    }
  }

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
    } on PlatformException catch (error) {
      AppLogger.warning(
        'Native VPN runtime status unavailable: ${error.code}.',
      );
      return VpnRuntimeStatus(status: _status);
    } on MissingPluginException {
      _nativeAvailable = false;
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

  Future<bool> _refreshNativeAvailability({
    VpnProtocol? protocol,
    bool backendEvidence = false,
  }) async {
    if (!_supportsNativeChannel()) {
      _nativeAvailable = false;
      return false;
    }
    try {
      final available = await _channel.invokeMethod<bool>(
        'isAvailable',
        protocol == null
            ? null
            : {
                'protocol': vpnProtocolStorageValue(protocol),
                if (backendEvidence) 'backend_evidence': true,
              },
      );
      if (available != null) {
        if (protocol != null) {
          _protocolAvailability[protocol] = available;
          if (available) {
            _protocolAvailabilityMessages.remove(protocol);
          } else {
            _protocolAvailabilityMessages[protocol] =
                '${vpnProtocolLabel(protocol)} is unavailable because the native helper probe did not confirm this protocol.';
          }
          _nativeAvailable = _protocolAvailability.values.any((value) => value);
        } else {
          _nativeAvailable = available;
        }
      } else {
        if (protocol != null) {
          _protocolAvailability[protocol] = false;
          _protocolAvailabilityMessages[protocol] =
              '${vpnProtocolLabel(protocol)} is unavailable because the native helper probe returned no availability result.';
          _nativeAvailable = _protocolAvailability.values.any((value) => value);
        } else {
          _nativeAvailable = false;
        }
      }
      if (protocol != null && (_protocolAvailability[protocol] ?? false)) {
        _lastNativeAvailabilityMessage = null;
      } else if (protocol != null) {
        _lastNativeAvailabilityMessage =
            _protocolAvailabilityMessages[protocol];
      } else if (_nativeAvailable) {
        _lastNativeAvailabilityMessage = null;
      }
    } on MissingPluginException {
      const message = 'Native VPN plugin missing for this platform/build.';
      if (protocol != null) {
        _protocolAvailability[protocol] = false;
        _protocolAvailabilityMessages[protocol] = message;
      }
      _nativeAvailable = _protocolAvailability.values.any((value) => value);
      _lastNativeAvailabilityMessage = message;
    } on PlatformException catch (error) {
      final message = error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'Native VPN helper probe failed (${error.code}).';
      _lastNativeAvailabilityMessage = message;
      if (protocol != null) {
        _protocolAvailability[protocol] = false;
        _protocolAvailabilityMessages[protocol] = message;
      }
      _nativeAvailable = _protocolAvailability.values.any((value) => value);
    }
    return protocol == null
        ? _nativeAvailable
        : (_protocolAvailability[protocol] ?? false);
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

class MockVpnService extends VpnService {
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
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    String? openVpnUsername,
    String? openVpnPassword,
    bool backendEvidence = false,
  }) async {
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
  VpnStatus getStatus() => _status;

  void _logMockUse() {
    if (_logged) return;
    _logged = true;
    AppLogger.warning('Mock VPN tunnel active: native bridge unavailable.');
  }
}
