import 'dart:async';

import 'package:flutter/services.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting }

abstract class VpnService {
  Stream<VpnStatus> get statusStream;
  VpnStatus get currentStatus;
  Future<void> connect({required String config});
  Future<void> disconnect();
}

class VpnServiceNative implements VpnService {
  VpnServiceNative({VpnService? fallback})
      : _fallback = fallback ?? VpnServiceMock() {
    _controller.add(_status);
  }

  final _controller = StreamController<VpnStatus>.broadcast();
  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  final VpnService _fallback;
  StreamSubscription<VpnStatus>? _fallbackSub;
  VpnStatus _status = VpnStatus.disconnected;
  bool _usingFallback = false;

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  @override
  VpnStatus get currentStatus => _status;

  @override
  Future<void> connect({required String config}) async {
    if (_status != VpnStatus.disconnected) return;
    _setStatus(VpnStatus.connecting);
    try {
      await _channel.invokeMethod('connect', {'config': config});
      _setStatus(VpnStatus.connected);
    } on PlatformException {
      await _activateFallback();
      try {
        await _fallback.connect(config: config);
      } catch (_) {
        _setStatus(VpnStatus.disconnected);
        rethrow;
      }
    } on MissingPluginException {
      await _activateFallback();
      try {
        await _fallback.connect(config: config);
      } catch (_) {
        _setStatus(VpnStatus.disconnected);
        rethrow;
      }
    } catch (_) {
      _setStatus(VpnStatus.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_status != VpnStatus.connected) return;
    _setStatus(VpnStatus.disconnecting);
    if (_usingFallback) {
      try {
        await _fallback.disconnect();
      } finally {
        _setStatus(VpnStatus.disconnected);
      }
      return;
    }
    try {
      await _channel.invokeMethod('disconnect');
      _setStatus(VpnStatus.disconnected);
    } on PlatformException {
      await _activateFallback();
      try {
        await _fallback.disconnect();
      } finally {
        _setStatus(VpnStatus.disconnected);
      }
    } on MissingPluginException {
      await _activateFallback();
      try {
        await _fallback.disconnect();
      } finally {
        _setStatus(VpnStatus.disconnected);
      }
    } catch (_) {
      _setStatus(VpnStatus.disconnected);
      rethrow;
    }
  }

  void _setStatus(VpnStatus status) {
    _status = status;
    _controller.add(status);
  }

  Future<void> _activateFallback() async {
    if (_usingFallback) return;
    _usingFallback = true;
    _fallbackSub = _fallback.statusStream.listen(_setStatus);
  }

  void dispose() {
    _fallbackSub?.cancel();
    _controller.close();
  }
}

class VpnServiceMock implements VpnService {
  VpnServiceMock() {
    _controller.add(_status);
  }

  final _controller = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = VpnStatus.disconnected;

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  @override
  VpnStatus get currentStatus => _status;

  @override
  Future<void> connect({required String config}) async {
    if (_status != VpnStatus.disconnected) return;
    _setStatus(VpnStatus.connecting);
    await Future.delayed(const Duration(seconds: 2));
    _setStatus(VpnStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    if (_status != VpnStatus.connected) return;
    _setStatus(VpnStatus.disconnecting);
    await Future.delayed(const Duration(seconds: 1));
    _setStatus(VpnStatus.disconnected);
  }

  void _setStatus(VpnStatus status) {
    _status = status;
    _controller.add(status);
  }
}

class VpnServiceUnsupported implements VpnService {
  VpnServiceUnsupported(this.message) {
    _controller.add(_status);
  }

  final String message;
  final _controller = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = VpnStatus.disconnected;

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  @override
  VpnStatus get currentStatus => _status;

  @override
  Future<void> connect({required String config}) async {
    throw UnsupportedError(message);
  }

  @override
  Future<void> disconnect() async {
    _setStatus(VpnStatus.disconnected);
  }

  void _setStatus(VpnStatus status) {
    _status = status;
    _controller.add(status);
  }
}
