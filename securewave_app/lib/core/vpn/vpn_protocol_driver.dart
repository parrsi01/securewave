import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import 'protocol_capabilities.dart';

abstract class VpnProtocolDriver {
  VpnProtocol get protocol;
  VpnStatus get status;
  String? get lastError;

  List<VpnProtocolRequirement> requirements();

  Future<VpnStatus> connect({
    required Map<String, dynamic> profile,
  });

  Future<VpnStatus> disconnect();
}
