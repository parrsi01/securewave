import 'vpn_status.dart';

class TunnelHealthSnapshot {
  const TunnelHealthSnapshot({
    required this.status,
    required this.interfaceName,
    required this.interfaceOk,
    required this.routingOk,
    required this.details,
    this.connectedSince,
    this.lastError,
  });

  final VpnStatus status;
  final String? interfaceName;
  final bool interfaceOk;
  final bool routingOk;
  final String? details;
  final DateTime? connectedSince;
  final String? lastError;

  static const disconnected = TunnelHealthSnapshot(
    status: VpnStatus.disconnected,
    interfaceName: null,
    interfaceOk: false,
    routingOk: false,
    details: null,
    connectedSince: null,
    lastError: null,
  );
}
