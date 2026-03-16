// VPNProfileManager.swift
// Installs, removes, starts, and stops the SecureWave WireGuard VPN profile.
// Wraps NETunnelProviderManager with observable state for SwiftUI.
// Used by the macOS standalone client (SecureWaveMacApp).
//
// Threading: All NetworkExtension callbacks arrive on an unspecified queue.
// State updates are dispatched to MainActor so SwiftUI can bind directly.

import Foundation
import NetworkExtension
import Combine
import os

// MARK: - Connection State

public enum VPNConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(since: Date)
    case disconnecting
    case error(String)

    public var displayLabel: String {
        switch self {
        case .disconnected:  return "Disconnected"
        case .connecting:    return "Connecting..."
        case .connected:     return "Connected"
        case .disconnecting: return "Disconnecting..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    public var isActive: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - VPN Profile Manager

@MainActor
public final class VPNProfileManager: ObservableObject {
    public static let shared = VPNProfileManager()

    @Published public private(set) var connectionState: VPNConnectionState = .disconnected
    @Published public private(set) var connectedServer: SWServer?
    @Published public private(set) var bytesIn: UInt64 = 0
    @Published public private(set) var bytesOut: UInt64 = 0

    private let log = Logger(subsystem: "com.securewave.mac", category: "VPNProfileManager")
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var statsTimer: Timer?

    private let appGroupIdentifier: String
    private let providerBundleIdentifier: String

    public init(
        appGroupIdentifier: String = "group.com.securewave.mac.shared",
        providerBundleIdentifier: String = "com.securewave.mac.PacketTunnel"
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.providerBundleIdentifier = providerBundleIdentifier
        Task { await self.loadExistingManager() }
    }

    // MARK: - Public API

    /// Install and activate a WireGuard profile for the given server.
    /// Fetches config from the API, writes the NE profile, then starts the tunnel.
    public func connect(to server: SWServer) async throws {
        log.info("connect(to:) called for server: \(server.id, privacy: .public)")
        connectionState = .connecting
        connectedServer = server

        let apiConfig: SWVPNConfig
        do {
            apiConfig = try await SecureWaveAPIClient.shared.vpnConfig(serverId: server.id)
        } catch {
            log.error("vpnConfig fetch failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .error("Could not fetch VPN configuration: \(error.localizedDescription)")
            throw error
        }

        let config: WireGuardConfiguration
        do {
            config = try WireGuardConfiguration(from: apiConfig, serverId: server.id, serverName: server.name)
        } catch {
            log.error("WireGuardConfiguration init failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .error(error.localizedDescription)
            throw error
        }

        try await installAndStart(config: config, server: server)
    }

    /// Stop the active tunnel and remove the VPN profile.
    public func disconnect() async {
        log.info("disconnect() called")
        connectionState = .disconnecting
        stopStatsTimer()

        guard let manager = manager else {
            connectionState = .disconnected
            connectedServer = nil
            return
        }

        if let session = manager.connection as? NETunnelProviderSession {
            session.stopTunnel()
        } else {
            manager.connection.stopVPNTunnel()
        }
        // State transitions to .disconnected via the NEVPNStatusDidChange observer.
    }

    /// Remove the installed VPN configuration from System Preferences.
    public func removeProfile() async throws {
        guard let manager = manager else { return }
        try await withCheckedThrowingContinuation { continuation in
            manager.removeFromPreferences { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        self.manager = nil
        connectionState = .disconnected
        connectedServer = nil
        log.info("VPN profile removed")
    }

    // MARK: - Internal

    private func loadExistingManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let existing = managers.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                    == providerBundleIdentifier
            }
            if let existing = existing {
                self.manager = existing
                observeStatus(of: existing)
                syncState(from: existing.connection.status)
                log.info("Loaded existing VPN manager, status: \(existing.connection.status.rawValue, privacy: .public)")
            }
        } catch {
            log.error("loadExistingManager failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func installAndStart(config: WireGuardConfiguration, server: SWServer) async throws {
        // Load existing managers to avoid duplicates.
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let tunnelManager = managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == providerBundleIdentifier
        } ?? NETunnelProviderManager()

        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = providerBundleIdentifier
        tunnelProtocol.serverAddress = config.endpointHost
        tunnelProtocol.providerConfiguration = config.providerConfiguration(
            appGroupIdentifier: appGroupIdentifier
        )

        tunnelManager.protocolConfiguration = tunnelProtocol
        tunnelManager.localizedDescription = "SecureWave VPN — \(server.city)"
        tunnelManager.isEnabled = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            tunnelManager.saveToPreferences { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            tunnelManager.loadFromPreferences { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        self.manager = tunnelManager
        observeStatus(of: tunnelManager)

        do {
            if let session = tunnelManager.connection as? NETunnelProviderSession {
                try session.startVPNTunnel()
            } else {
                try tunnelManager.connection.startVPNTunnel()
            }
        } catch {
            log.error("startVPNTunnel failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .error("Failed to start tunnel: \(error.localizedDescription)")
            throw error
        }
    }

    private func observeStatus(of manager: NETunnelProviderManager) {
        if let existing = statusObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.syncState(from: manager.connection.status)
            }
        }
    }

    private func syncState(from status: NEVPNStatus) {
        switch status {
        case .connected, .reasserting:
            connectionState = .connected(since: Date())
            startStatsTimer()
        case .connecting:
            connectionState = .connecting
        case .disconnecting:
            connectionState = .disconnecting
            stopStatsTimer()
        case .disconnected, .invalid:
            connectionState = .disconnected
            connectedServer = nil
            stopStatsTimer()
        @unknown default:
            connectionState = .disconnected
        }
    }

    // MARK: - Traffic Stats

    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollStats()
        }
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func pollStats() {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let message: [String: Any] = ["action": "status"]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        try? session.sendProviderMessage(data) { [weak self] responseData in
            guard let self = self,
                  let responseData = responseData,
                  let payload = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            else { return }
            Task { @MainActor in
                self.bytesIn = UInt64(payload["rxBytes"] as? Int ?? 0)
                self.bytesOut = UInt64(payload["txBytes"] as? Int ?? 0)
            }
        }
    }
}
