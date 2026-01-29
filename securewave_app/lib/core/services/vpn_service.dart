import 'package:flutter/services.dart';

import '../models/vpn_status.dart';

abstract class VpnService {
  Future<VpnStatus> connect();
  Future<VpnStatus> disconnect();
  VpnStatus getStatus();
}

class ChannelVpnService implements VpnService {
  ChannelVpnService({VpnService? fallback})
      : _fallback = fallback ?? MockVpnService();

  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  final VpnService _fallback;
  VpnStatus _status = VpnStatus.disconnected;

  @override
  Future<VpnStatus> connect() async {
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      await _channel.invokeMethod('connect');
      _status = VpnStatus.connected;
    } on PlatformException {
      _status = await _fallback.connect();
    } on MissingPluginException {
      _status = await _fallback.connect();
    }
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnected) {
      return _status;
    }
    try {
      await _channel.invokeMethod('disconnect');
      _status = VpnStatus.disconnected;
    } on PlatformException {
      _status = await _fallback.disconnect();
    } on MissingPluginException {
      _status = await _fallback.disconnect();
    }
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;
}

class MockVpnService implements VpnService {
  MockVpnService({
    this.connectDelay = const Duration(seconds: 2),
    this.disconnectDelay = const Duration(seconds: 1),
  });

  final Duration connectDelay;
  final Duration disconnectDelay;
  VpnStatus _status = VpnStatus.disconnected;

  @override
  Future<VpnStatus> connect() async {
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
      return _status;
    }
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
    await Future.delayed(disconnectDelay);
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;
}
