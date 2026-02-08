import Foundation
import NetworkExtension
import os

final class SecureWaveVPNManager {
  static let shared = SecureWaveVPNManager()

  private let manager = NEVPNManager.shared()
  private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SecureWave", category: "vpn")

  private var providerBundleIdentifier: String {
    let baseId = Bundle.main.bundleIdentifier ?? "com.example.securewaveApp"
    return "\(baseId).PacketTunnel"
  }

  func availabilityError() -> Error? {
    return preflightError()
  }

  func connect(config: String, completion: @escaping (Error?) -> Void) {
    if let error = preflightError() {
      log.error("preflight failed: \(error.localizedDescription, privacy: .public)")
      completion(error)
      return
    }
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
        completion(self.wrap(error, operation: "startVPNTunnel"))
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
        completion(self?.wrap(error, operation: "loadFromPreferences"))
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
        if let error = error {
          completion(self.wrap(error, operation: "saveToPreferences"))
        } else {
          completion(nil)
        }
      }
    }
  }

  private func preflightError() -> Error? {
    #if targetEnvironment(simulator)
    return NSError(
      domain: "SecureWave",
      code: -20,
      userInfo: [NSLocalizedDescriptionKey: "VPN requires a physical iOS device (Network Extension is not available on Simulator)."]
    )
    #else
    guard let pluginsURL = Bundle.main.builtInPlugInsURL else {
      return NSError(
        domain: "SecureWave",
        code: -21,
        userInfo: [NSLocalizedDescriptionKey: "PacketTunnel extension is missing from the app bundle (no PlugIns directory)."]
      )
    }

    let appexURL = pluginsURL.appendingPathComponent("PacketTunnel.appex")
    guard let appexBundle = Bundle(url: appexURL) else {
      return NSError(
        domain: "SecureWave",
        code: -22,
        userInfo: [NSLocalizedDescriptionKey: "PacketTunnel extension is not embedded. Ensure Runner embeds PacketTunnel.appex."]
      )
    }

    let expected = providerBundleIdentifier
    let actual = appexBundle.bundleIdentifier ?? "<unknown>"
    guard actual == expected else {
      return NSError(
        domain: "SecureWave",
        code: -23,
        userInfo: [NSLocalizedDescriptionKey: "PacketTunnel bundle identifier mismatch. Expected \(expected), found \(actual)."]
      )
    }

    return nil
    #endif
  }

  private func wrap(_ error: Error, operation: String) -> Error {
    let nsError = error as NSError
    log.error("\(operation, privacy: .public) failed: \(nsError.domain, privacy: .public) (\(nsError.code, privacy: .public)) \(nsError.localizedDescription, privacy: .public)")

    let userMessage: String
    if nsError.domain == NEVPNErrorDomain {
      userMessage = "VPN operation failed. Verify Network Extensions capability + entitlements for Runner and PacketTunnel, and ensure the build is signed for a physical device."
    } else {
      userMessage = "VPN operation failed: \(nsError.localizedDescription)"
    }

    return NSError(
      domain: "SecureWave",
      code: nsError.code,
      userInfo: [
        NSLocalizedDescriptionKey: userMessage,
        NSUnderlyingErrorKey: nsError,
      ]
    )
  }
}
