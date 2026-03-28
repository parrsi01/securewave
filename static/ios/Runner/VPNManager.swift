import Darwin
import Foundation
import NetworkExtension
import Security
import os

private enum SecureWaveAppleKeys {
  static let appGroupInfoKey = "SecureWaveAppGroupIdentifier"
  static let packetTunnelBundleInfoKey = "SecureWavePacketTunnelBundleIdentifier"

  static let lastState = "securewave.apple.state"
  static let lastError = "securewave.apple.lastError"
  static let connectedSince = "securewave.apple.connectedSince"
  static let currentProtocol = "securewave.apple.protocol"

  static let credentialService = "SecureWaveVPN"
  static let fieldProtocol = "protocol"
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
  static let fieldOvpnConfig = "ovpn_config"

  static let fieldServer = "server"
  static let fieldRemoteId = "remote_id"
  static let fieldLocalId = "local_id"
  static let fieldAuthMethod = "auth_method"
  static let fieldUsername = "username"
  static let fieldPassword = "password"
  static let fieldClientPkcs12Base64 = "client_pkcs12_base64"
  static let fieldClientPkcs12Password = "client_pkcs12_password"
}

private enum SecureWaveAppleProtocol: String {
  case wireGuard = "wireguard"
  case openVpn = "openvpn"
  case ikev2 = "ikev2"

  init(arguments: [String: Any]) throws {
    let raw = (
      (arguments[SecureWaveAppleKeys.fieldProtocol] as? String) ??
      (arguments["type"] as? String) ??
      ""
    )
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard let value = Self(rawValue: raw) else {
      throw SecureWaveVPNManager.makeError(
        code: "invalid_profile",
        message: "Unsupported Apple VPN protocol '\(raw.isEmpty ? "unknown" : raw)'."
      )
    }
    self = value
  }

  var localizedName: String {
    switch self {
    case .wireGuard:
      return "WireGuard"
    case .openVpn:
      return "OpenVPN"
    case .ikev2:
      return "IKEv2"
    }
  }

  var interfaceName: String {
    switch self {
    case .wireGuard:
      return "utun"
    case .openVpn:
      return "utun"
    case .ikev2:
      return "ipsec"
    }
  }
}

private struct SecureWaveSharedTunnelSnapshot {
  let state: String
  let lastError: String?
  let connectedSince: Date?
  let protocolType: SecureWaveAppleProtocol?
}

private struct SecureWaveStatusResolution {
  let state: String
  let protocolType: SecureWaveAppleProtocol?
  let lastError: String?
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
        connectedSince: nil,
        protocolType: nil
      )
    }

    let state = defaults.string(forKey: SecureWaveAppleKeys.lastState) ?? "disconnected"
    let error = defaults.string(forKey: SecureWaveAppleKeys.lastError)
    let timestamp = defaults.double(forKey: SecureWaveAppleKeys.connectedSince)
    let connectedSince = timestamp > 0
      ? Date(timeIntervalSince1970: timestamp)
      : nil
    let protocolType = defaults.string(forKey: SecureWaveAppleKeys.currentProtocol)
      .flatMap(SecureWaveAppleProtocol.init(rawValue:))
    return SecureWaveSharedTunnelSnapshot(
      state: state,
      lastError: error?.isEmpty == true ? nil : error,
      connectedSince: connectedSince,
      protocolType: protocolType
    )
  }

  func record(
    state: String,
    lastError: String?,
    connectedSince: Date?,
    protocolType: SecureWaveAppleProtocol?
  ) {
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
    if let protocolType {
      defaults.set(protocolType.rawValue, forKey: SecureWaveAppleKeys.currentProtocol)
    } else {
      defaults.removeObject(forKey: SecureWaveAppleKeys.currentProtocol)
    }
  }
}

private final class SecureWaveCredentialsStore {
  init(serviceName: String) {
    self.serviceName = serviceName
  }

  private let serviceName: String

  func persistentReference(for key: String, value: String) throws -> Data {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]

    SecItemDelete(query as CFDictionary)

    var addQuery = query
    addQuery[kSecValueData as String] = Data(value.utf8)
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw SecureWaveVPNManager.makeError(
        code: "vpn_connect_failed",
        message: "Unable to store VPN credentials in the Apple Keychain."
      )
    }

    var loadQuery = query
    loadQuery[kSecReturnPersistentRef as String] = kCFBooleanTrue
    loadQuery[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let copyStatus = SecItemCopyMatching(loadQuery as CFDictionary, &result)
    guard copyStatus == errSecSuccess, let data = result as? Data else {
      throw SecureWaveVPNManager.makeError(
        code: "vpn_connect_failed",
        message: "Unable to reference VPN credentials in the Apple Keychain."
      )
    }
    return data
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
    [
      SecureWaveAppleKeys.fieldProtocol: SecureWaveAppleProtocol.wireGuard.rawValue,
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
      SecureWaveAppleKeys.fieldPresharedKey: presharedKey as Any,
    ]
  }
}

