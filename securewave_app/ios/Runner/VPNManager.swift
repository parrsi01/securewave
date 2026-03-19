import Darwin
import Foundation
import NetworkExtension
import os

private enum SecureWaveAppleKeys {
  static let appGroupInfoKey = "SecureWaveAppGroupIdentifier"
  static let packetTunnelBundleInfoKey = "SecureWavePacketTunnelBundleIdentifier"

  static let lastState = "securewave.apple_vpn.last_state"
  static let lastError = "securewave.apple_vpn.last_error"
  static let connectedSince = "securewave.apple_vpn.connected_since"

  static let fieldServerId = "serverId"
  static let fieldEndpointHost = "endpointHost"
  static let fieldEndpointPort = "endpointPort"
  static let fieldClientPrivateKey = "clientPrivateKey"
  static let fieldAddressCidr = "addressCidr"
  static let fieldDns = "dns"
  static let fieldAllowedIps = "allowedIps"
  static let fieldKeepaliveSeconds = "keepaliveSeconds"
  static let fieldPresharedKey = "presharedKey"
  static let fieldServerPublicKey = "serverPublicKey"
  static let fieldUsePacketTunnelFallback = "usePacketTunnelFallback"
}

private struct SecureWaveSharedTunnelSnapshot {
  let state: String
  let lastError: String?
  let connectedSince: Date?
}

private final class SecureWaveTunnelStateStore {
  init(appGroupIdentifier: String) {
    self.appGroupIdentifier = appGroupIdentifier
  }

  private let appGroupIdentifier: String

  private var defaults: UserDefaults? {
    UserDefaults(suiteName: appGroupIdentifier)
  }

  var isConfigured: Bool {
    defaults != nil
  }

  func snapshot() -> SecureWaveSharedTunnelSnapshot {
    guard let defaults else {
      return SecureWaveSharedTunnelSnapshot(
        state: "unavailable",
        lastError: "App Group '\(appGroupIdentifier)' is unavailable.",
        connectedSince: nil
      )
    }

    let state = defaults.string(forKey: SecureWaveAppleKeys.lastState) ?? "disconnected"
    let error = defaults.string(forKey: SecureWaveAppleKeys.lastError)
    let timestamp = defaults.double(forKey: SecureWaveAppleKeys.connectedSince)
    let connectedSince = timestamp > 0
      ? Date(timeIntervalSince1970: timestamp)
      : nil
    return SecureWaveSharedTunnelSnapshot(
      state: state,
      lastError: error?.isEmpty == true ? nil : error,
      connectedSince: connectedSince
    )
  }

  func record(state: String, lastError: String?, connectedSince: Date?) {
    guard let defaults else { return }
    defaults.set(state, forKey: SecureWaveAppleKeys.lastState)
    if let lastError, !lastError.isEmpty {
      defaults.set(lastError, forKey: SecureWaveAppleKeys.lastError)
    } else {
      defaults.removeObject(forKey: SecureWaveAppleKeys.lastError)
    }
    if let connectedSince {
      defaults.set(connectedSince.timeIntervalSince1970, forKey: SecureWaveAppleKeys.connectedSince)
    } else {
      defaults.removeObject(forKey: SecureWaveAppleKeys.connectedSince)
    }
  }
}

private struct SecureWaveWireGuardRequest {
  let serverId: String
  let endpointHost: String
  let endpointPort: Int
  let clientPrivateKey: String
  let addressCidr: String
  let dns: [String]
  let allowedIps: [String]
  let keepaliveSeconds: Int
  let presharedKey: String?
  let serverPublicKey: String
  let usePacketTunnelFallback: Bool

