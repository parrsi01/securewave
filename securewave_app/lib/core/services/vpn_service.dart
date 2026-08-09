import 'package:flutter/services.dart';

import '../models/vpn_status.dart';

abstract class VpnService {
  Future<VpnStatus> connect({required String config});
  Future<VpnStatus> disconnect();
  Future<VpnTrafficStats> getTrafficStats();
  Future<VpnRuntimeStatus> refreshRuntimeStatus();
  bool get isAvailable;
}

class VpnRuntimeStatus {
  const VpnRuntimeStatus({required this.status});

  final VpnStatus status;

  factory VpnRuntimeStatus.fromJson(Map<Object?, Object?> json) {
    final value = json['status']?.toString();
    return VpnRuntimeStatus(status: switch (value) {
      'connected' => VpnStatus.connected,
      'connecting' => VpnStatus.connecting,
      'disconnecting' => VpnStatus.disconnecting,
      'error' => VpnStatus.error,
      _ => VpnStatus.disconnected,
    });
  }
}

class VpnTrafficStats {
  const VpnTrafficStats({required this.rxBytes, required this.txBytes, this.countersAvailable = true});

  final int rxBytes;
  final int txBytes;
  final bool countersAvailable;

  static const unavailable = VpnTrafficStats(rxBytes: 0, txBytes: 0, countersAvailable: false);

  factory VpnTrafficStats.fromJson(Map<Object?, Object?> json) {
    int number(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    final available = json['counters_available'] == true || json['counters_available']?.toString() == 'true';
    return VpnTrafficStats(rxBytes: number(json['rx_bytes']), txBytes: number(json['tx_bytes']), countersAvailable: available);
  }
}

class VpnServiceException implements Exception {
  const VpnServiceException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'VpnServiceException($code): $message';
}

class ChannelVpnService implements VpnService {
  ChannelVpnService({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('securewave/vpn');

  final MethodChannel _channel;
  VpnStatus _status = VpnStatus.disconnected;
  bool _nativeAvailable = false;

  @override
  bool get isAvailable => _nativeAvailable;

  Future<void> _checkAvailable() async {
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      _nativeAvailable = available == true;
      if (!_nativeAvailable) throw const VpnServiceException('vpn_unavailable', 'The SecureWave Linux helper is unavailable. Install the .deb package and retry.');
    } on VpnServiceException {
      rethrow;
    } on PlatformException catch (error) {
      _nativeAvailable = false;
      throw VpnServiceException(error.code, error.message ?? 'The SecureWave Linux helper is unavailable.');
    } on MissingPluginException {
      _nativeAvailable = false;
      throw const VpnServiceException('vpn_unavailable', 'The SecureWave Linux helper is unavailable in this build.');
    }
  }

  @override
  Future<VpnStatus> connect({required String config}) async {
    if (config.trim().isEmpty) throw const VpnServiceException('invalid_config', 'The backend returned an empty WireGuard profile.');
    _status = VpnStatus.connecting;
    try {
      await _checkAvailable();
      await _channel.invokeMethod<void>('connect', {'config': config});
      _status = VpnStatus.connected;
      return _status;
    } on VpnServiceException {
      _status = VpnStatus.disconnected;
      rethrow;
    } on PlatformException catch (error) {
      _status = VpnStatus.disconnected;
      throw VpnServiceException(error.code, error.message ?? 'WireGuard could not connect.');
    } on MissingPluginException {
      _status = VpnStatus.disconnected;
      throw const VpnServiceException('vpn_unavailable', 'The SecureWave Linux helper is unavailable in this build.');
    }
  }

  @override
  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnected) return _status;
    _status = VpnStatus.disconnecting;
    try {
      await _channel.invokeMethod<void>('disconnect');
      _status = VpnStatus.disconnected;
    } on PlatformException catch (error) {
      _status = VpnStatus.error;
      throw VpnServiceException(error.code, error.message ?? 'WireGuard could not disconnect cleanly.');
    } on MissingPluginException {
      _status = VpnStatus.disconnected;
    }
    return _status;
  }

  @override
  Future<VpnTrafficStats> getTrafficStats() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>('getTrafficStats');
      return result == null ? VpnTrafficStats.unavailable : VpnTrafficStats.fromJson(result);
    } on PlatformException {
      return VpnTrafficStats.unavailable;
    } on MissingPluginException {
      _nativeAvailable = false;
      return VpnTrafficStats.unavailable;
    }
  }

  @override
  Future<VpnRuntimeStatus> refreshRuntimeStatus() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>('getStatus');
      if (result == null) return const VpnRuntimeStatus(status: VpnStatus.disconnected);
      final status = VpnRuntimeStatus.fromJson(result);
      _status = status.status;
      _nativeAvailable = true;
      return status;
    } on PlatformException {
      return VpnRuntimeStatus(status: _status);
    } on MissingPluginException {
      _nativeAvailable = false;
      return VpnRuntimeStatus(status: _status);
    }
  }
}

class DemoVpnService implements VpnService {
  VpnStatus _status = VpnStatus.disconnected;
  int _polls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<VpnStatus> connect({required String config}) async {
    if (_status == VpnStatus.connected) return _status;
    _status = VpnStatus.connecting;
    await Future<void>.delayed(const Duration(milliseconds: 280));
    _status = VpnStatus.connected;
    _polls = 0;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnected) return _status;
    _status = VpnStatus.disconnecting;
    await Future<void>.delayed(const Duration(milliseconds: 160));
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  Future<VpnTrafficStats> getTrafficStats() async {
    if (_status != VpnStatus.connected) return VpnTrafficStats.unavailable;
    _polls += 1;
    return VpnTrafficStats(rxBytes: _polls * 8192, txBytes: _polls * 4096);
  }

  @override
  Future<VpnRuntimeStatus> refreshRuntimeStatus() async => VpnRuntimeStatus(status: _status);
}
