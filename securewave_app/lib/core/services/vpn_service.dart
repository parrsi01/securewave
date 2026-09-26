import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform_info/platform_info.dart';

import '../models/vpn_protocol.dart';
import '../models/vpn_runtime_policy.dart';
import '../models/vpn_status.dart';
import '../logging/app_logger.dart';

abstract class VpnService {
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
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
  ChannelVpnService() {
    _nativeAvailable = false;
  }

  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  VpnStatus _status = VpnStatus.disconnected;
  bool _nativeAvailable = false;
  final Map<VpnProtocol, bool> _protocolAvailability = {};
  final Map<VpnProtocol, String> _protocolAvailabilityMessages = {};
  String? _lastNativeAvailabilityMessage;

  @override
  bool get isNativeAvailable => _nativeAvailable;

  @override
  bool canConnectProtocol(VpnProtocol protocol) {
    if (!VpnRuntimePolicy.isReleased(protocol)) return false;
    return _platformImplementsProtocol(protocol) &&
        (_protocolAvailability[protocol] ?? false);
  }

  bool _platformImplementsProtocol(VpnProtocol protocol) {
    if (!VpnRuntimePolicy.isReleased(protocol)) return false;
    final os = platform.operatingSystem.name.toLowerCase();
    return os == 'linux' && protocol == VpnProtocol.wireGuard;
  }

  @override
  Future<bool> refreshProtocolAvailability(
    VpnProtocol protocol, {
    bool backendEvidence = false,
  }) async {
    if (!VpnRuntimePolicy.isReleased(protocol)) {
      _protocolAvailability[protocol] = false;
      _protocolAvailabilityMessages[protocol] =
          VpnRuntimePolicy.unavailableReason(protocol);
      return false;
    }
    if (!_platformImplementsProtocol(protocol)) {
      _protocolAvailability[protocol] = false;
      return false;
    }
    final evidenceRequired = VpnRuntimePolicy.requiresBackendEvidence(protocol);
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
    if (!VpnRuntimePolicy.isReleased(protocol)) {
      return VpnRuntimePolicy.unavailableReason(protocol);
    }
    if (!_platformImplementsProtocol(protocol)) {
      return '${vpnProtocolLabel(protocol)} is only implemented by the Linux runtime.';
    }
    return _protocolAvailabilityMessages[protocol] ??
        '${vpnProtocolLabel(protocol)} is unavailable because the native helper probe did not confirm this protocol.';
  }

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    String? config,
    bool backendEvidence = false,
  }) async {
    if (_status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      if (!VpnRuntimePolicy.isReleased(protocol)) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'protocol_unavailable',
          VpnRuntimePolicy.unavailableReason(protocol),
        );
      }
      if (!_platformImplementsProtocol(protocol)) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'protocol_unavailable',
          protocolUnavailableReason(protocol) ??
              '${vpnProtocolLabel(protocol)} is not available on this runtime.',
        );
      }
      final available = await refreshProtocolAvailability(
        protocol,
        backendEvidence: backendEvidence,
      );
      if (!available) {
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
        if (backendEvidence) 'backend_evidence': true,
      });
      _status = VpnStatus.connected;
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          error.code,
          error.message ?? 'Native VPN is not configured on this device.',
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
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        'vpn_unavailable',
        'Native VPN plugin missing for this platform/build.',
      );
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
      final available = await _refreshNativeAvailability();
      if (!available) {
        _status = VpnStatus.disconnected;
        return _status;
      }
      await _channel.invokeMethod('disconnect');
      _status = VpnStatus.disconnected;
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
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
      _status = VpnStatus.disconnected;
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
    return os == 'linux';
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
                // Availability tiles need a local capability probe before a
                // backend profile is fetched. Connect still passes fresh
                // backend evidence and remains fail-closed in the runner.
                if (!backendEvidence) 'runtime_only': true,
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
}
