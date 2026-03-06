import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform_info/platform_info.dart';

import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../logging/app_logger.dart';

abstract class VpnService {
  Future<VpnStatus> connect({required VpnProtocol protocol, String? config});
  Future<VpnStatus> disconnect();
  VpnStatus getStatus();
  bool get isNativeAvailable;
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
  ChannelVpnService({VpnService? fallback})
      : _fallback = fallback ?? MockVpnService() {
    _nativeAvailable = _supportsNativeChannel();
    _refreshNativeAvailability();
  }

  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  final VpnService _fallback;
  VpnStatus _status = VpnStatus.disconnected;
  bool _nativeAvailable = false;
  bool _mockNoticeLogged = false;

  @override
  bool get isNativeAvailable => _nativeAvailable;

  @override
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, String? config}) async {
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      final available = await _refreshNativeAvailability();
      if (!available) {
        _logMockUse('Native VPN unavailable; falling back to mock tunnel.');
        _status = await _fallback.connect(protocol: protocol, config: config);
        return _status;
      }
      if (config == null || config.trim().isEmpty) {
        throw VpnServiceException(
          'invalid_config',
          'Missing WireGuard configuration. Please refresh and try again.',
        );
      }
      await _channel.invokeMethod('connect', {
        'protocol': vpnProtocolStorageValue(protocol),
        'config': config,
      });
      _status = VpnStatus.connected;
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        _logMockUse('Native VPN not configured; using mock tunnel.');
        _status = await _fallback.connect(protocol: protocol, config: config);
      } else {
        throw VpnServiceException(
          error.code,
          error.message ?? 'Unable to start VPN tunnel.',
          details: error.details,
        );
      }
    } on MissingPluginException {
      _nativeAvailable = false;
      _logMockUse('Native VPN plugin missing; using mock tunnel.');
      _status = await _fallback.connect(protocol: protocol, config: config);
    }
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnected) {
      return _status;
    }
    try {
      final available = await _refreshNativeAvailability();
      if (!available) {
        _logMockUse('Native VPN unavailable; using mock disconnect.');
        _status = await _fallback.disconnect();
        return _status;
      }
      await _channel.invokeMethod('disconnect');
      _status = VpnStatus.disconnected;
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        _logMockUse('Native VPN not configured; using mock disconnect.');
        _status = await _fallback.disconnect();
      } else {
        throw VpnServiceException(
          error.code,
          error.message ?? 'Unable to stop VPN tunnel.',
          details: error.details,
        );
      }
    } on MissingPluginException {
      _nativeAvailable = false;
      _logMockUse('Native VPN plugin missing; using mock disconnect.');
      _status = await _fallback.disconnect();
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

  Future<bool> _refreshNativeAvailability() async {
    if (!_supportsNativeChannel()) {
      _nativeAvailable = false;
      return _nativeAvailable;
    }
    final os = platform.operatingSystem.name.toLowerCase();
    if (os == 'ios') {
      _nativeAvailable = true;
      return _nativeAvailable;
    }
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      if (available != null) {
        _nativeAvailable = available;
      } else {
        _nativeAvailable = true;
      }
    } on MissingPluginException {
      _nativeAvailable = false;
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
      } else {
        _nativeAvailable = false;
      }
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
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, String? config}) async {
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
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
    if (_status == VpnStatus.disconnected) {
      return _status;
    }
    _logMockUse();
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
