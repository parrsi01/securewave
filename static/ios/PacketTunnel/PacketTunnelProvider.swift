import Darwin
import Foundation
import NetworkExtension
import os

#if canImport(WireGuardKitGo)
import WireGuardKitGo
#endif

#if canImport(WireGuardKitC)
import WireGuardKitC
#endif

#if canImport(WireGuardKit)
import WireGuardKit
#endif

class PacketTunnelProvider: NEPacketTunnelProvider {
  private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SecureWave.PacketTunnel", category: "vpn")
  private var appGroupIdentifier: String {
    if let configured = (Bundle.main.object(forInfoDictionaryKey: "SecureWaveAppGroupIdentifier") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !configured.isEmpty {
      return configured
    }
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.securewaveApp.PacketTunnel"
    let baseBundleIdentifier = bundleIdentifier.replacingOccurrences(of: ".PacketTunnel", with: "")
    return "group.\(baseBundleIdentifier).shared"
  }

  #if canImport(WireGuardKit)
  private var adapter: WireGuardAdapter?
  #endif

  override func startTunnel(options: [String : NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
    log.log("startTunnel called")
    guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
          let providerConfiguration = tunnelProtocol.providerConfiguration,
          let config = buildWireGuardConfig(from: providerConfiguration) else {
      let error = NSError(
        domain: "SecureWave",
        code: -10,
        userInfo: [NSLocalizedDescriptionKey: "Missing WireGuard configuration."]
      )
      persistStatus(state: "error", lastError: error.localizedDescription, connectedSince: 0)
      log.error("startTunnel aborted: missing config")
      completionHandler(error)
      return
    }
    persistStatus(state: "connecting", lastError: nil, connectedSince: 0)

    #if canImport(WireGuardKit)
    do {
      let tunnelConfig = try TunnelConfiguration(fromWgQuickConfig: config, called: "SecureWave")
      let adapter = WireGuardAdapter(with: self) { [weak self] level, message in
        guard let self else { return }
        switch level {
        case .verbose:
          self.log.debug("WireGuard: \(message, privacy: .public)")
        case .error:
          self.log.error("WireGuard: \(message, privacy: .public)")
        }
      }
      self.adapter = adapter
      adapter.start(tunnelConfiguration: tunnelConfig) { [weak self] error in
        if let error {
          self?.persistStatus(state: "error", lastError: error.localizedDescription, connectedSince: 0)
          self?.log.error("WireGuardAdapter.start failed: \(String(describing: error), privacy: .public)")
          completionHandler(error)
        } else {
          let connectedSince = Int(Date().timeIntervalSince1970)
          self?.persistStatus(state: "connected", lastError: nil, connectedSince: connectedSince)
          self?.log.log("tunnel started")
          completionHandler(nil)
        }
      }
    } catch let parseError as TunnelConfiguration.ParseError {
      let message: String
      switch parseError {
      case .noInterface:
        message = "Invalid WireGuard configuration: missing [Interface] section."
      case .multipleInterfaces:
        message = "Invalid WireGuard configuration: multiple [Interface] sections."
      case .interfaceHasNoPrivateKey:
        message = "Invalid WireGuard configuration: missing PrivateKey."
      case .interfaceHasInvalidPrivateKey:
        message = "Invalid WireGuard configuration: invalid PrivateKey."
      case .interfaceHasInvalidListenPort:
        message = "Invalid WireGuard configuration: invalid ListenPort."
      case .interfaceHasInvalidAddress:
        message = "Invalid WireGuard configuration: invalid Address."
      case .interfaceHasInvalidDNS:
        message = "Invalid WireGuard configuration: invalid DNS."
      case .interfaceHasInvalidMTU:
        message = "Invalid WireGuard configuration: invalid MTU."
      case .interfaceHasUnrecognizedKey:
        message = "Invalid WireGuard configuration: unrecognized key in [Interface]."
      case .peerHasNoPublicKey:
        message = "Invalid WireGuard configuration: missing PublicKey in [Peer]."
      case .peerHasInvalidPublicKey:
        message = "Invalid WireGuard configuration: invalid PublicKey in [Peer]."
      case .peerHasInvalidPreSharedKey:
        message = "Invalid WireGuard configuration: invalid PresharedKey in [Peer]."
      case .peerHasInvalidAllowedIP:
        message = "Invalid WireGuard configuration: invalid AllowedIPs in [Peer]."
      case .peerHasInvalidEndpoint:
        message = "Invalid WireGuard configuration: invalid Endpoint in [Peer]."
      case .peerHasInvalidPersistentKeepAlive:
        message = "Invalid WireGuard configuration: invalid PersistentKeepalive in [Peer]."
      case .peerHasUnrecognizedKey:
        message = "Invalid WireGuard configuration: unrecognized key in [Peer]."
      case .multiplePeersWithSamePublicKey:
        message = "Invalid WireGuard configuration: duplicate peer PublicKey entries."
      case .multipleEntriesForKey:
        message = "Invalid WireGuard configuration: multiple entries for a single-value key."
      case .invalidLine:
        message = "Invalid WireGuard configuration: invalid line."
      }
      persistStatus(state: "error", lastError: message, connectedSince: 0)
      log.error("configuration parse failed: \(message, privacy: .public)")
      completionHandler(NSError(domain: "SecureWave", code: -12, userInfo: [NSLocalizedDescriptionKey: message]))
    } catch {
      persistStatus(state: "error", lastError: "Failed to start tunnel.", connectedSince: 0)
      log.error("startTunnel failed: unexpected error")
      completionHandler(NSError(domain: "SecureWave", code: -13, userInfo: [NSLocalizedDescriptionKey: "Failed to start tunnel."]))
    }
    #else
    persistStatus(state: "error", lastError: "WireGuardKit is not linked. Add the package in Xcode.", connectedSince: 0)
    log.error("startTunnel aborted: WireGuardKit is not linked")
    completionHandler(NSError(domain: "SecureWave", code: -11, userInfo: [NSLocalizedDescriptionKey: "WireGuardKit is not linked. Add the package in Xcode."]))
    #endif
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    persistStatus(state: "disconnecting", lastError: nil, connectedSince: readConnectedSince())
    #if canImport(WireGuardKit)
    log.log("stopTunnel called: reason=\(reason.rawValue, privacy: .public)")
    adapter?.stop { [weak self] _ in
      self?.persistStatus(state: "disconnected", lastError: nil, connectedSince: 0)
      self?.log.log("tunnel stopped")
      completionHandler()
    }
    adapter = nil
    #else
    persistStatus(state: "disconnected", lastError: nil, connectedSince: 0)
    log.log("stopTunnel called (no WireGuardKit linked)")
    completionHandler()
    #endif
  }

  override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
    guard let request = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
          (request["action"] as? String) == "status" else {
      completionHandler?(nil)
      return
    }
    let payload = statusPayload()
    let response = try? JSONSerialization.data(withJSONObject: payload)
    completionHandler?(response)
  }

  private func buildWireGuardConfig(from providerConfiguration: [String: Any]) -> String? {
    if let wgQuickConfig = providerConfiguration["wgQuickConfig"] as? String,
       !wgQuickConfig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return wgQuickConfig
    }

    let endpointHost = (providerConfiguration["endpointHost"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let endpointPort: Int
    if let intPort = providerConfiguration["endpointPort"] as? Int {
      endpointPort = intPort
    } else if let textPort = providerConfiguration["endpointPort"] as? String,
              let parsed = Int(textPort) {
      endpointPort = parsed
    } else {
      endpointPort = 0
    }
    let privateKey = (providerConfiguration["clientPrivateKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let addressCidr = (providerConfiguration["addressCidr"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let serverPublicKey = (providerConfiguration["serverPublicKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if endpointHost.isEmpty || endpointPort <= 0 || privateKey.isEmpty || addressCidr.isEmpty || serverPublicKey.isEmpty {
      return nil
    }

    let dns = (providerConfiguration["dns"] as? [String] ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let allowedIps = (providerConfiguration["allowedIps"] as? [String] ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let keepalive: Int
    if let intKeepalive = providerConfiguration["keepaliveSeconds"] as? Int {
      keepalive = intKeepalive
    } else if let textKeepalive = providerConfiguration["keepaliveSeconds"] as? String,
              let parsed = Int(textKeepalive) {
      keepalive = parsed
    } else {
      keepalive = 0
    }
    let presharedKey = (providerConfiguration["presharedKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    var lines = [
      "[Interface]",
      "PrivateKey = \(privateKey)",
      "Address = \(addressCidr)",
    ]
    if !dns.isEmpty {
      lines.append("DNS = \(dns.joined(separator: ", "))")
    }
    lines.append("")
    lines.append("[Peer]")
    lines.append("PublicKey = \(serverPublicKey)")
    if !presharedKey.isEmpty {
      lines.append("PresharedKey = \(presharedKey)")
    }
    lines.append("AllowedIPs = \(allowedIps.isEmpty ? "0.0.0.0/0, ::/0" : allowedIps.joined(separator: ", "))")
    let endpointHostLiteral =
      endpointHost.contains(":") && !endpointHost.hasPrefix("[")
      ? "[\(endpointHost)]"
      : endpointHost
    lines.append("Endpoint = \(endpointHostLiteral):\(endpointPort)")
    if keepalive > 0 {
      lines.append("PersistentKeepalive = \(keepalive)")
    }
    return lines.joined(separator: "\n")
  }

  private func statusPayload() -> [String: Any] {
    let stats = readUtunCounters()
    let connectedSince = readConnectedSince()
    return [
      "state": readState(),
      "lastError": readLastError() as Any,
      "rxBytes": Int(stats.rx),
      "txBytes": Int(stats.tx),
      "connectedSince": connectedSince,
    ]
  }

  private func persistStatus(state: String, lastError: String?, connectedSince: Int) {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
    defaults.set(state, forKey: SecureWaveSharedState.stateKey)
    if let lastError, !lastError.isEmpty {
      defaults.set(lastError, forKey: SecureWaveSharedState.lastErrorKey)
    } else {
      defaults.removeObject(forKey: SecureWaveSharedState.lastErrorKey)
    }
    let stats = readUtunCounters()
    defaults.set(Int(stats.rx), forKey: SecureWaveSharedState.rxBytesKey)
    defaults.set(Int(stats.tx), forKey: SecureWaveSharedState.txBytesKey)
    defaults.set(connectedSince, forKey: SecureWaveSharedState.connectedSinceKey)
  }

  private func readState() -> String {
    UserDefaults(suiteName: appGroupIdentifier)?
      .string(forKey: SecureWaveSharedState.stateKey) ?? "disconnected"
  }

  private func readLastError() -> String? {
    UserDefaults(suiteName: appGroupIdentifier)?
      .string(forKey: SecureWaveSharedState.lastErrorKey)
  }

  private func readConnectedSince() -> Int {
    UserDefaults(suiteName: appGroupIdentifier)?
      .integer(forKey: SecureWaveSharedState.connectedSinceKey) ?? 0
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
}

enum SecureWaveSharedState {
  static let stateKey = "securewave.apple.state"
  static let lastErrorKey = "securewave.apple.lastError"
  static let rxBytesKey = "securewave.apple.rxBytes"
  static let txBytesKey = "securewave.apple.txBytes"
  static let connectedSinceKey = "securewave.apple.connectedSince"
}

#if canImport(WireGuardKit)
private extension String {
  func splitToArray(separator: Character = ",", trimmingCharacters: CharacterSet? = nil) -> [String] {
    return split(separator: separator)
      .map {
        if let charSet = trimmingCharacters {
          return $0.trimmingCharacters(in: charSet)
        } else {
          return String($0)
        }
      }
  }
}

private extension Optional where Wrapped == String {
  func splitToArray(separator: Character = ",", trimmingCharacters: CharacterSet? = nil) -> [String] {
    switch self {
    case .none:
      return []
    case .some(let wrapped):
      return wrapped.splitToArray(separator: separator, trimmingCharacters: trimmingCharacters)
    }
  }
}

extension TunnelConfiguration {
  enum ParserState {
    case inInterfaceSection
    case inPeerSection
    case notInASection
  }

  enum ParseError: Error {
    case invalidLine(String.SubSequence)
    case noInterface
    case multipleInterfaces
    case interfaceHasNoPrivateKey
    case interfaceHasInvalidPrivateKey(String)
    case interfaceHasInvalidListenPort(String)
    case interfaceHasInvalidAddress(String)
    case interfaceHasInvalidDNS(String)
    case interfaceHasInvalidMTU(String)
    case interfaceHasUnrecognizedKey(String)
    case peerHasNoPublicKey
    case peerHasInvalidPublicKey(String)
    case peerHasInvalidPreSharedKey(String)
    case peerHasInvalidAllowedIP(String)
    case peerHasInvalidEndpoint(String)
    case peerHasInvalidPersistentKeepAlive(String)
    case peerHasUnrecognizedKey(String)
    case multiplePeersWithSamePublicKey
    case multipleEntriesForKey(String)
  }

  convenience init(fromWgQuickConfig wgQuickConfig: String, called name: String? = nil) throws {
    var interfaceConfiguration: InterfaceConfiguration?
    var peerConfigurations = [PeerConfiguration]()

    let lines = wgQuickConfig.split { $0.isNewline }

    var parserState = ParserState.notInASection
    var attributes = [String: String]()

    for (lineIndex, line) in lines.enumerated() {
      var trimmedLine: String
      if let commentRange = line.range(of: "#") {
        trimmedLine = String(line[..<commentRange.lowerBound])
      } else {
        trimmedLine = String(line)
      }

      trimmedLine = trimmedLine.trimmingCharacters(in: .whitespacesAndNewlines)
      let lowercasedLine = trimmedLine.lowercased()

      if !trimmedLine.isEmpty {
        if let equalsIndex = trimmedLine.firstIndex(of: "=") {
          // Line contains an attribute
          let keyWithCase = trimmedLine[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
          let key = keyWithCase.lowercased()
          let value = trimmedLine[trimmedLine.index(equalsIndex, offsetBy: 1)...].trimmingCharacters(in: .whitespacesAndNewlines)
          let keysWithMultipleEntriesAllowed: Set<String> = ["address", "allowedips", "dns"]
          if let presentValue = attributes[key] {
            if keysWithMultipleEntriesAllowed.contains(key) {
              attributes[key] = presentValue + "," + value
            } else {
              throw ParseError.multipleEntriesForKey(keyWithCase)
            }
          } else {
            attributes[key] = value
          }
          let interfaceSectionKeys: Set<String> = ["privatekey", "listenport", "address", "dns", "mtu"]
          let peerSectionKeys: Set<String> = ["publickey", "presharedkey", "allowedips", "endpoint", "persistentkeepalive"]
          if parserState == .inInterfaceSection {
            guard interfaceSectionKeys.contains(key) else {
              throw ParseError.interfaceHasUnrecognizedKey(keyWithCase)
            }
          } else if parserState == .inPeerSection {
            guard peerSectionKeys.contains(key) else {
              throw ParseError.peerHasUnrecognizedKey(keyWithCase)
            }
          }
        } else if lowercasedLine != "[interface]" && lowercasedLine != "[peer]" {
          throw ParseError.invalidLine(line)
        }
      }

      let isLastLine = lineIndex == lines.count - 1

      if isLastLine || lowercasedLine == "[interface]" || lowercasedLine == "[peer]" {
        // Previous section has ended; process the attributes collected so far
        if parserState == .inInterfaceSection {
          let interface = try TunnelConfiguration.collate(interfaceAttributes: attributes)
          guard interfaceConfiguration == nil else { throw ParseError.multipleInterfaces }
          interfaceConfiguration = interface
        } else if parserState == .inPeerSection {
          let peer = try TunnelConfiguration.collate(peerAttributes: attributes)
          peerConfigurations.append(peer)
        }
      }

      if lowercasedLine == "[interface]" {
        parserState = .inInterfaceSection
        attributes.removeAll()
      } else if lowercasedLine == "[peer]" {
        parserState = .inPeerSection
        attributes.removeAll()
      }
    }

    let peerPublicKeysArray = peerConfigurations.map { $0.publicKey }
    let peerPublicKeysSet = Set<PublicKey>(peerPublicKeysArray)
    if peerPublicKeysArray.count != peerPublicKeysSet.count {
      throw ParseError.multiplePeersWithSamePublicKey
    }

    if let interfaceConfiguration = interfaceConfiguration {
      self.init(name: name, interface: interfaceConfiguration, peers: peerConfigurations)
    } else {
      throw ParseError.noInterface
    }
  }

  private static func collate(interfaceAttributes attributes: [String: String]) throws -> InterfaceConfiguration {
    guard let privateKeyString = attributes["privatekey"] else {
      throw ParseError.interfaceHasNoPrivateKey
    }
    guard let privateKey = PrivateKey(base64Key: privateKeyString) else {
      throw ParseError.interfaceHasInvalidPrivateKey(privateKeyString)
    }
    var interface = InterfaceConfiguration(privateKey: privateKey)
    if let listenPortString = attributes["listenport"] {
      guard let listenPort = UInt16(listenPortString) else {
        throw ParseError.interfaceHasInvalidListenPort(listenPortString)
      }
      interface.listenPort = listenPort
    }
    if let addressesString = attributes["address"] {
      var addresses = [IPAddressRange]()
      for addressString in addressesString.splitToArray(trimmingCharacters: .whitespacesAndNewlines) {
        guard let address = IPAddressRange(from: addressString) else {
          throw ParseError.interfaceHasInvalidAddress(addressString)
        }
        addresses.append(address)
      }
      interface.addresses = addresses
    }
    if let dnsString = attributes["dns"] {
      var dnsServers = [DNSServer]()
      var dnsSearch = [String]()
      for dnsServerString in dnsString.splitToArray(trimmingCharacters: .whitespacesAndNewlines) {
        if let dnsServer = DNSServer(from: dnsServerString) {
          dnsServers.append(dnsServer)
        } else {
          dnsSearch.append(dnsServerString)
        }
      }
      interface.dns = dnsServers
      interface.dnsSearch = dnsSearch
    }
    if let mtuString = attributes["mtu"] {
      guard let mtu = UInt16(mtuString) else {
        throw ParseError.interfaceHasInvalidMTU(mtuString)
      }
      interface.mtu = mtu
    }
    return interface
  }

  private static func collate(peerAttributes attributes: [String: String]) throws -> PeerConfiguration {
    guard let publicKeyString = attributes["publickey"] else {
      throw ParseError.peerHasNoPublicKey
    }
    guard let publicKey = PublicKey(base64Key: publicKeyString) else {
      throw ParseError.peerHasInvalidPublicKey(publicKeyString)
    }
    var peer = PeerConfiguration(publicKey: publicKey)
    if let preSharedKeyString = attributes["presharedkey"] {
      guard let preSharedKey = PreSharedKey(base64Key: preSharedKeyString) else {
        throw ParseError.peerHasInvalidPreSharedKey(preSharedKeyString)
      }
      peer.preSharedKey = preSharedKey
    }
    if let allowedIPsString = attributes["allowedips"] {
      var allowedIPs = [IPAddressRange]()
      for allowedIPString in allowedIPsString.splitToArray(trimmingCharacters: .whitespacesAndNewlines) {
        guard let allowedIP = IPAddressRange(from: allowedIPString) else {
          throw ParseError.peerHasInvalidAllowedIP(allowedIPString)
        }
        allowedIPs.append(allowedIP)
      }
      peer.allowedIPs = allowedIPs
    }
    if let endpointString = attributes["endpoint"] {
      guard let endpoint = Endpoint(from: endpointString) else {
        throw ParseError.peerHasInvalidEndpoint(endpointString)
      }
      peer.endpoint = endpoint
    }
    if let persistentKeepAliveString = attributes["persistentkeepalive"] {
      guard let persistentKeepAlive = UInt16(persistentKeepAliveString) else {
        throw ParseError.peerHasInvalidPersistentKeepAlive(persistentKeepAliveString)
      }
      peer.persistentKeepAlive = persistentKeepAlive
    }
    return peer
  }
}
#endif
