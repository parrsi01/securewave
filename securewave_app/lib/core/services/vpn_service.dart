import 'package:flutter/services.dart';

import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';

abstract class VpnService {
  Future<VpnStatus> connect({required VpnProtocol protocol});
  Future<VpnStatus> disconnect();
  VpnStatus getStatus();
  bool get isNativeAvailable;
}

class ChannelVpnService implements VpnService {
  ChannelVpnService({VpnService? fallback})
      : _fallback = fallback ?? MockVpnService();

  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  final VpnService _fallback;
  VpnStatus _status = VpnStatus.disconnected;
  bool _nativeAvailable = true;

  @override
  bool get isNativeAvailable => _nativeAvailable;

  @override
  Future<VpnStatus> connect({required VpnProtocol protocol}) async {
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      await _channel.invokeMethod('connect', {
        'protocol': vpnProtocolStorageValue(protocol),
      });
      _status = VpnStatus.connected;
    } on PlatformException {
      _nativeAvailable = false;
      _status = await _fallback.connect(protocol: protocol);
    } on MissingPluginException {
      _nativeAvailable = false;
      _status = await _fallback.connect(protocol: protocol);
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
      _nativeAvailable = false;
      _status = await _fallback.disconnect();
    } on MissingPluginException {
      _nativeAvailable = false;
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
  bool get isNativeAvailable => false;

  @override
  Future<VpnStatus> connect({required VpnProtocol protocol}) async {
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