private struct SecureWaveOpenVPNRequest {
  let serverAddress: String
  let ovpnConfig: String
  let username: String?
  let password: String?

  init(arguments: [String: Any]) throws {
    func optionalString(_ key: String) -> String? {
      let rawValue = arguments[key]
      let value = rawValue.map { String(describing: $0) }?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let value, !value.isEmpty {
        return value
      }
      return nil
    }

    guard let ovpnConfig =
      optionalString(SecureWaveAppleKeys.fieldOvpnConfig) ??
      optionalString("openvpn_config") else {
      throw SecureWaveVPNManager.makeError(
        code: "invalid_profile",
        message: "Missing OpenVPN configuration (ovpn_config)."
      )
    }

    let username = optionalString(SecureWaveAppleKeys.fieldUsername)
    let password = optionalString(SecureWaveAppleKeys.fieldPassword)
    if (username == nil) != (password == nil) {
      throw SecureWaveVPNManager.makeError(
        code: "invalid_profile",
        message: "OpenVPN credentials require both username and password when auth-user-pass is used."
      )
    }

    self.serverAddress =
      optionalString(SecureWaveAppleKeys.fieldServer) ??
      optionalString(SecureWaveAppleKeys.fieldEndpointHost) ??
      Self.remoteHost(from: ovpnConfig) ??
      "OpenVPN"
    self.ovpnConfig = ovpnConfig
    self.username = username
    self.password = password
  }

  func providerConfiguration(appGroupIdentifier: String) -> [String: Any] {
    [
      SecureWaveAppleKeys.fieldProtocol: SecureWaveAppleProtocol.openVpn.rawValue,
      SecureWaveAppleKeys.fieldServer: serverAddress,
      SecureWaveAppleKeys.fieldOvpnConfig: ovpnConfig,
      SecureWaveAppleKeys.appGroupInfoKey: appGroupIdentifier,
    ]
  }

  private static func remoteHost(from ovpnConfig: String) -> String? {
    for rawLine in ovpnConfig.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else {
        continue
      }
      let parts = line.split(whereSeparator: \.isWhitespace)
      guard parts.count >= 2, parts[0].lowercased() == "remote" else {
        continue
      }
      let host = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      if !host.isEmpty {
        return host
      }
    }
    return nil
  }
}

private struct SecureWaveIKEv2Request {
  let serverAddress: String
  let remoteIdentifier: String
  let localIdentifier: String?
  let username: String?
  let password: String?
  let authMethod: String
  let clientPkcs12Base64: String?
  let clientPkcs12Password: String?

  init(arguments: [String: Any]) throws {
    func optionalString(_ key: String) -> String? {
      let rawValue = arguments[key]
      let value = rawValue.map { String(describing: $0) }?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let value, !value.isEmpty {
        return value
      }
      return nil
    }

    guard let serverAddress = optionalString(SecureWaveAppleKeys.fieldServer) ??
      optionalString(SecureWaveAppleKeys.fieldEndpointHost) else {
      throw SecureWaveVPNManager.makeError(
        code: "invalid_profile",
        message: "Missing IKEv2 server endpoint."
      )
    }

    let authMethod = (optionalString(SecureWaveAppleKeys.fieldAuthMethod) ?? "eap-mschapv2")
      .lowercased()
    let username = optionalString(SecureWaveAppleKeys.fieldUsername)
    let password = optionalString(SecureWaveAppleKeys.fieldPassword)
    let clientPkcs12Base64 = optionalString(SecureWaveAppleKeys.fieldClientPkcs12Base64)
    let clientPkcs12Password = optionalString(SecureWaveAppleKeys.fieldClientPkcs12Password)

    switch authMethod {
    case "eap-mschapv2":
      guard let username, let password else {
        throw SecureWaveVPNManager.makeError(
          code: "invalid_profile",
          message: "IKEv2 EAP authentication requires username and password."
        )
      }
      self.username = username
      self.password = password
    case "eap-tls", "certificate":
      guard clientPkcs12Base64 != nil else {
        throw SecureWaveVPNManager.makeError(
          code: "invalid_profile",
          message: "IKEv2 certificate authentication requires client PKCS#12 material."
        )
      }
      self.username = username
      self.password = nil
    default:
      throw SecureWaveVPNManager.makeError(
        code: "invalid_profile",
        message: "Unsupported IKEv2 auth method '\(authMethod)'."
      )
    }

    self.serverAddress = serverAddress
    self.remoteIdentifier = optionalString(SecureWaveAppleKeys.fieldRemoteId) ?? serverAddress
    self.localIdentifier = optionalString(SecureWaveAppleKeys.fieldLocalId)
    self.authMethod = authMethod
    self.clientPkcs12Base64 = clientPkcs12Base64
    self.clientPkcs12Password = clientPkcs12Password
  }

