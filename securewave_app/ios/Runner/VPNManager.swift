import Foundation
import NetworkExtension

final class SecureWaveVPNManager {
  static let shared = SecureWaveVPNManager()

  private let manager = NEVPNManager.shared()

  private var providerBundleIdentifier: String {
    let baseId = Bundle.main.bundleIdentifier ?? "com.example.securewaveApp"
    return "\(baseId).PacketTunnel"
  }

  func connect(config: String, completion: @escaping (Error?) -> Void) {
    configure(config: config) { [weak self] error in
      if let error = error {
        completion(error)
        return
      }
      guard let self = self else {
        completion(NSError(domain: "SecureWave", code: -1, userInfo: [NSLocalizedDescriptionKey: "VPN manager unavailable."]))
        return
      }
      do {
        try self.manager.connection.startVPNTunnel()
        completion(nil)
      } catch {
        completion(error)
      }
    }
  }

  func disconnect(completion: (() -> Void)? = nil) {
    manager.connection.stopVPNTunnel()
    completion?()
  }

  private func configure(config: String, completion: @escaping (Error?) -> Void) {
    manager.loadFromPreferences { [weak self] error in
      if let error = error {
        completion(error)
        return
      }
      guard let self = self else {
        completion(NSError(domain: "SecureWave", code: -2, userInfo: [NSLocalizedDescriptionKey: "VPN manager unavailable."]))
        return
      }
      let tunnelProtocol = NETunnelProviderProtocol()
      tunnelProtocol.providerBundleIdentifier = self.providerBundleIdentifier
      tunnelProtocol.serverAddress = "SecureWave"
      tunnelProtocol.providerConfiguration = ["wgConfig": config]

      self.manager.protocolConfiguration = tunnelProtocol
      self.manager.localizedDescription = "SecureWave VPN"
      self.manager.isEnabled = true

      self.manager.saveToPreferences { error in
        completion(error)
      }
    }
  }
}
