import 'vpn_protocol.dart';

/// Client-side runtime policy.
///
/// This is intentionally a second fail-closed gate after backend availability:
/// it prevents a locally installed tool from turning an unreleased protocol
/// into a connectable option.
abstract final class VpnRuntimePolicy {
  static bool isReleased(VpnProtocol protocol) => true;

  static bool requiresBackendEvidence(VpnProtocol protocol) => false;

  static bool requiresFreshEgressProof(VpnProtocol protocol) => false;

  static bool mustDisconnectAfterProcessRestore(VpnProtocol protocol) => false;

  static String unavailableReason(VpnProtocol protocol) =>
      '${vpnProtocolLabel(protocol)} is unavailable on this runtime.';
}