  func configure(
    _ tunnelProtocol: NEVPNProtocolIKEv2,
    credentialsStore: SecureWaveCredentialsStore
  ) throws {
    tunnelProtocol.serverAddress = serverAddress
    tunnelProtocol.remoteIdentifier = remoteIdentifier
    if let localIdentifier, !localIdentifier.isEmpty {
      tunnelProtocol.localIdentifier = localIdentifier
    }
    tunnelProtocol.disconnectOnSleep = false
    tunnelProtocol.deadPeerDetectionRate = .medium
    tunnelProtocol.enablePFS = true

    switch authMethod {
    case "eap-mschapv2":
      guard let username, let password else {
        throw SecureWaveVPNManager.makeError(
          code: "invalid_profile",
          message: "IKEv2 EAP authentication requires username and password."
        )
      }
      tunnelProtocol.username = username
      tunnelProtocol.passwordReference = try credentialsStore.persistentReference(
        for: "\(SecureWaveAppleKeys.credentialService).ikev2.password",
        value: password
      )
      tunnelProtocol.authenticationMethod = .none
      tunnelProtocol.useExtendedAuthentication = true
    case "eap-tls", "certificate":
      guard let clientPkcs12Base64,
        let identityData = Data(base64Encoded: clientPkcs12Base64) else {
        throw SecureWaveVPNManager.makeError(
          code: "invalid_profile",
          message: "IKEv2 client PKCS#12 data is not valid base64."
        )
      }
      tunnelProtocol.identityData = identityData
      tunnelProtocol.identityDataPassword = clientPkcs12Password
      tunnelProtocol.authenticationMethod = .certificate
      tunnelProtocol.useExtendedAuthentication = false
      if let username, !username.isEmpty {
        tunnelProtocol.username = username
      }
    default:
      break
    }
  }
}

final class SecureWaveVPNManager {
  static let shared = SecureWaveVPNManager()