  init(arguments: [String: Any]) throws {
    func requiredString(_ key: String) throws -> String {
      let value = (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !value.isEmpty else {
        throw SecureWaveVPNManager.makeError(
          code: "invalid_profile",
          message: "Missing WireGuard field '\(key)'."
        )
      }
      return value
    }

    func stringList(_ key: String) -> [String] {
      if let values = arguments[key] as? [String] {
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      }
      if let values = arguments[key] as? [Any] {
        return values.map { "\($0)".trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      }
      if let value = arguments[key] as? String {
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      }
      return []
    }

    func requiredInt(_ key: String) throws -> Int {
      if let value = arguments[key] as? Int, value > 0 {
        return value
      }
      if let value = arguments[key] as? NSNumber, value.intValue > 0 {
        return value.intValue
      }
      if let text = arguments[key] as? String, let value = Int(text), value > 0 {
        return value
      }
      throw SecureWaveVPNManager.makeError(
        code: "invalid_profile",
        message: "Missing or invalid WireGuard field '\(key)'."
      )
    }

    let dns = stringList(SecureWaveAppleKeys.fieldDns)
    let allowedIps = stringList(SecureWaveAppleKeys.fieldAllowedIps)
    guard !allowedIps.isEmpty else {
      throw SecureWaveVPNManager.makeError(
        code: "invalid_profile",
        message: "WireGuard AllowedIPs are required."
      )
    }

    self.serverId = (arguments[SecureWaveAppleKeys.fieldServerId] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "securewave-wireguard"
    self.endpointHost = try requiredString(SecureWaveAppleKeys.fieldEndpointHost)
    self.endpointPort = try requiredInt(SecureWaveAppleKeys.fieldEndpointPort)
    self.clientPrivateKey = try requiredString(SecureWaveAppleKeys.fieldClientPrivateKey)
    self.addressCidr = try requiredString(SecureWaveAppleKeys.fieldAddressCidr)
    self.dns = dns
    self.allowedIps = allowedIps
    self.keepaliveSeconds = max(
      0,
      (arguments[SecureWaveAppleKeys.fieldKeepaliveSeconds] as? NSNumber)?.intValue ??
        Int((arguments[SecureWaveAppleKeys.fieldKeepaliveSeconds] as? String) ?? "") ??
        25
    )
    let preshared = (arguments[SecureWaveAppleKeys.fieldPresharedKey] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    self.presharedKey = preshared?.isEmpty == true ? nil : preshared
    self.serverPublicKey = try requiredString(SecureWaveAppleKeys.fieldServerPublicKey)
    if let value = arguments[SecureWaveAppleKeys.fieldUsePacketTunnelFallback] as? Bool {
      self.usePacketTunnelFallback = value
    } else if let value = arguments[SecureWaveAppleKeys.fieldUsePacketTunnelFallback] as? NSNumber {
      self.usePacketTunnelFallback = value.boolValue
    } else if let value = arguments[SecureWaveAppleKeys.fieldUsePacketTunnelFallback] as? String {
      let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      self.usePacketTunnelFallback =
        normalized == "1" || normalized == "true" || normalized == "yes"
    } else {
      self.usePacketTunnelFallback = false
    }
  }

  func providerConfiguration(appGroupIdentifier: String) -> [String: Any] {
    return [
      SecureWaveAppleKeys.fieldServerId: serverId,
      SecureWaveAppleKeys.fieldEndpointHost: endpointHost,
      SecureWaveAppleKeys.fieldEndpointPort: endpointPort,
      SecureWaveAppleKeys.fieldClientPrivateKey: clientPrivateKey,
      SecureWaveAppleKeys.fieldAddressCidr: addressCidr,
      SecureWaveAppleKeys.fieldDns: dns,
      SecureWaveAppleKeys.fieldAllowedIps: allowedIps,
      SecureWaveAppleKeys.fieldKeepaliveSeconds: keepaliveSeconds,
      SecureWaveAppleKeys.fieldServerPublicKey: serverPublicKey,
      SecureWaveAppleKeys.fieldUsePacketTunnelFallback: usePacketTunnelFallback,
      SecureWaveAppleKeys.appGroupInfoKey: appGroupIdentifier,
      SecureWaveAppleKeys.fieldPresharedKey: presharedKey as Any
    ]
  }
}

final class SecureWaveVPNManager {
  static let shared = SecureWaveVPNManager()

  private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "SecureWave",
    category: "apple_vpn_bridge"
  )

  private var appGroupIdentifier: String {
    (Bundle.main.object(forInfoDictionaryKey: SecureWaveAppleKeys.appGroupInfoKey) as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty ?? "group.com.example.securewaveApp.shared"
  }

  private var providerBundleIdentifier: String {
    (Bundle.main.object(forInfoDictionaryKey: SecureWaveAppleKeys.packetTunnelBundleInfoKey) as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmpty ?? "\(Bundle.main.bundleIdentifier ?? "com.example.securewaveApp").PacketTunnel"
  }

  private var stateStore: SecureWaveTunnelStateStore {
    SecureWaveTunnelStateStore(appGroupIdentifier: appGroupIdentifier)
  }

  func isAvailable(completion: @escaping (Bool, String?) -> Void) {
    diagnostics { payload in
      let available = payload["available"] as? Bool ?? false
      completion(available, payload["lastError"] as? String)
    }
  }

  func diagnostics(completion: @escaping ([String: Any]) -> Void) {
    let extensionEmbedded = embeddedPacketTunnelURL() != nil
    let appGroupConfigured = stateStore.isConfigured
    let preflight = preflightError(
      extensionEmbedded: extensionEmbedded,
      appGroupConfigured: appGroupConfigured
    )

    loadManager { [weak self] manager, loadError in
      guard let self else {
        completion([
          "available": false,
          "extensionEmbedded": false,
          "appGroupConfigured": false,
          "tunnelManagerReady": false,
          "lastError": "VPN manager unavailable."
        ])
        return
      }

      let managerReady = loadError == nil
      let snapshot = self.stateStore.snapshot()
      let errorText = (preflight ?? loadError)?.localizedDescription ??
        snapshot.lastError
      completion([
        "available": preflight == nil && managerReady,
        "extensionEmbedded": extensionEmbedded,
        "appGroupConfigured": appGroupConfigured,
        "tunnelManagerReady": managerReady,
        "appGroupIdentifier": self.appGroupIdentifier,
        "providerBundleIdentifier": self.providerBundleIdentifier,
        "lastError": errorText as Any
      ])
    }
  }

  func status(completion: @escaping ([String: Any]) -> Void) {
    let extensionEmbedded = embeddedPacketTunnelURL() != nil
    let appGroupConfigured = stateStore.isConfigured
    let preflight = preflightError(
      extensionEmbedded: extensionEmbedded,
      appGroupConfigured: appGroupConfigured
    )

    loadManager { [weak self] manager, loadError in
      guard let self else {
        completion([
          "state": "unavailable",
          "lastError": "VPN manager unavailable.",
          "rxBytes": 0,
          "txBytes": 0,
          "connectedSince": NSNull()
        ])
        return
      }

      let snapshot = self.stateStore.snapshot()
      let state = self.currentState(
        manager: manager,
        snapshot: snapshot,
        preflightError: preflight ?? loadError
      )
      let counters = self.readUtunCounters()
      let connectedSince = snapshot.connectedSince?.timeIntervalSince1970
      completion([
        "state": state,
        "lastError": (preflight ?? loadError)?.localizedDescription ?? snapshot.lastError as Any,
        "rxBytes": counters.rx,
        "txBytes": counters.tx,
        "connectedSince": connectedSince as Any
      ])
    }
  }

  func connectWireGuard(arguments: [String: Any], completion: @escaping (Error?) -> Void) {
    do {
      let request = try SecureWaveWireGuardRequest(arguments: arguments)
      let extensionEmbedded = embeddedPacketTunnelURL() != nil
      let appGroupConfigured = stateStore.isConfigured
      if let preflight = preflightError(
        extensionEmbedded: extensionEmbedded,
        appGroupConfigured: appGroupConfigured
      ) {
        stateStore.record(state: "unavailable", lastError: preflight.localizedDescription, connectedSince: nil)
        completion(preflight)
        return
      }

      stateStore.record(state: "connecting", lastError: nil, connectedSince: nil)
      loadManager { [weak self] manager, loadError in
        guard let self else {
          completion(Self.makeError(code: "vpn_unavailable", message: "VPN manager unavailable."))
          return
        }
        if let loadError {
          let wrapped = self.wrap(
            loadError,
            code: "vpn_unavailable",
            operation: "loadAllFromPreferences"
          )
          self.stateStore.record(state: "error", lastError: wrapped.localizedDescription, connectedSince: nil)
          completion(wrapped)
          return
        }

        let tunnelManager = manager ?? NETunnelProviderManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = self.providerBundleIdentifier
        tunnelProtocol.serverAddress = request.endpointHost
        tunnelProtocol.providerConfiguration = request.providerConfiguration(
          appGroupIdentifier: self.appGroupIdentifier
        )

        tunnelManager.protocolConfiguration = tunnelProtocol
        tunnelManager.localizedDescription = "SecureWave WireGuard"
        tunnelManager.isEnabled = true

        tunnelManager.saveToPreferences { error in
          if let error {
            let wrapped = self.wrap(
              error,
              code: "vpn_permission_required",
              operation: "saveToPreferences"
            )
            self.stateStore.record(state: "error", lastError: wrapped.localizedDescription, connectedSince: nil)
            completion(wrapped)
            return
          }

          tunnelManager.loadFromPreferences { error in
            if let error {
              let wrapped = self.wrap(
                error,
                code: "vpn_permission_required",
                operation: "loadFromPreferences"
              )
              self.stateStore.record(state: "error", lastError: wrapped.localizedDescription, connectedSince: nil)
              completion(wrapped)
              return
            }

            do {
              if let session = tunnelManager.connection as? NETunnelProviderSession {
                try session.startVPNTunnel()
              } else {
                try tunnelManager.connection.startVPNTunnel()
              }
              completion(nil)
            } catch {
              let wrapped = self.wrap(
                error,
                code: "vpn_connect_failed",
                operation: "startVPNTunnel"
              )
              self.stateStore.record(state: "error", lastError: wrapped.localizedDescription, connectedSince: nil)
              completion(wrapped)
            }
          }
        }
      }
    } catch {
      let wrapped = (error as? NSError) ?? Self.makeError(
        code: "invalid_profile",
        message: error.localizedDescription
      )
      stateStore.record(state: "error", lastError: wrapped.localizedDescription, connectedSince: nil)
      completion(wrapped)
    }
  }

  func startVPN(arguments: [String: Any], completion: @escaping (Error?) -> Void) {
    connectWireGuard(arguments: arguments, completion: completion)
  }

  func disconnect(completion: @escaping (Error?) -> Void) {
    stateStore.record(state: "disconnecting", lastError: nil, connectedSince: stateStore.snapshot().connectedSince)
    loadManager { [weak self] manager, loadError in
      guard let self else {
        completion(Self.makeError(code: "vpn_unavailable", message: "VPN manager unavailable."))
        return
      }
      if let loadError {
        let wrapped = self.wrap(
          loadError,
          code: "vpn_unavailable",
          operation: "loadAllFromPreferences"
        )
        self.stateStore.record(state: "error", lastError: wrapped.localizedDescription, connectedSince: nil)
        completion(wrapped)
        return
      }
      guard let manager else {
        self.stateStore.record(state: "disconnected", lastError: nil, connectedSince: nil)
        completion(nil)
        return
      }

      if let session = manager.connection as? NETunnelProviderSession {
        session.stopTunnel()
      } else {
        manager.connection.stopVPNTunnel()
      }
      completion(nil)
    }
  }

  func stopVPN(completion: @escaping (Error?) -> Void) {
    disconnect(completion: completion)
  }

  private func loadManager(completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { [providerBundleIdentifier] managers, error in
      if let error {
        completion(nil, error)
        return
      }

      let manager = managers?.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier ==
          providerBundleIdentifier
      }
      completion(manager, nil)
    }
  }

  private func embeddedPacketTunnelURL() -> URL? {
    guard let pluginsURL = Bundle.main.builtInPlugInsURL else { return nil }
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: pluginsURL,
      includingPropertiesForKeys: nil
    )) ?? []
    return urls.first { url in
      Bundle(url: url)?.bundleIdentifier == providerBundleIdentifier
    }
  }

  private func preflightError(
    extensionEmbedded: Bool,
    appGroupConfigured: Bool
  ) -> NSError? {
    #if targetEnvironment(simulator)
    return Self.makeError(
      code: "vpn_unavailable",
      message: "VPN requires a physical iOS device. Network Extension is unavailable on Simulator."
    )
    #else
    if !extensionEmbedded {
      return Self.makeError(
        code: "vpn_unavailable",
        message: "Packet Tunnel extension is not embedded in this app bundle."
      )
    }
    if !appGroupConfigured {
      return Self.makeError(
        code: "vpn_unavailable",
        message: "App Group '\(appGroupIdentifier)' is not configured for Runner and PacketTunnel."
      )
    }
    return nil
    #endif
  }

  private func currentState(
    manager: NETunnelProviderManager?,
    snapshot: SecureWaveSharedTunnelSnapshot,
    preflightError: Error?
  ) -> String {
    if preflightError != nil {
      return "unavailable"
    }

    guard let manager else {
      return snapshot.state == "error" ? "error" : "disconnected"
    }

    switch manager.connection.status {
    case .connected, .reasserting:
      return "connected"
    case .connecting:
      return "connecting"
    case .disconnecting:
      return "disconnecting"
    case .disconnected, .invalid:
      if snapshot.state == "error", snapshot.lastError != nil {
        return "error"
      }
      return "disconnected"
    @unknown default:
      return "disconnected"
    }
  }

  private func readUtunCounters() -> (rx: UInt64, tx: UInt64) {
    var pointer: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&pointer) == 0, let first = pointer else {
      return (0, 0)
    }
    defer { freeifaddrs(pointer) }

    var bestRx: UInt64 = 0
    var bestTx: UInt64 = 0
    var current = first
    while true {
      let name = String(cString: current.pointee.ifa_name)
      if name.hasPrefix("utun"), let data = current.pointee.ifa_data {
        let stats = data.assumingMemoryBound(to: if_data.self).pointee
        let rx = UInt64(stats.ifi_ibytes)
        let tx = UInt64(stats.ifi_obytes)
        if (rx + tx) >= (bestRx + bestTx) {
          bestRx = rx
          bestTx = tx
        }
      }
      guard let next = current.pointee.ifa_next else { break }
      current = next
    }
    return (bestRx, bestTx)
  }

  private func wrap(_ error: Error, code: String, operation: String) -> NSError {
    let nsError = error as NSError
    log.error(
      "\(operation, privacy: .public) failed: \(nsError.domain, privacy: .public) (\(nsError.code, privacy: .public)) \(nsError.localizedDescription, privacy: .public)"
    )
    let message: String
    if nsError.domain == NEVPNErrorDomain {
      message = "Network Extension rejected the VPN operation. Check signing, entitlements, and Packet Tunnel embedding."
    } else {
      message = nsError.localizedDescription
    }
    return Self.makeError(code: code, message: message, underlying: nsError)
  }

  static func makeError(code: String, message: String, underlying: Error? = nil) -> NSError {
    var userInfo: [String: Any] = [
      NSLocalizedDescriptionKey: message,
      "SecureWaveErrorCode": code,
    ]
    if let underlying {
      userInfo[NSUnderlyingErrorKey] = underlying
    }
    return NSError(domain: "SecureWaveVPN", code: 1, userInfo: userInfo)
  }
}

private extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
