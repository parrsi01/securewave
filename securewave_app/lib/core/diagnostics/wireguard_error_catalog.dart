/// Frontend-visible WireGuard failures used by the debug message runner.
///
/// These are simulated UI cases only. Running the catalog never calls the
/// native helper, changes routes, or starts a tunnel.
class WireGuardFrontendErrorCase {
  const WireGuardFrontendErrorCase({
    required this.id,
    required this.code,
    required this.message,
  });

  final String id;
  final String code;
  final String message;
}

/// The messages that can be surfaced by the Flutter WireGuard connection path.
/// Keep this list explicit so a frontend regression is visible in one pass.
const wireGuardFrontendErrorCatalog = <WireGuardFrontendErrorCase>[
  WireGuardFrontendErrorCase(
    id: 'backend_evidence_pending',
    code: 'availability_pending',
    message: 'Checking server support for WireGuard.',
  ),
  WireGuardFrontendErrorCase(
    id: 'backend_evidence_missing',
    code: 'protocol_unavailable',
    message:
        'WireGuard requires fresh backend runtime and data-plane evidence.',
  ),
  WireGuardFrontendErrorCase(
    id: 'server_unsupported',
    code: 'server_protocol_unavailable',
    message: 'The backend catalog does not list WireGuard for this server.',
  ),
  WireGuardFrontendErrorCase(
    id: 'profile_missing',
    code: 'protocol_unavailable',
    message:
        'WireGuard profile did not include a runnable Linux configuration.',
  ),
  WireGuardFrontendErrorCase(
    id: 'config_missing',
    code: 'invalid_config',
    message: 'Missing WireGuard configuration. Please refresh and try again.',
  ),
  WireGuardFrontendErrorCase(
    id: 'config_path_rejected',
    code: 'invalid_path',
    message: 'WireGuard config path is not approved.',
  ),
  WireGuardFrontendErrorCase(
    id: 'config_directives_rejected',
    code: 'invalid_config',
    message: 'WireGuard config contains unsupported privileged directives.',
  ),
  WireGuardFrontendErrorCase(
    id: 'native_unavailable',
    code: 'vpn_unavailable',
    message:
        'Native VPN tunnel unavailable on this device. Install required VPN components and retry.',
  ),
  WireGuardFrontendErrorCase(
    id: 'helper_start_failed',
    code: 'vpn_connect_failed',
    message: 'WireGuard start failed.',
  ),
  WireGuardFrontendErrorCase(
    id: 'interface_missing',
    code: 'vpn_connect_failed',
    message: 'WireGuard command completed but sw-wg was not present.',
  ),
  WireGuardFrontendErrorCase(
    id: 'route_evidence_missing',
    code: 'vpn_connect_failed',
    message:
        'WireGuard command completed but IPv4/IPv6 route evidence did not use sw-wg.',
  ),
  WireGuardFrontendErrorCase(
    id: 'handshake_timeout',
    code: 'vpn_connect_failed',
    message:
        'WireGuard started but did not complete an authenticated handshake within 10 seconds.',
  ),
  WireGuardFrontendErrorCase(
    id: 'runtime_residue',
    code: 'vpn_residue_present',
    message:
        'WireGuard is not connected but owned privileged runtime residue remains.',
  ),
  WireGuardFrontendErrorCase(
    id: 'cleanup_residue',
    code: 'vpn_cleanup_failed',
    message: 'WireGuard cleanup residue remains: <runtime details>.',
  ),
  WireGuardFrontendErrorCase(
    id: 'disconnect_failed',
    code: 'vpn_disconnect_failed',
    message: 'WireGuard stop failed.',
  ),
  WireGuardFrontendErrorCase(
    id: 'disconnect_residue',
    code: 'vpn_disconnect_failed',
    message: 'WireGuard stop completed but cleanup residue remains.',
  ),
  WireGuardFrontendErrorCase(
    id: 'connectivity_drop',
    code: 'connectivity_error',
    message: 'VPN tunnel appears down; kill switch may be blocking traffic.',
  ),
  WireGuardFrontendErrorCase(
    id: 'backend_unreachable',
    code: 'backend_unreachable',
    message:
        'Backend unreachable. The VPN service cannot be reached right now.',
  ),
  WireGuardFrontendErrorCase(
    id: 'auth_failed',
    code: 'auth',
    message: 'Authentication failed. Please sign in again.',
  ),
  WireGuardFrontendErrorCase(
    id: 'profile_not_found',
    code: 'profile_not_found',
    message:
        'Profile fetch failed. The backend could not resolve the selected VPN device or server.',
  ),
  WireGuardFrontendErrorCase(
    id: 'backend_error',
    code: 'backend_error',
    message:
        'Backend server error. The VPN service is experiencing issues. Please try again in a few minutes.',
  ),
  WireGuardFrontendErrorCase(
    id: 'unknown',
    code: 'unknown',
    message:
        'Unable to complete the VPN request right now. If this persists, check Diagnostics for details.',
  ),
];