  private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "SecureWave",
    category: "apple_vpn_bridge"
  )
  private let credentialsStore = SecureWaveCredentialsStore(
    serviceName: SecureWaveAppleKeys.credentialService
  )
  private let openVpnRuntimeLinked = false
  private let openVpnInstallHint =
    "OpenVPN bridge is wired, but PacketTunnel is still using SecureWavePlaceholderOpenVPNEngine. Replace that placeholder with your licensed Apple OpenVPN runtime."

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
    let packetTunnelPreflight = packetTunnelPreflightError(
      extensionEmbedded: extensionEmbedded,
      appGroupConfigured: appGroupConfigured
    )
    let ikev2Preflight = ikev2PreflightError()

    loadManagers { [weak self] tunnelManager, tunnelError, ikev2Manager, ikev2Error in
      guard let self else {
        completion([
          "available": false,
          "extensionEmbedded": false,
          "appGroupConfigured": false,
          "tunnelManagerReady": false,
          "personalVpnReady": false,
          "supportedProtocols": [
            "wireguard": true,
            "openvpn": true,
            "ikev2": true,
          ],
          "protocolCapabilities": [
            "wireguard": [
              "supported": true,
              "runtimeAvailable": false,
              "reason": "VPN manager unavailable.",
            ],
            "openvpn": [
              "supported": true,
              "runtimeAvailable": false,
              "reason": "Apple OpenVPN runtime not linked",
            ],
            "ikev2": [
              "supported": true,
              "runtimeAvailable": false,
              "reason": "VPN manager unavailable.",
            ],
          ],
          "lastError": "VPN manager unavailable.",
        ])
        return
      }

      let snapshot = self.stateStore.snapshot()
      let packetTunnelReady = packetTunnelPreflight == nil && tunnelError == nil
      let wireGuardSupported = true
      let openVpnSupported = true
      let ikev2Supported = true
      let wireGuardRuntimeAvailable = packetTunnelReady
      let openVpnRuntimeAvailable = packetTunnelReady && self.openVpnRuntimeLinked
      let ikev2RuntimeAvailable = ikev2Preflight == nil && ikev2Error == nil
      let packetTunnelReason = self.preferredErrorText([
        packetTunnelPreflight?.localizedDescription,
        tunnelError?.localizedDescription,
        snapshot.lastError,
      ])
      let ikev2Reason = self.preferredErrorText([
        ikev2Preflight?.localizedDescription,
        ikev2Error?.localizedDescription,
        snapshot.lastError,
      ])
      let configuredProtocol =
        self.packetTunnelProtocol(for: tunnelManager, snapshot: snapshot) ??
        snapshot.protocolType
      let activeProtocol = self.activeProtocol(
        tunnelManager: tunnelManager,
        ikev2Manager: ikev2Manager,
        snapshot: snapshot
      )
      completion([
        "available": wireGuardRuntimeAvailable || openVpnRuntimeAvailable || ikev2RuntimeAvailable,
        "extensionEmbedded": extensionEmbedded,
        "appGroupConfigured": appGroupConfigured,
        "tunnelManagerReady": tunnelError == nil,
        "personalVpnReady": ikev2RuntimeAvailable,
        "appGroupIdentifier": self.appGroupIdentifier,
        "providerBundleIdentifier": self.providerBundleIdentifier,
        "openVpnRuntimeLinked": self.openVpnRuntimeLinked,
        "openVpnInstallHint": self.openVpnInstallHint,
        "supportedProtocols": [
          "wireguard": wireGuardSupported,
          "openvpn": openVpnSupported,
          "ikev2": ikev2Supported,
        ],
        "protocolCapabilities": [
          "wireguard": self.protocolCapabilityPayload(
            supported: wireGuardSupported,
            runtimeAvailable: wireGuardRuntimeAvailable,
            reason: wireGuardRuntimeAvailable ? nil : packetTunnelReason
          ),
          "openvpn": self.protocolCapabilityPayload(
            supported: openVpnSupported,
            runtimeAvailable: openVpnRuntimeAvailable,
            reason: openVpnRuntimeAvailable
              ? nil
              : (self.openVpnRuntimeLinked ? packetTunnelReason : "Apple OpenVPN runtime not linked")
          ),
          "ikev2": self.protocolCapabilityPayload(
            supported: ikev2Supported,
            runtimeAvailable: ikev2RuntimeAvailable,
            reason: ikev2RuntimeAvailable ? nil : ikev2Reason
          ),
        ],
        "configuredProtocol": configuredProtocol?.rawValue as Any,
        "activeProtocol": activeProtocol?.rawValue as Any,
        "lastError": self.preferredErrorText([
          snapshot.lastError,
          packetTunnelPreflight?.localizedDescription,
          tunnelError?.localizedDescription,
          ikev2Preflight?.localizedDescription,
          ikev2Error?.localizedDescription,
        ]) as Any,
      ])
    }
  }

  private func protocolCapabilityPayload(
    supported: Bool,
    runtimeAvailable: Bool,
    reason: String?
  ) -> [String: Any] {
    var payload: [String: Any] = [
      "supported": supported,
      "runtimeAvailable": runtimeAvailable,
    ]
    if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
      payload["reason"] = reason
    }
    return payload
  }

  func status(completion: @escaping ([String: Any]) -> Void) {
    let extensionEmbedded = embeddedPacketTunnelURL() != nil
    let appGroupConfigured = stateStore.isConfigured
    let packetTunnelPreflight = packetTunnelPreflightError(
      extensionEmbedded: extensionEmbedded,
      appGroupConfigured: appGroupConfigured
    )
    let ikev2Preflight = ikev2PreflightError()

    loadManagers { [weak self] tunnelManager, tunnelError, ikev2Manager, ikev2Error in
      guard let self else {
        completion([
          "state": "unavailable",
          "lastError": "VPN manager unavailable.",
          "rxBytes": 0,
          "txBytes": 0,
          "connectedSince": NSNull(),
          "protocol": NSNull(),
          "interface": NSNull(),
        ])
        return
      }

      let snapshot = self.stateStore.snapshot()
      let resolution = self.resolveStatus(
        tunnelManager: tunnelManager,
        tunnelError: tunnelError,
        packetTunnelPreflight: packetTunnelPreflight,
        ikev2Manager: ikev2Manager,
        ikev2Error: ikev2Error,
        ikev2Preflight: ikev2Preflight,
        snapshot: snapshot
      )
      let connectedSince = self.persistResolvedState(resolution, snapshot: snapshot)
      let counters = self.readUtunCounters()
      completion([
        "state": resolution.state,
        "lastError": resolution.lastError as Any,
        "rxBytes": counters.rx,
        "txBytes": counters.tx,
        "connectedSince": connectedSince?.timeIntervalSince1970 as Any,
        "protocol": resolution.protocolType?.rawValue as Any,
        "interface": (
          resolution.state == "connected" || resolution.state == "connecting"
        ) ? resolution.protocolType?.interfaceName as Any : NSNull(),
      ])
    }
  }

  func connectWireGuard(arguments: [String: Any], completion: @escaping (Error?) -> Void) {
    var payload = arguments
    payload[SecureWaveAppleKeys.fieldProtocol] = SecureWaveAppleProtocol.wireGuard.rawValue
    startVPN(arguments: payload, completion: completion)
  }

  func startVPN(arguments: [String: Any], completion: @escaping (Error?) -> Void) {
    do {
      let protocolType = try SecureWaveAppleProtocol(arguments: arguments)
      switch protocolType {
      case .wireGuard:
        startWireGuard(arguments: arguments, completion: completion)
      case .ikev2:
        startIkev2(arguments: arguments, completion: completion)
      case .openVpn:
        startOpenVpn(arguments: arguments, completion: completion)
      }
    } catch {
      let wrapped = (error as? NSError) ?? Self.makeError(
        code: "invalid_profile",
        message: error.localizedDescription
      )
      stateStore.record(
        state: "error",
        lastError: wrapped.localizedDescription,
        connectedSince: nil,
        protocolType: nil
      )
      completion(wrapped)
    }
  }

  func disconnect(completion: @escaping (Error?) -> Void) {
    let snapshot = stateStore.snapshot()
    stateStore.record(
      state: "disconnecting",
      lastError: nil,
      connectedSince: snapshot.connectedSince,
      protocolType: snapshot.protocolType
    )

    loadManagers { [weak self] tunnelManager, tunnelError, ikev2Manager, ikev2Error in
      guard let self else {
        completion(Self.makeError(code: "vpn_unavailable", message: "VPN manager unavailable."))
        return
      }

      if let tunnelError, let ikev2Error {
        let wrapped = self.wrap(
          tunnelError,
          code: "vpn_unavailable",
          operation: "loadManagers"
        )
        self.log.error("IKEv2 load failed: \(ikev2Error.localizedDescription, privacy: .public)")
        self.stateStore.record(
          state: "error",
          lastError: wrapped.localizedDescription,
          connectedSince: nil,
          protocolType: snapshot.protocolType
        )
        completion(wrapped)
        return
      }

      if let session = tunnelManager?.connection as? NETunnelProviderSession {
        session.stopTunnel()
      } else {
        tunnelManager?.connection.stopVPNTunnel()
      }
      ikev2Manager?.connection.stopVPNTunnel()
      completion(nil)
    }
  }

  func stopVPN(completion: @escaping (Error?) -> Void) {
    disconnect(completion: completion)
  }

  private func startWireGuard(arguments: [String: Any], completion: @escaping (Error?) -> Void) {
    do {
      let request = try SecureWaveWireGuardRequest(arguments: arguments)
      let extensionEmbedded = embeddedPacketTunnelURL() != nil
      let appGroupConfigured = stateStore.isConfigured
      if let preflight = packetTunnelPreflightError(
        extensionEmbedded: extensionEmbedded,
        appGroupConfigured: appGroupConfigured
      ) {
        stateStore.record(
          state: "unavailable",
          lastError: preflight.localizedDescription,
          connectedSince: nil,
          protocolType: .wireGuard
        )
        completion(preflight)
        return
      }

      stateStore.record(
        state: "connecting",
        lastError: nil,
        connectedSince: nil,
        protocolType: .wireGuard
      )
      loadPacketTunnelManager { [weak self] manager, loadError in
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
          self.stateStore.record(
            state: "error",
            lastError: wrapped.localizedDescription,
            connectedSince: nil,
            protocolType: .wireGuard
          )
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
            self.stateStore.record(
              state: "error",
              lastError: wrapped.localizedDescription,
              connectedSince: nil,
              protocolType: .wireGuard
            )
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
              self.stateStore.record(
                state: "error",
                lastError: wrapped.localizedDescription,
                connectedSince: nil,
                protocolType: .wireGuard
              )
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
              self.stateStore.record(
                state: "error",
                lastError: wrapped.localizedDescription,
                connectedSince: nil,
                protocolType: .wireGuard
              )
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
      stateStore.record(
        state: "error",
        lastError: wrapped.localizedDescription,
        connectedSince: nil,
        protocolType: .wireGuard
      )
      completion(wrapped)
    }
  }

  private func startOpenVpn(arguments: [String: Any], completion: @escaping (Error?) -> Void) {
    do {
      let request = try SecureWaveOpenVPNRequest(arguments: arguments)
      if let runtimeError = openVpnRuntimeGuardError(serverAddress: request.serverAddress) {
        stateStore.record(
          state: "error",
          lastError: runtimeError.localizedDescription,
          connectedSince: nil,
          protocolType: .openVpn
        )
        completion(runtimeError)
        return
      }
      let extensionEmbedded = embeddedPacketTunnelURL() != nil
      let appGroupConfigured = stateStore.isConfigured
      if let preflight = packetTunnelPreflightError(
        extensionEmbedded: extensionEmbedded,
        appGroupConfigured: appGroupConfigured
      ) {
        stateStore.record(
          state: "unavailable",
          lastError: preflight.localizedDescription,
          connectedSince: nil,
          protocolType: .openVpn
        )
        completion(preflight)
        return
      }

      stateStore.record(
        state: "connecting",
        lastError: nil,
        connectedSince: nil,
        protocolType: .openVpn
      )
      loadPacketTunnelManager { [weak self] manager, loadError in
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
          self.stateStore.record(
            state: "error",
            lastError: wrapped.localizedDescription,
            connectedSince: nil,
            protocolType: .openVpn
          )
          completion(wrapped)
          return
        }

        let tunnelManager = manager ?? NETunnelProviderManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = self.providerBundleIdentifier
        tunnelProtocol.serverAddress = request.serverAddress
        tunnelProtocol.providerConfiguration = request.providerConfiguration(
          appGroupIdentifier: self.appGroupIdentifier
        )
        if let username = request.username {
          tunnelProtocol.username = username
        }
        if let password = request.password {
          do {
            tunnelProtocol.passwordReference = try self.credentialsStore.persistentReference(
              for: "\(SecureWaveAppleKeys.credentialService).openvpn.password",
              value: password
            )
          } catch {
            let wrapped = (error as? NSError) ?? Self.makeError(
              code: "vpn_connect_failed",
              message: error.localizedDescription
            )
            self.stateStore.record(
              state: "error",
              lastError: wrapped.localizedDescription,
              connectedSince: nil,
              protocolType: .openVpn
            )
            completion(wrapped)
            return
          }
        }

        tunnelManager.protocolConfiguration = tunnelProtocol
        tunnelManager.localizedDescription = "SecureWave OpenVPN"
        tunnelManager.isEnabled = true

        tunnelManager.saveToPreferences { error in
          if let error {
            let wrapped = self.wrap(
              error,
              code: "vpn_permission_required",
              operation: "saveToPreferences"
            )
            self.stateStore.record(
              state: "error",
              lastError: wrapped.localizedDescription,
              connectedSince: nil,
              protocolType: .openVpn
            )
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
              self.stateStore.record(
                state: "error",
                lastError: wrapped.localizedDescription,
                connectedSince: nil,
                protocolType: .openVpn
              )
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
              self.stateStore.record(
                state: "error",
                lastError: wrapped.localizedDescription,
                connectedSince: nil,
                protocolType: .openVpn
              )
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
      stateStore.record(
        state: "error",
        lastError: wrapped.localizedDescription,
        connectedSince: nil,
        protocolType: .openVpn
      )
      completion(wrapped)
    }
  }

  private func startIkev2(arguments: [String: Any], completion: @escaping (Error?) -> Void) {
    do {
      let request = try SecureWaveIKEv2Request(arguments: arguments)
      if let preflight = ikev2PreflightError() {
        stateStore.record(
          state: "unavailable",
          lastError: preflight.localizedDescription,
          connectedSince: nil,
          protocolType: .ikev2
        )
        completion(preflight)
        return
      }

      stateStore.record(
        state: "connecting",
        lastError: nil,
        connectedSince: nil,
        protocolType: .ikev2
      )
      loadIkev2Manager { [weak self] manager, loadError in
        guard let self else {
          completion(Self.makeError(code: "vpn_unavailable", message: "VPN manager unavailable."))
          return
        }
        if let loadError {
          let wrapped = self.wrap(
            loadError,
            code: "vpn_unavailable",
            operation: "loadFromPreferences"
          )
          self.stateStore.record(
            state: "error",
            lastError: wrapped.localizedDescription,
            connectedSince: nil,
            protocolType: .ikev2
          )
          completion(wrapped)
          return
        }

        let vpnManager = manager ?? NEVPNManager.shared()
        let tunnelProtocol = NEVPNProtocolIKEv2()
        do {
          try request.configure(tunnelProtocol, credentialsStore: self.credentialsStore)
        } catch {
          let wrapped = (error as? NSError) ?? Self.makeError(
            code: "invalid_profile",
            message: error.localizedDescription
          )
          self.stateStore.record(
            state: "error",
            lastError: wrapped.localizedDescription,
            connectedSince: nil,
            protocolType: .ikev2
          )
          completion(wrapped)
          return
        }

        vpnManager.protocolConfiguration = tunnelProtocol
        vpnManager.localizedDescription = "SecureWave IKEv2"
        vpnManager.isOnDemandEnabled = false
        vpnManager.isEnabled = true

        vpnManager.saveToPreferences { error in
          if let error {
            let wrapped = self.wrap(
              error,
              code: "vpn_permission_required",
              operation: "saveToPreferences"
            )
            self.stateStore.record(
              state: "error",
              lastError: wrapped.localizedDescription,
              connectedSince: nil,
              protocolType: .ikev2
            )
            completion(wrapped)
            return
          }

          vpnManager.loadFromPreferences { error in
            if let error {
              let wrapped = self.wrap(
                error,
                code: "vpn_permission_required",
                operation: "loadFromPreferences"
              )
              self.stateStore.record(
                state: "error",
                lastError: wrapped.localizedDescription,
                connectedSince: nil,
                protocolType: .ikev2
              )
              completion(wrapped)
              return
            }

            do {
              try vpnManager.connection.startVPNTunnel()
              completion(nil)
            } catch {
              let wrapped = self.wrap(
                error,
                code: "vpn_connect_failed",
                operation: "startVPNTunnel"
              )
              self.stateStore.record(
                state: "error",
                lastError: wrapped.localizedDescription,
                connectedSince: nil,
                protocolType: .ikev2
              )
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
      stateStore.record(
        state: "error",
        lastError: wrapped.localizedDescription,
        connectedSince: nil,
        protocolType: .ikev2
      )
      completion(wrapped)
    }
  }

  private func loadManagers(
    completion: @escaping (NETunnelProviderManager?, Error?, NEVPNManager?, Error?) -> Void
  ) {
    loadPacketTunnelManager { [weak self] tunnelManager, tunnelError in
      guard let self else {
        completion(nil, Self.makeError(code: "vpn_unavailable", message: "VPN manager unavailable."), nil, Self.makeError(code: "vpn_unavailable", message: "VPN manager unavailable."))
        return
      }
      self.loadIkev2Manager { ikev2Manager, ikev2Error in
        completion(tunnelManager, tunnelError, ikev2Manager, ikev2Error)
      }
    }
  }

  private func loadPacketTunnelManager(
    completion: @escaping (NETunnelProviderManager?, Error?) -> Void
  ) {
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

  private func loadIkev2Manager(completion: @escaping (NEVPNManager?, Error?) -> Void) {
    let manager = NEVPNManager.shared()
    manager.loadFromPreferences { error in
      if let error {
        completion(nil, error)
      } else {
        completion(manager, nil)
      }
    }
  }

  private func openVpnRuntimeGuardError(serverAddress: String) -> NSError? {
    guard !openVpnRuntimeLinked else {
      return nil
    }
    log.error(
      "[APPLE_VPN] {\"event\":\"openvpn_runtime_blocked\",\"server\":\"\(serverAddress, privacy: .public)\",\"runtimeLinked\":false}"
    )
    return Self.makeError(
      code: "OPENVPN_RUNTIME_NOT_LINKED",
      message: openVpnInstallHint
    )
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

  private func packetTunnelPreflightError(
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

  private func ikev2PreflightError() -> NSError? {
    #if targetEnvironment(simulator)
    return Self.makeError(
      code: "vpn_unavailable",
      message: "VPN requires a physical Apple device. Personal VPN is unavailable on Simulator."
    )
    #else
    return nil
    #endif
  }

  private func resolveStatus(
    tunnelManager: NETunnelProviderManager?,
    tunnelError: Error?,
    packetTunnelPreflight: Error?,
    ikev2Manager: NEVPNManager?,
    ikev2Error: Error?,
    ikev2Preflight: Error?,
    snapshot: SecureWaveSharedTunnelSnapshot
  ) -> SecureWaveStatusResolution {
    if let state = managerState(for: tunnelManager), state != "disconnected" {
      let protocolType = packetTunnelProtocol(for: tunnelManager, snapshot: snapshot) ?? .wireGuard
      return SecureWaveStatusResolution(
        state: state,
        protocolType: protocolType,
        lastError: state == "error"
          ? preferredErrorText([
              snapshot.lastError,
              packetTunnelPreflight?.localizedDescription,
              tunnelError?.localizedDescription,
            ])
          : nil
      )
    }

    if let state = managerState(for: ikev2Manager), state != "disconnected" {
      return SecureWaveStatusResolution(
        state: state,
        protocolType: .ikev2,
        lastError: state == "error"
          ? preferredErrorText([
              snapshot.lastError,
              ikev2Preflight?.localizedDescription,
              ikev2Error?.localizedDescription,
            ])
          : nil
      )
    }

    switch snapshot.state {
    case "connecting", "disconnecting", "error", "unavailable":
      return SecureWaveStatusResolution(
        state: snapshot.state,
        protocolType: snapshot.protocolType,
        lastError: snapshot.lastError
      )
    default:
      break
    }

    let packetTunnelReady = packetTunnelPreflight == nil && tunnelError == nil
    let ikev2Supported = ikev2Preflight == nil && ikev2Error == nil
    if !packetTunnelReady && !ikev2Supported {
      return SecureWaveStatusResolution(
        state: "unavailable",
        protocolType: snapshot.protocolType,
        lastError: preferredErrorText([
          snapshot.lastError,
          packetTunnelPreflight?.localizedDescription,
          tunnelError?.localizedDescription,
          ikev2Preflight?.localizedDescription,
          ikev2Error?.localizedDescription,
        ])
      )
    }

    return SecureWaveStatusResolution(
      state: "disconnected",
      protocolType: snapshot.protocolType,
      lastError: nil
    )
  }

  private func managerState(for manager: NEVPNManager?) -> String? {
    guard let manager else { return nil }
    switch manager.connection.status {
    case .connected, .reasserting:
      return "connected"
    case .connecting:
      return "connecting"
    case .disconnecting:
      return "disconnecting"
    case .invalid:
      return "error"
    case .disconnected:
      return "disconnected"
    @unknown default:
      return "disconnected"
    }
  }

  private func activeProtocol(
    tunnelManager: NETunnelProviderManager?,
    ikev2Manager: NEVPNManager?,
    snapshot: SecureWaveSharedTunnelSnapshot
  ) -> SecureWaveAppleProtocol? {
    if let state = managerState(for: tunnelManager), isLiveConnectionState(state) {
      return packetTunnelProtocol(for: tunnelManager, snapshot: snapshot) ?? .wireGuard
    }
    if let state = managerState(for: ikev2Manager), isLiveConnectionState(state) {
      return .ikev2
    }
    if ["connecting", "disconnecting", "error"].contains(snapshot.state) {
      return snapshot.protocolType
    }
    return nil
  }

  private func isLiveConnectionState(_ state: String) -> Bool {
    state == "connected" || state == "connecting" || state == "disconnecting"
  }

  private func packetTunnelProtocol(
    for manager: NETunnelProviderManager?,
    snapshot: SecureWaveSharedTunnelSnapshot
  ) -> SecureWaveAppleProtocol? {
    let configured =
      ((manager?.protocolConfiguration as? NETunnelProviderProtocol)?
        .providerConfiguration?[SecureWaveAppleKeys.fieldProtocol] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if let configured, let value = SecureWaveAppleProtocol(rawValue: configured) {
      return value
    }
    switch snapshot.protocolType {
    case .wireGuard, .openVpn:
      return snapshot.protocolType
    default:
      return manager == nil ? nil : .wireGuard
    }
  }

  private func preferredErrorText(_ values: [String?]) -> String? {
    values
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }

  @discardableResult
  private func persistResolvedState(
    _ resolution: SecureWaveStatusResolution,
    snapshot: SecureWaveSharedTunnelSnapshot
  ) -> Date? {
    let persistedProtocol = resolution.protocolType ?? snapshot.protocolType
    switch resolution.state {
    case "connected":
      let connectedSince = snapshot.connectedSince ?? Date()
      if snapshot.state != "connected" ||
        snapshot.connectedSince == nil ||
        snapshot.protocolType != persistedProtocol ||
        snapshot.lastError != nil {
        stateStore.record(
          state: "connected",
          lastError: nil,
          connectedSince: connectedSince,
          protocolType: persistedProtocol
        )
      }
      return connectedSince
    case "connecting", "disconnecting":
      if snapshot.state != resolution.state || snapshot.protocolType != persistedProtocol {
        stateStore.record(
          state: resolution.state,
          lastError: nil,
          connectedSince: snapshot.connectedSince,
          protocolType: persistedProtocol
        )
      }
      return snapshot.connectedSince
    case "error", "unavailable":
      if snapshot.state != resolution.state ||
        snapshot.protocolType != persistedProtocol ||
        snapshot.lastError != resolution.lastError {
        stateStore.record(
          state: resolution.state,
          lastError: resolution.lastError,
          connectedSince: nil,
          protocolType: persistedProtocol
        )
      }
      return nil
    default:
      if snapshot.state != "disconnected" ||
        snapshot.protocolType != persistedProtocol ||
        snapshot.lastError != nil ||
        snapshot.connectedSince != nil {
        stateStore.record(
          state: "disconnected",
          lastError: nil,
          connectedSince: nil,
          protocolType: persistedProtocol
        )
      }
      return nil
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
      message = "Network Extension rejected the VPN operation. Check signing, entitlements, and Apple VPN capabilities for this target."
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
