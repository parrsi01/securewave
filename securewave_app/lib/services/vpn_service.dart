import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum VpnStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class VpnServiceException implements Exception {
  const VpnServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VpnTrafficStats {
  const VpnTrafficStats({
    required this.rxBytes,
    required this.txBytes,
    required this.available,
  });

  final int rxBytes;
  final int txBytes;
  final bool available;

  factory VpnTrafficStats.fromMap(Map<Object?, Object?> values) {
    int bytes(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    final available = values['counters_available'] == true ||
        values['counters_available']?.toString().toLowerCase() == 'true';
    return VpnTrafficStats(
      rxBytes: bytes(values['rx_bytes']),
      txBytes: bytes(values['tx_bytes']),
      available: available,
    );
  }

  static const unavailable = VpnTrafficStats(
    rxBytes: 0,
    txBytes: 0,
    available: false,
  );
}

class VpnService {
  static const _channel = MethodChannel('securewave/vpn');

  VpnStatus _status = VpnStatus.disconnected;
  bool _available = false;
  String? _availabilityError;
  String? _statusError;

  VpnStatus get status => _status;
  String? get statusError => _statusError;

  Future<bool> refreshAvailability() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) {
      _available = false;
      _availabilityError = 'SecureWave VPN is available on Linux only.';
      return false;
    }
    try {
      _available = await _channel.invokeMethod<bool>(
            'isAvailable',
            const {
              'protocol': 'wireguard',
              'backend_evidence': true,
            },
          ) ==
          true;
      _availabilityError = null;
    } on PlatformException catch (error) {
      _available = false;
      _availabilityError = error.message;
    } on MissingPluginException {
      _available = false;
      _availabilityError = 'The Linux WireGuard helper is unavailable.';
    }
    return _available;
  }

  Future<VpnStatus> connect(String config) async {
    if (_status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      if (config.trim().isEmpty) {
        throw const VpnServiceException(
            'The API returned an empty WireGuard profile.');
      }
      if (!await refreshAvailability()) {
        throw VpnServiceException(
          _availabilityError ?? 'The Linux WireGuard helper is unavailable.',
        );
      }
      await _channel.invokeMethod<void>('connect', {
        'protocol': 'wireguard',
        'config': config,
        'backend_evidence': true,
      });
      _status = VpnStatus.connected;
      return _status;
    } on PlatformException catch (error) {
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        error.message ?? 'Could not connect the WireGuard tunnel.',
      );
    } on MissingPluginException {
      _status = VpnStatus.disconnected;
      throw const VpnServiceException(
        'The Linux WireGuard helper is unavailable.',
      );
    } catch (_) {
      _status = VpnStatus.disconnected;
      rethrow;
    }
  }

  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnecting) return _status;
    _status = VpnStatus.disconnecting;
    try {
      if (!await refreshAvailability()) {
        throw VpnServiceException(
          _availabilityError ?? 'Could not reach the Linux WireGuard helper.',
        );
      }
      await _channel.invokeMethod<void>('disconnect');
      _status = VpnStatus.disconnected;
      return _status;
    } on PlatformException catch (error) {
      _status = VpnStatus.error;
      throw VpnServiceException(
        error.message ?? 'Could not disconnect the WireGuard tunnel.',
      );
    } on MissingPluginException {
      _status = VpnStatus.error;
      throw const VpnServiceException(
        'The Linux WireGuard helper is unavailable.',
      );
    } catch (_) {
      _status = VpnStatus.error;
      rethrow;
    }
  }

  Future<VpnStatus> refreshRuntimeStatus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) {
      _status = VpnStatus.disconnected;
      return _status;
    }
    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>(
        'getStatus',
      );
      _statusError = values?['message']?.toString();
      _status = _statusError != null && _statusError!.isNotEmpty
          ? VpnStatus.error
          : switch (values?['status']?.toString()) {
              'connected' => VpnStatus.connected,
              _ => VpnStatus.disconnected,
            };
      return _status;
    } on PlatformException catch (error) {
      _statusError = error.message;
      _status = VpnStatus.error;
      return _status;
    } on MissingPluginException {
      _statusError = 'The Linux WireGuard helper is unavailable.';
      _status = VpnStatus.error;
      return _status;
    }
  }

  Future<VpnTrafficStats> getTrafficStats() async {
    if (!_available) return VpnTrafficStats.unavailable;
    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>(
        'getTrafficStats',
        const {'protocol': 'wireguard'},
      );
      return values == null
          ? VpnTrafficStats.unavailable
          : VpnTrafficStats.fromMap(values);
    } on PlatformException {
      return VpnTrafficStats.unavailable;
    } on MissingPluginException {
      _available = false;
      return VpnTrafficStats.unavailable;
    }
  }
}
