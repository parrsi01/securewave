// PacketTunnelProvider.swift  (apple/ios/SecureWavePacketTunnel/)
//
// Canonical reference copy for Apple review.
// The production implementation lives at:
//   securewave_app/ios/PacketTunnel/PacketTunnelProvider.swift
//
// This file mirrors that implementation and documents it for reviewers.
// Do not modify independently — keep in sync with the production file.
//
// Architecture:
//   Flutter host app  →  MethodChannel (securewave/vpn_platform_bridge)
//   → SecureWaveVPNManager (ios/Runner/VPNManager.swift)
//   → NETunnelProviderManager  →  [this extension process]
//   → WireGuardKit (WireGuardAdapter)
//   → utun interface  →  SecureWave WireGuard gateway

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

// MARK: - Shared State Keys

/// Keys used to share tunnel state via App Group UserDefaults between
/// the extension process and the host app process.
enum SecureWaveSharedState {
    static let stateKey         = "securewave.apple.state"
    static let lastErrorKey     = "securewave.apple.lastError"
    static let rxBytesKey       = "securewave.apple.rxBytes"
    static let txBytesKey       = "securewave.apple.txBytes"
    static let connectedSinceKey = "securewave.apple.connectedSince"
}

// MARK: - PacketTunnelProvider

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.securewave.app.PacketTunnel",
        category: "vpn"
    )

    /// App Group identifier read from Info.plist (SecureWaveAppGroupIdentifier key).
    /// Falls back to a derived identifier if the key is absent.
    private var appGroupIdentifier: String {
        if let configured = (Bundle.main.object(forInfoDictionaryKey: "SecureWaveAppGroupIdentifier") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return configured
        }
        let bundleId = Bundle.main.bundleIdentifier ?? "com.securewave.app.PacketTunnel"
        let base = bundleId.replacingOccurrences(of: ".PacketTunnel", with: "")
        return "group.\(base).shared"
    }

    #if canImport(WireGuardKit)
    private var adapter: WireGuardAdapter?
    #endif

    // MARK: - Tunnel Lifecycle

    override func startTunnel(
        options: [String: NSObject]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        log.log("startTunnel called")

        guard
            let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
            let providerConfiguration = tunnelProtocol.providerConfiguration,
            let config = buildWireGuardConfig(from: providerConfiguration)
        else {
            let error = makeError(code: -10, message: "Missing or invalid WireGuard configuration.")
            persistStatus(state: "error", lastError: error.localizedDescription, connectedSince: 0)
            log.error("startTunnel aborted: missing config")
            completionHandler(error)
            return
        }

        persistStatus(state: "connecting", lastError: nil, connectedSince: 0)

        #if canImport(WireGuardKit)
        startWithWireGuardKit(config: config, completionHandler: completionHandler)
        #else
        let error = makeError(
            code: -11,
            message: "WireGuardKit is not linked. Add the Swift Package in Xcode."
        )
        persistStatus(state: "error", lastError: error.localizedDescription, connectedSince: 0)
        log.error("startTunnel aborted: WireGuardKit not linked")
        completionHandler(error)
        #endif
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        persistStatus(state: "disconnecting", lastError: nil, connectedSince: readConnectedSince())

        #if canImport(WireGuardKit)
        log.log("stopTunnel: reason=\(reason.rawValue, privacy: .public)")
        adapter?.stop { [weak self] _ in
            self?.persistStatus(state: "disconnected", lastError: nil, connectedSince: 0)
            self?.log.log("tunnel stopped")
            completionHandler()
        }
        adapter = nil
        #else
        persistStatus(state: "disconnected", lastError: nil, connectedSince: 0)
        log.log("stopTunnel (no WireGuardKit)")
        completionHandler()
        #endif
    }

    /// Responds to status queries sent from the host app via
    /// NETunnelProviderSession.sendProviderMessage(_:responseHandler:).
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard
            let request = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
            (request["action"] as? String) == "status"
        else {
            completionHandler?(nil)
            return
        }
        let payload = statusPayload()
        let response = try? JSONSerialization.data(withJSONObject: payload)
        completionHandler?(response)
    }

    // MARK: - WireGuardKit Start

    #if canImport(WireGuardKit)
    private func startWithWireGuardKit(
        config: String,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            let tunnelConfig = try TunnelConfiguration(fromWgQuickConfig: config, called: "SecureWave")
            let adapter = WireGuardAdapter(with: self) { [weak self] level, message in
                switch level {
                case .verbose: self?.log.debug("WG: \(message, privacy: .public)")
                case .error:   self?.log.error("WG: \(message, privacy: .public)")
                }
            }
            self.adapter = adapter
            adapter.start(tunnelConfiguration: tunnelConfig) { [weak self] error in
                if let error = error {
                    self?.persistStatus(state: "error", lastError: error.localizedDescription, connectedSince: 0)
                    self?.log.error("WireGuardAdapter.start failed: \(String(describing: error), privacy: .public)")
                    completionHandler(error)
                } else {
                    let ts = Int(Date().timeIntervalSince1970)
                    self?.persistStatus(state: "connected", lastError: nil, connectedSince: ts)
                    self?.log.log("tunnel connected")
                    completionHandler(nil)
                }
            }
        } catch let parseError as TunnelConfiguration.ParseError {
            let message = parseError.userFacingMessage
            persistStatus(state: "error", lastError: message, connectedSince: 0)
            log.error("config parse failed: \(message, privacy: .public)")
            completionHandler(makeError(code: -12, message: message))
        } catch {
            persistStatus(state: "error", lastError: "Failed to start tunnel.", connectedSince: 0)
            log.error("startTunnel unexpected error")
            completionHandler(makeError(code: -13, message: "Failed to start tunnel."))
        }
    }
    #endif

    // MARK: - Config Assembly

    /// Builds a wg-quick config string from the providerConfiguration dictionary.
    /// Prefers the pre-rendered `wgQuickConfig` string if present; otherwise
    /// assembles from individual fields (for compatibility with older profiles).
    private func buildWireGuardConfig(from providerConfiguration: [String: Any]) -> String? {
        // Fast path: pre-rendered config string.
        if let wgQuick = providerConfiguration["wgQuickConfig"] as? String,
           !wgQuick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return wgQuick
        }

        // Field-by-field assembly.
        let host = (providerConfiguration["endpointHost"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let port: Int = {
            if let i = providerConfiguration["endpointPort"] as? Int { return i }
            if let s = providerConfiguration["endpointPort"] as? String, let i = Int(s) { return i }
            return 0
        }()
        let privateKey = (providerConfiguration["clientPrivateKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let address    = (providerConfiguration["addressCidr"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pubKey     = (providerConfiguration["serverPublicKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty, port > 0, !privateKey.isEmpty, !address.isEmpty, !pubKey.isEmpty else {
            return nil
        }

        let dns = (providerConfiguration["dns"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let allowedIps = (providerConfiguration["allowedIps"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let keepalive: Int = {
            if let i = providerConfiguration["keepaliveSeconds"] as? Int { return i }
            if let s = providerConfiguration["keepaliveSeconds"] as? String, let i = Int(s) { return i }
            return 0
        }()
        let psk = (providerConfiguration["presharedKey"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var lines = ["[Interface]", "PrivateKey = \(privateKey)", "Address = \(address)"]
        if !dns.isEmpty { lines.append("DNS = \(dns.joined(separator: ", "))") }
        lines += ["", "[Peer]", "PublicKey = \(pubKey)"]
        if !psk.isEmpty { lines.append("PresharedKey = \(psk)") }
        let ips = allowedIps.isEmpty ? "0.0.0.0/0, ::/0" : allowedIps.joined(separator: ", ")
        lines.append("AllowedIPs = \(ips)")
        let endpointHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        lines.append("Endpoint = \(endpointHost):\(port)")
        if keepalive > 0 { lines.append("PersistentKeepalive = \(keepalive)") }

        return lines.joined(separator: "\n")
    }

    // MARK: - Status Persistence

    private func statusPayload() -> [String: Any] {
        let stats = utunCounters()
        return [
            "state": readState(),
            "lastError": readLastError() as Any,
            "rxBytes": Int(stats.rx),
            "txBytes": Int(stats.tx),
            "connectedSince": readConnectedSince(),
        ]
    }

    private func persistStatus(state: String, lastError: String?, connectedSince: Int) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.set(state, forKey: SecureWaveSharedState.stateKey)
        if let err = lastError, !err.isEmpty {
            defaults.set(err, forKey: SecureWaveSharedState.lastErrorKey)
        } else {
            defaults.removeObject(forKey: SecureWaveSharedState.lastErrorKey)
        }
        let stats = utunCounters()
        defaults.set(Int(stats.rx), forKey: SecureWaveSharedState.rxBytesKey)
        defaults.set(Int(stats.tx), forKey: SecureWaveSharedState.txBytesKey)
        defaults.set(connectedSince, forKey: SecureWaveSharedState.connectedSinceKey)
    }

    private func readState() -> String {
        UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: SecureWaveSharedState.stateKey) ?? "disconnected"
    }

    private func readLastError() -> String? {
        UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: SecureWaveSharedState.lastErrorKey)
    }

    private func readConnectedSince() -> Int {
        UserDefaults(suiteName: appGroupIdentifier)?.integer(forKey: SecureWaveSharedState.connectedSinceKey) ?? 0
    }

    // MARK: - Network Counters

    private func utunCounters() -> (rx: UInt64, tx: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
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
                if rx + tx >= bestRx + bestTx { bestRx = rx; bestTx = tx }
            }
            guard let next = current.pointee.ifa_next else { break }
            current = next
        }
        return (bestRx, bestTx)
    }

    // MARK: - Helpers

    private func makeError(code: Int, message: String) -> NSError {
        NSError(domain: "SecureWave", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - ParseError user-facing messages

#if canImport(WireGuardKit)
extension TunnelConfiguration.ParseError {
    var userFacingMessage: String {
        switch self {
        case .noInterface:                   return "Missing [Interface] section."
        case .multipleInterfaces:            return "Multiple [Interface] sections."
        case .interfaceHasNoPrivateKey:      return "Missing PrivateKey."
        case .interfaceHasInvalidPrivateKey: return "Invalid PrivateKey."
        case .interfaceHasInvalidListenPort: return "Invalid ListenPort."
        case .interfaceHasInvalidAddress:    return "Invalid Address."
        case .interfaceHasInvalidDNS:        return "Invalid DNS."
        case .interfaceHasInvalidMTU:        return "Invalid MTU."
        case .interfaceHasUnrecognizedKey:   return "Unrecognized key in [Interface]."
        case .peerHasNoPublicKey:            return "Missing PublicKey in [Peer]."
        case .peerHasInvalidPublicKey:       return "Invalid PublicKey in [Peer]."
        case .peerHasInvalidPreSharedKey:    return "Invalid PresharedKey in [Peer]."
        case .peerHasInvalidAllowedIP:       return "Invalid AllowedIPs in [Peer]."
        case .peerHasInvalidEndpoint:        return "Invalid Endpoint in [Peer]."
        case .peerHasInvalidPersistentKeepAlive: return "Invalid PersistentKeepalive in [Peer]."
        case .peerHasUnrecognizedKey:        return "Unrecognized key in [Peer]."
        case .multiplePeersWithSamePublicKey: return "Duplicate peer PublicKey."
        case .multipleEntriesForKey:         return "Multiple entries for single-value key."
        case .invalidLine:                   return "Invalid line in config."
        }
    }
}
#endif
