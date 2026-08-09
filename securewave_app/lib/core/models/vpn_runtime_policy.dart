import 'vpn_protocol.dart';

/// Client-side runtime policy.
///
/// WireGuard is the only protocol shipped by the Linux beta. Deferred
/// protocols remain represented in the model for compatibility with older
/// payloads, but they are never selectable by the beta UI.
abstract final class VpnRuntimePolicy {
  static bool isReleased(VpnProtocol protocol) =>
      protocol == VpnProtocol.wireGuard;

  static bool requiresBackendEvidence(VpnProtocol protocol) => false;

  static bool requiresFreshEgressProof(VpnProtocol protocol) => false;

  static bool mustDisconnectAfterProcessRestore(VpnProtocol protocol) => false;

  static String unavailableReason(VpnProtocol protocol) {
    return '${vpnProtocolLabel(protocol)} is deferred from the Linux beta.';
  }
}
