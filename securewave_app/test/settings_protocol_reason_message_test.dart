import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/screens/settings/settings_screen.dart';

void main() {
  test('maps backend typed protocol reasons to actionable UI text', () {
    expect(
      protocolUnavailableReasonMessage(
        'openvpn_server_misconfigured',
        VpnProtocol.openVpn,
      ),
      'Server provisioning not installed. Admin action required.',
    );
    expect(
      protocolUnavailableReasonMessage(
        'ikev2_healthcheck_fail',
        VpnProtocol.ikev2,
      ),
      'Service not running on server.',
    );
    expect(
      protocolUnavailableReasonMessage(
        'openvpn_unavailable_region',
        VpnProtocol.openVpn,
      ),
      'Not available in selected region.',
    );
    expect(
      protocolUnavailableReasonMessage(
        'ikev2_temporarily_unavailable',
        VpnProtocol.ikev2,
      ),
      'Temporarily unavailable. Try later.',
    );
    expect(
      protocolUnavailableReasonMessage(
        'ikev2_auth_mode_mismatch_linux',
        VpnProtocol.ikev2,
      ),
      'IKEv2 auth mode incompatible with Linux automation; manual setup required.',
    );
    expect(
      protocolUnavailableReasonMessage(
        'no_servers_available',
        VpnProtocol.wireGuard,
      ),
      'No healthy servers.',
    );
  });

  test('hides raw backend reason codes in production-safe mode', () {
    expect(
      protocolUnavailableReasonMessage(
        'internal_region_probe_failed',
        VpnProtocol.wireGuard,
        includeDebugReason: false,
      ),
      'Currently unavailable.',
    );
  });
}
