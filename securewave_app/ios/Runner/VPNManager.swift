import Foundation
import NetworkExtension
import os
import Darwin

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

  func statusString() -> String {
    switch manager.connection.status {
    case .connected, .reasserting:
      return "connected"
    case .connecting:
      return "connecting"
    case .disconnecting:
      return "disconnecting"
    case .disconnected, .invalid:
      return "disconnected"
    @unknown default:
      return "disconnected"
    }
  }

  func capabilitiesPayload() -> [String: Any] {
    let available = availabilityError() == nil
    return [
      "wireguard": available,
      "openvpn": false,
      "ikev2": false,
      "l2tp": false,
      "shadowsocks": false,
      "tcp_fallback": false,
      "quic": false,
      "android_vpnservice_based": false,
      "windows_thread_safe": false,
      "macos_entitlements_ready": available,
      "macos_entitlement_warning": available
        ? ""
        : "Network Extension entitlements are not configured for Runner + PacketTunnel.",
    ]
  }

  func trafficStatsPayload() -> [String: Any] {
    let status = manager.connection.status
    let connected = status == .connected || status == .reasserting
    let stats = readUtunCounters()
    return [
      "connected": connected,
      "rx_bytes": stats.rx,
      "tx_bytes": stats.tx,
      "interface": stats.interfaceName,
      "protocol": "wireguard",
      "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000),
    ]
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

  private func readUtunCounters() -> (rx: UInt64, tx: UInt64, interfaceName: String) {
    var pointer: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&pointer) == 0, let first = pointer else {
      return (0, 0, "")
    }
    defer { freeifaddrs(pointer) }

    var bestRx: UInt64 = 0
    var bestTx: UInt64 = 0
    var bestName = ""
    var current = first
    while true {
      let name = String(cString: current.pointee.ifa_name)
      if name.hasPrefix("utun"),
         let data = current.pointee.ifa_data {
        let stats = data.assumingMemoryBound(to: if_data.self).pointee
        let rx = UInt64(stats.ifi_ibytes)
        let tx = UInt64(stats.ifi_obytes)
        if (rx + tx) >= (bestRx + bestTx) {
          bestRx = rx
          bestTx = tx
          bestName = name
        }
      }
      guard let next = current.pointee.ifa_next else { break }
      current = next
    }
    return (bestRx, bestTx, bestName)
  }
}
