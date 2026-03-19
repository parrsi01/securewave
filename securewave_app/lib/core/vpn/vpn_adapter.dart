import '../models/vpn_profile.dart';
import '../models/vpn_status.dart';

class VpnConnectionResult {
  const VpnConnectionResult({
    required this.status,
    this.assignedIp,
    this.adapterMode = 'real',
  });

  final VpnStatus status;
  final String? assignedIp;
  final String adapterMode;
}

abstract class VpnAdapter {
  Future<VpnConnectionResult> connect(VpnProfile profile);
  Future<void> disconnect();
  Stream<VpnStatus> statusStream();
}
