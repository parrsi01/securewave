import 'dart:async';

import '../models/vpn_profile.dart';
import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../services/vpn_service.dart';
import 'vpn_adapter.dart';

class RealVpnAdapter implements VpnAdapter {
  RealVpnAdapter(this._service);

  final VpnService _service;
  final StreamController<VpnStatus> _statusController =
      StreamController<VpnStatus>.broadcast();

  @override
  Future<VpnConnectionResult> connect(VpnProfile profile) async {
    final protocol = vpnProtocolFromStorage(profile.protocol);
    _statusController.add(VpnStatus.connecting);
    final status = await _service.connect(
      protocol: protocol,
      profile: profile.toNativeProfile(),
    );
    _statusController.add(status);
    return VpnConnectionResult(
      status: status,
      assignedIp: _extractAssignedIp(profile.wireguardConfig),
      adapterMode: 'real',
    );
  }

  @override
  Future<void> disconnect() async {
    _statusController.add(VpnStatus.disconnecting);
    final status = await _service.disconnect();
    _statusController.add(status);
  }

  @override
  Stream<VpnStatus> statusStream() => _statusController.stream;

  String? _extractAssignedIp(String? wireguardConfig) {
    final config = (wireguardConfig ?? '').trim();
    if (config.isEmpty) {
      return null;
    }
    for (final line in config.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.toLowerCase().startsWith('address')) {
        continue;
      }
      final separator = trimmed.indexOf('=');
      if (separator < 0) {
        continue;
      }
      final value = trimmed.substring(separator + 1).trim();
      if (value.isEmpty) {
        continue;
      }
      return value.split(',').first.trim().split('/').first.trim();
    }
    return null;
  }
}
