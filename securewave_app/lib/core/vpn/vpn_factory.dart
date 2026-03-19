import '../config/runtime_config.dart';
import '../services/vpn_service.dart';
import 'mock_vpn_adapter.dart';
import 'real_vpn_adapter.dart';
import 'vpn_adapter.dart';

VpnAdapter createVpnAdapter({
  VpnService? realService,
  MockVpnAdapterConfig? mockConfig,
}) {
  if (isMockVpn) {
    return MockVpnAdapter(config: mockConfig ?? mockVpnAdapterConfig);
  }
  return RealVpnAdapter(realService ?? ChannelVpnService());
}
