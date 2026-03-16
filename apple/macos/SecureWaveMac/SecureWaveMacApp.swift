// SecureWaveMacApp.swift
// macOS standalone SwiftUI client for SecureWave VPN.
// Targets macOS 13.0+. Uses NetworkExtension (NETunnelProviderManager)
// to install and control the WireGuard packet tunnel extension.
//
// Bundle ID:      com.securewave.mac
// Extension ID:   com.securewave.mac.PacketTunnel
// App Group:      group.com.securewave.mac.shared

import SwiftUI
import NetworkExtension

@main
struct SecureWaveMacApp: App {

    @StateObject private var vpnManager = VPNProfileManager(
        appGroupIdentifier: "group.com.securewave.mac.shared",
        providerBundleIdentifier: "com.securewave.mac.PacketTunnel"
    )
    @StateObject private var authModel = AuthModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vpnManager)
                .environmentObject(authModel)
                .frame(minWidth: 380, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Menu bar extra — shows connection state at a glance.
        MenuBarExtra("SecureWave VPN", systemImage: menuBarIcon) {
            MenuBarContent()
                .environmentObject(vpnManager)
                .environmentObject(authModel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch vpnManager.connectionState {
        case .connected:     return "lock.shield.fill"
        case .connecting,
             .disconnecting: return "lock.shield"
        default:             return "shield.slash"
        }
    }
}

// MARK: - Auth Model

@MainActor
final class AuthModel: ObservableObject {
    @Published var isLoggedIn: Bool = SecureWaveAPIClient.shared.isAuthenticated
    @Published var loginError: String?
    @Published var isLoggingIn: Bool = false

    func login(username: String, password: String) async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            _ = try await SecureWaveAPIClient.shared.login(username: username, password: password)
            isLoggedIn = true
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout() {
        SecureWaveAPIClient.shared.logout()
        isLoggedIn = false
    }
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var auth: AuthModel

    var body: some View {
        if auth.isLoggedIn {
            ContentView()
        } else {
            LoginView()
        }
    }
}

// MARK: - Menu Bar Content

struct MenuBarContent: View {
    @EnvironmentObject var vpn: VPNProfileManager
    @EnvironmentObject var auth: AuthModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vpn.connectionState.displayLabel)
                .font(.headline)
            if let server = vpn.connectedServer {
                Text(server.city + ", " + server.country)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button(auth.isLoggedIn ? "Open SecureWave" : "Log in") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 220)
    }
}
