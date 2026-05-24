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
  bool canConnectProtocol(VpnProtocol protocol);
  String? protocolUnavailableReason(VpnProtocol protocol);
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
  ChannelVpnService({VpnService? fallback, bool allowFallback = true})
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
    if (_allowFallback) return true;
    final os = platform.operatingSystem.name.toLowerCase();
    if (os == 'linux' && protocol == VpnProtocol.ikev2) {
      return false;
    }
    return true;
  }

  @override
  String? protocolUnavailableReason(VpnProtocol protocol) {
    if (canConnectProtocol(protocol)) return null;
    final os = platform.operatingSystem.name.toLowerCase();
    if (os == 'linux' && protocol == VpnProtocol.ikev2) {
      return 'IKEv2 is blocked on Linux until the strongSwan profile import/start path is implemented.';
    }
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
  VpnStatus getStatus() => _status;

  void _logMockUse() {
    if (_logged) return;
    _logged = true;
    AppLogger.warning('Mock VPN tunnel active: native bridge unavailable.');
  }
}
