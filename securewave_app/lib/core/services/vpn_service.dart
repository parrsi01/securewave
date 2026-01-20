import 'dart:async';

enum VpnStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

abstract class VpnService {
  Stream<VpnStatus> get statusStream;
  VpnStatus get currentStatus;
  Future<void> connect();
  Future<void> disconnect();
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
  Future<void> connect() async {
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
