import Darwin
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

  func connect(config: String, completion: @escaping (Error?) -> Void) {
    if let error = preflightError() {
      log.error("preflight failed: \(error.localizedDescription, privacy: .public)")
      completion(error)
      return
    }
    configure(config: config) { [weak self] error in
      if let error {
        completion(error)
        return
      }
      guard let self else {
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

  func tunnelStatus(completion: @escaping ([String: Any]) -> Void) {
    manager.loadFromPreferences { [weak self] error in
      guard let self else {
        completion([
          "status": "DISCONNECTED",
          "interfaceName": NSNull(),
          "interfaceOk": false,
          "routingOk": false,
          "details": "VPN manager unavailable."
        ])
        return
      }
      if let error {
        completion(self.disconnectedPayload(details: error.localizedDescription))
        return
      }

      let sessionStatus = self.statusString(for: self.manager.connection.status)
      let stats = self.currentTunnelInterfaceStats()
      let routeInterface = self.defaultRouteInterface()
      let interfaceOk = stats != nil
      let routingOk = interfaceOk && routeInterface == stats?.name

      completion([
        "status": sessionStatus,
        "interfaceName": stats?.name as Any,
        "interfaceOk": interfaceOk,
        "routingOk": routingOk,
        "details": interfaceOk
          ? "Detected tunnel interface \(stats?.name ?? "unknown")."
          : "No active utun tunnel detected."
      ])
    }
  }

  func trafficStats(completion: @escaping ([String: Any]) -> Void) {
    manager.loadFromPreferences { [weak self] error in
      guard let self else {
        completion(["rxBytes": 0, "txBytes": 0])
        return
      }
      if let error {
        self.log.error("trafficStats load failed: \(error.localizedDescription, privacy: .public)")
        completion(self.interfaceStatsPayload())
        return
      }

      guard self.manager.connection.status == .connected,
            let session = self.manager.connection as? NETunnelProviderSession else {
        completion(self.interfaceStatsPayload())
        return
      }

      let payload = ["command": "traffic_stats"]
      do {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try session.sendProviderMessage(data) { response in
          guard let response else {
            completion(self.interfaceStatsPayload())
            return
          }
          do {
            let decoded = try JSONSerialization.jsonObject(with: response)
            if let dictionary = decoded as? [String: Any] {
              completion(dictionary)
            } else {
              completion(self.interfaceStatsPayload())
            }
          } catch {
            completion(self.interfaceStatsPayload())
          }
        }
      } catch {
        completion(self.interfaceStatsPayload())
      }
    }
  }

  private func configure(config: String, completion: @escaping (Error?) -> Void) {
    manager.loadFromPreferences { [weak self] error in
      if let error {
        completion(self?.wrap(error, operation: "loadFromPreferences"))
        return
      }
      guard let self else {
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
        if let error {
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

  private func interfaceStatsPayload() -> [String: Any] {
    let stats = currentTunnelInterfaceStats()
    return [
      "rxBytes": stats?.rxBytes ?? 0,
      "txBytes": stats?.txBytes ?? 0,
      "interfaceName": stats?.name as Any
    ]
  }

  private func disconnectedPayload(details: String) -> [String: Any] {
    return [
      "status": "DISCONNECTED",
      "interfaceName": NSNull(),
      "interfaceOk": false,
      "routingOk": false,
      "details": details
    ]
  }

  private func defaultRouteInterface() -> String? {
    var routeInterface: String?
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/route")
    process.arguments = ["-n", "get", "default"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        for line in output.split(separator: "\n") {
          let trimmed = line.trimmingCharacters(in: .whitespaces)
          if trimmed.hasPrefix("interface:") {
            routeInterface = trimmed.replacingOccurrences(of: "interface:", with: "")
              .trimmingCharacters(in: .whitespaces)
            break
          }
        }
      }
    } catch {
      return nil
    }
    return routeInterface
  }

  private func currentTunnelInterfaceStats() -> (name: String, rxBytes: Int64, txBytes: Int64)? {
    var pointer: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&pointer) == 0, let first = pointer else {
      return nil
    }
    defer { freeifaddrs(pointer) }

    var candidate: (name: String, rxBytes: Int64, txBytes: Int64)?
    var cursor: UnsafeMutablePointer<ifaddrs>? = first

    while let current = cursor {
      let interface = current.pointee
      let name = String(cString: interface.ifa_name)
      let isTunnel = name.hasPrefix("utun") || name.hasPrefix("wg") || name.hasPrefix("tun")
      if isTunnel,
         let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
        candidate = (
          name: name,
          rxBytes: Int64(data.ifi_ibytes),
          txBytes: Int64(data.ifi_obytes)
        )
      }
      cursor = interface.ifa_next
    }
    return candidate
  }

  private func statusString(for status: NEVPNStatus) -> String {
    switch status {
    case .connected:
      return "CONNECTED"
    case .connecting:
      return "CONNECTING"
    case .disconnecting:
      return "DISCONNECTING"
    case .reasserting:
      return "RECONNECTING"
    case .invalid, .disconnected:
      return "DISCONNECTED"
    @unknown default:
      return "ERROR"
    }
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
