// ContentView.swift
// Main UI for the SecureWave macOS standalone client.
// Shows: server list, connection toggle, status indicators, data usage.

import SwiftUI
import NetworkExtension

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var auth: AuthModel

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            // Brand
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.teal)

            Text("SecureWave VPN")
                .font(.title.bold())

            Text("Sign in to continue")
                .foregroundStyle(.secondary)

            // Form
            VStack(spacing: 12) {
                TextField("Email", text: $username)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 300)

            if let error = auth.loginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button(action: {
                Task { await auth.login(username: username, password: password) }
            }) {
                Group {
                    if auth.isLoggingIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sign In")
                    }
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .disabled(username.isEmpty || password.isEmpty || auth.isLoggingIn)
            .keyboardShortcut(.return)

            Link("Forgot password?",
                 destination: URL(string: "https://securewaveapp.com/forgot_password")!)
                .font(.caption)
        }
        .padding(40)
        .frame(width: 380)
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var vpn: VPNProfileManager
    @EnvironmentObject var auth: AuthModel

    @State private var servers: [SWServer] = []
    @State private var selectedServer: SWServer?
    @State private var isLoadingServers = false
    @State private var serverError: String?

    var body: some View {
        NavigationSplitView {
            // Sidebar: server list
            ServerListView(
                servers: servers,
                selectedServer: $selectedServer,
                isLoading: isLoadingServers,
                error: serverError
            )
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { Task { await loadServers() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingServers)
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: { auth.logout() }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        } detail: {
            // Detail: connection panel
            ConnectionPanel(selectedServer: selectedServer)
        }
        .task { await loadServers() }
    }

    private func loadServers() async {
        isLoadingServers = true
        serverError = nil
        defer { isLoadingServers = false }
        do {
            let fetched = try await SecureWaveAPIClient.shared.servers()
            servers = fetched
            // Pre-select the first online server if nothing is selected.
            if selectedServer == nil {
                selectedServer = fetched.first(where: { $0.isOnline })
            }
        } catch {
            serverError = error.localizedDescription
        }
    }
}

// MARK: - Server List

struct ServerListView: View {
    let servers: [SWServer]
    @Binding var selectedServer: SWServer?
    let isLoading: Bool
    let error: String?

    var body: some View {
        Group {
            if isLoading && servers.isEmpty {
                ProgressView("Loading servers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(servers, selection: $selectedServer) { server in
                    ServerRow(server: server)
                        .tag(server)
                }
            }
        }
    }
}

struct ServerRow: View {
    let server: SWServer

    var body: some View {
        HStack {
            Circle()
                .fill(server.isOnline ? .green : .red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.city)
                    .font(.body)
                Text(server.country)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let latency = server.latencyMs {
                Text("\(latency) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(latencyColor(ms: latency))
            }
        }
        .opacity(server.isOnline ? 1.0 : 0.5)
    }

    private func latencyColor(ms: Int) -> Color {
        switch ms {
        case 0..<80:   return .green
        case 80..<200: return .yellow
        default:       return .red
        }
    }
}

// MARK: - Connection Panel

struct ConnectionPanel: View {
    @EnvironmentObject var vpn: VPNProfileManager
    let selectedServer: SWServer?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Status badge
            StatusBadge(state: vpn.connectionState)

            // Server info
            if let server = vpn.connectedServer ?? selectedServer {
                VStack(spacing: 4) {
                    Text(server.city)
                        .font(.title2.bold())
                    Text(server.country)
                        .foregroundStyle(.secondary)
                }
            }

            // Connect / Disconnect button
            ConnectButton(
                state: vpn.connectionState,
                targetServer: selectedServer,
                onConnect: { server in
                    Task {
                        try? await vpn.connect(to: server)
                    }
                },
                onDisconnect: {
                    Task { await vpn.disconnect() }
                }
            )

            // Traffic counters (only when connected)
            if case .connected = vpn.connectionState {
                TrafficStats(bytesIn: vpn.bytesIn, bytesOut: vpn.bytesOut)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let state: VPNConnectionState

    var body: some View {
        ZStack {
            Circle()
                .fill(circleColor.opacity(0.15))
                .frame(width: 120, height: 120)

            Circle()
                .strokeBorder(circleColor, lineWidth: 3)
                .frame(width: 120, height: 120)

            Image(systemName: iconName)
                .font(.system(size: 44))
                .foregroundStyle(circleColor)
        }
        .animation(.easeInOut(duration: 0.3), value: state.displayLabel)
    }

    private var circleColor: Color {
        switch state {
        case .connected:     return .teal
        case .connecting,
             .disconnecting: return .orange
        case .error:         return .red
        case .disconnected:  return .secondary
        }
    }

    private var iconName: String {
        switch state {
        case .connected:     return "lock.shield.fill"
        case .connecting,
             .disconnecting: return "lock.shield"
        case .error:         return "exclamationmark.shield"
        case .disconnected:  return "shield.slash"
        }
    }
}

// MARK: - Connect Button

struct ConnectButton: View {
    let state: VPNConnectionState
    let targetServer: SWServer?
    let onConnect: (SWServer) -> Void
    let onDisconnect: () -> Void

    var body: some View {
        Button(action: handleTap) {
            Group {
                if case .connecting = state {
                    ProgressView().controlSize(.small)
                } else if case .disconnecting = state {
                    ProgressView().controlSize(.small)
                } else {
                    Text(buttonLabel)
                }
            }
            .frame(minWidth: 160)
        }
        .buttonStyle(.borderedProminent)
        .tint(buttonTint)
        .controlSize(.large)
        .disabled(isDisabled)
    }

    private var buttonLabel: String {
        switch state {
        case .connected:     return "Disconnect"
        case .disconnected,
             .error:         return "Connect"
        case .connecting:    return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        }
    }

    private var buttonTint: Color {
        if case .connected = state { return .red }
        return .teal
    }

    private var isDisabled: Bool {
        switch state {
        case .connecting, .disconnecting: return true
        case .disconnected, .error: return targetServer == nil
        default: return false
        }
    }

    private func handleTap() {
        switch state {
        case .connected:
            onDisconnect()
        case .disconnected, .error:
            if let server = targetServer {
                onConnect(server)
            }
        default:
            break
        }
    }
}

// MARK: - Traffic Stats

struct TrafficStats: View {
    let bytesIn: UInt64
    let bytesOut: UInt64

    var body: some View {
        HStack(spacing: 32) {
            StatCell(label: "Download", value: formatBytes(bytesIn), icon: "arrow.down.circle")
            StatCell(label: "Upload", value: formatBytes(bytesOut), icon: "arrow.up.circle")
        }
        .font(.caption)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", kb)
    }
}

struct StatCell: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
            Text(value)
                .font(.body.monospacedDigit().bold())
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - SWServer Identifiable / Hashable

extension SWServer: Hashable {
    public static func == (lhs: SWServer, rhs: SWServer) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
