import 'dart:async';
import 'dart:math';

import '../config/runtime_config.dart';
import '../models/vpn_profile.dart';
import '../models/vpn_status.dart';
import '../services/vpn_service.dart';
import 'vpn_adapter.dart';

class MockVpnAdapter implements VpnAdapter {
  MockVpnAdapter({
    MockVpnAdapterConfig config = mockVpnAdapterConfig,
    Random? random,
  })  : _config = config,
        _random = random ?? Random();

  final MockVpnAdapterConfig _config;
  final Random _random;
  final StreamController<VpnStatus> _statusController =
      StreamController<VpnStatus>.broadcast();

  VpnStatus _status = VpnStatus.disconnected;

  @override
  Future<VpnConnectionResult> connect(VpnProfile profile) async {
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
      return VpnConnectionResult(
        status: _status == VpnStatus.connecting
            ? VpnStatus.connecting
            : VpnStatus.connected,
        assignedIp: '10.8.0.100',
        adapterMode: 'mock',
      );
    }

    _status = VpnStatus.connecting;
    _statusController.add(VpnStatus.connecting);
    await Future<void>.delayed(_config.latency);

    final shouldFail = _config.forceFailure ||
        (_config.unstableMode && _random.nextInt(10) == 0);
    if (shouldFail) {
      _status = VpnStatus.error;
      _statusController.add(VpnStatus.error);
      throw VpnServiceException(
        'vpn_connect_failed',
        _config.forceFailure
            ? 'Mock VPN forced a connection failure.'
            : 'Mock VPN unstable mode simulated a connection failure.',
      );
    }

    _status = VpnStatus.connected;
    _statusController.add(VpnStatus.connected);
    return const VpnConnectionResult(
      status: VpnStatus.connected,
      assignedIp: '10.8.0.100',
      adapterMode: 'mock',
    );
  }

  @override
  Future<void> disconnect() async {
    if (_status == VpnStatus.disconnected ||
        _status == VpnStatus.disconnecting) {
      _status = VpnStatus.disconnected;
      _statusController.add(VpnStatus.disconnected);
      return;
    }

    _status = VpnStatus.disconnecting;
    _statusController.add(VpnStatus.disconnecting);
    _status = VpnStatus.disconnected;
    _statusController.add(VpnStatus.disconnected);
  }

  @override
  Stream<VpnStatus> statusStream() => _statusController.stream;
}
