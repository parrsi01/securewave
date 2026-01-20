import NetworkExtension

#if canImport(WireGuardKit)
import WireGuardKit
#endif

class PacketTunnelProvider: NEPacketTunnelProvider {
  #if canImport(WireGuardKit)
  private var adapter: WireGuardAdapter?
  #endif

  override func startTunnel(options: [String : NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
    guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
          let config = tunnelProtocol.providerConfiguration?["wgConfig"] as? String,
          !config.isEmpty else {
      completionHandler(NSError(domain: "SecureWave", code: -10, userInfo: [NSLocalizedDescriptionKey: "Missing WireGuard configuration."]))
      return
    }

    #if canImport(WireGuardKit)
    do {
      let tunnelConfig = try TunnelConfiguration(fromWgQuickConfig: config, called: "SecureWave")
      let adapter = WireGuardAdapter(with: self) { _, _ in }
      self.adapter = adapter
      adapter.start(tunnelConfiguration: tunnelConfig) { error in
        completionHandler(error)
      }
    } catch {
      completionHandler(error)
    }
    #else
    completionHandler(NSError(domain: "SecureWave", code: -11, userInfo: [NSLocalizedDescriptionKey: "WireGuardKit is not linked. Add the package in Xcode."]))
    #endif
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    #if canImport(WireGuardKit)
    adapter?.stop { completionHandler() }
    adapter = nil
    #else
    completionHandler()
    #endif
  }

  override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
    completionHandler?(nil)
  }
}
