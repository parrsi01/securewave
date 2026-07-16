import 'vpn_protocol.dart';

/// Client-side runtime policy.
///
/// This is intentionally a second fail-closed gate after backend availability:
/// it prevents a locally installed tool from turning an unreleased protocol
/// into a connectable option.
abstract final class VpnRuntimePolicy {
  static bool isReleased(VpnProtocol protocol) => protocol != VpnProtocol.ikev2;

  static bool requiresBackendEvidence(VpnProtocol protocol) =>
      protocol != VpnProtocol.wireGuard;

  static bool requiresFreshEgressProof(VpnProtocol protocol) =>
      protocol == VpnProtocol.openVpn;

  static bool mustDisconnectAfterProcessRestore(VpnProtocol protocol) =>
      protocol != VpnProtocol.wireGuard;

  static String unavailableReason(VpnProtocol protocol) {
    if (protocol == VpnProtocol.ikev2) {
      return 'IKEv2 is temporarily unavailable while its dedicated gateway is not provisioned.';
    }
    return '${vpnProtocolLabel(protocol)} is unavailable on this runtime.';
  }
}
