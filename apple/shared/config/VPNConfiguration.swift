// VPNConfiguration.swift
// WireGuard configuration model shared between host app and macOS client.
// Converts a server API response into the providerConfiguration dictionary
// expected by NETunnelProviderProtocol and PacketTunnelProvider.

import Foundation
import NetworkExtension

// MARK: - WireGuard Configuration Model

/// Validated, immutable WireGuard configuration derived from the SecureWave API.
public struct WireGuardConfiguration {
    public let serverId: String
    public let serverName: String
    public let endpointHost: String
    public let endpointPort: Int
    public let clientPrivateKey: String
    public let serverPublicKey: String
    public let addressCidr: String
    public let dns: [String]
    public let allowedIps: [String]
    public let keepaliveSeconds: Int
    public let presharedKey: String?

    // MARK: Init from API response

    public init(from apiConfig: SWVPNConfig, serverId: String, serverName: String) throws {
        guard !apiConfig.clientPrivateKey.isEmpty else {
            throw WireGuardConfigError.missingField("client_private_key")
        }
        guard !apiConfig.serverPublicKey.isEmpty else {
            throw WireGuardConfigError.missingField("server_public_key")
        }
        guard !apiConfig.endpointHost.isEmpty else {
            throw WireGuardConfigError.missingField("endpoint_host")
        }
        guard apiConfig.endpointPort > 0, apiConfig.endpointPort <= 65535 else {
            throw WireGuardConfigError.invalidPort(apiConfig.endpointPort)
        }
        guard !apiConfig.addressCidr.isEmpty else {
            throw WireGuardConfigError.missingField("address_cidr")
        }
        guard !apiConfig.allowedIps.isEmpty else {
            throw WireGuardConfigError.missingField("allowed_ips")
        }

        self.serverId = serverId
        self.serverName = serverName
        self.endpointHost = apiConfig.endpointHost
        self.endpointPort = apiConfig.endpointPort
        self.clientPrivateKey = apiConfig.clientPrivateKey
        self.serverPublicKey = apiConfig.serverPublicKey
        self.addressCidr = apiConfig.addressCidr
        self.dns = apiConfig.dns
        self.allowedIps = apiConfig.allowedIps
        self.keepaliveSeconds = max(0, apiConfig.keepaliveSeconds)
        let psk = apiConfig.presharedKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.presharedKey = psk?.isEmpty == true ? nil : psk
    }

    // MARK: wg-quick config string

    /// Renders the standard wg-quick INI format consumed by PacketTunnelProvider.
    public func wgQuickConfig() -> String {
        var lines = [
            "[Interface]",
            "PrivateKey = \(clientPrivateKey)",
            "Address = \(addressCidr)",
        ]
        if !dns.isEmpty {
            lines.append("DNS = \(dns.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("[Peer]")
        lines.append("PublicKey = \(serverPublicKey)")
        if let psk = presharedKey {
            lines.append("PresharedKey = \(psk)")
        }
        lines.append("AllowedIPs = \(allowedIps.joined(separator: ", "))")
        // IPv6-literal endpoint needs brackets.
        let host = endpointHost.contains(":") && !endpointHost.hasPrefix("[")
            ? "[\(endpointHost)]"
            : endpointHost
        lines.append("Endpoint = \(host):\(endpointPort)")
        if keepaliveSeconds > 0 {
            lines.append("PersistentKeepalive = \(keepaliveSeconds)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: NETunnelProviderProtocol providerConfiguration

    /// Dictionary written into NETunnelProviderProtocol.providerConfiguration.
    /// Keys match the field constants in VPNManager.swift / PacketTunnelProvider.swift.
    public func providerConfiguration(appGroupIdentifier: String) -> [String: Any] {
        var config: [String: Any] = [
            "wgQuickConfig": wgQuickConfig(),
            "serverId": serverId,
            "endpointHost": endpointHost,
            "endpointPort": endpointPort,
            "clientPrivateKey": clientPrivateKey,
            "serverPublicKey": serverPublicKey,
            "addressCidr": addressCidr,
            "dns": dns,
            "allowedIps": allowedIps,
            "keepaliveSeconds": keepaliveSeconds,
            "SecureWaveAppGroupIdentifier": appGroupIdentifier,
        ]
        if let psk = presharedKey {
            config["presharedKey"] = psk
        }
        return config
    }

    // MARK: NEPacketTunnelNetworkSettings

    /// Build network settings for use inside PacketTunnelProvider.startTunnel()
    /// when WireGuardKit is unavailable and manual routing is needed.
    public func networkSettings(tunnelRemoteAddress: String) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelRemoteAddress)

        // IPv4 routing
        let components = addressCidr.split(separator: "/")
        let address = String(components.first ?? "10.0.0.2")
        let prefixLength = Int(components.last ?? "32") ?? 32
        let ipv4Settings = NEIPv4Settings(addresses: [address], subnetMasks: [prefixString(prefix: prefixLength)])
        ipv4Settings.includedRoutes = allowedIps.compactMap { cidr -> NEIPv4Route? in
            let parts = cidr.split(separator: "/")
            guard parts.count == 2,
                  let prefix = Int(parts[1]),
                  !cidr.contains(":") else { return nil }
            return NEIPv4Route(destinationAddress: String(parts[0]), subnetMask: prefixString(prefix: prefix))
        }
        settings.ipv4Settings = ipv4Settings

        // DNS
        if !dns.isEmpty {
            let dnsSettings = NEDNSSettings(servers: dns)
            dnsSettings.matchDomains = [""] // Route all DNS through tunnel.
            settings.dnsSettings = dnsSettings
        }

        // MTU — WireGuard standard is 1420.
        settings.mtu = 1420

        return settings
    }

    private func prefixString(prefix: Int) -> String {
        let mask = prefix == 0 ? 0 : (~0 << (32 - prefix))
        let b1 = (mask >> 24) & 0xFF
        let b2 = (mask >> 16) & 0xFF
        let b3 = (mask >> 8) & 0xFF
        let b4 = mask & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }
}

// MARK: - Errors

public enum WireGuardConfigError: Error, LocalizedError {
    case missingField(String)
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case .missingField(let field):
            return "WireGuard configuration is missing required field: \(field)"
        case .invalidPort(let port):
            return "Invalid endpoint port: \(port). Must be 1–65535."
        }
    }
}
