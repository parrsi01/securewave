import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var session: UserSession
    @State private var servers: [Server] = []
    @State private var selectedServer: Server?
    @State private var isConnected = false
    @State private var isLoading = false
    @State private var statusMessage = "Disconnected"
    @State private var connectionId: Int?

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text(statusMessage)
                    .font(.headline)
                    .foregroundColor(isConnected ? .green : .secondary)

                Toggle("VPN Enabled", isOn: $isConnected)
                    .onChange(of: isConnected) { _, newValue in
                        Task { await toggleVPN(newValue) }
                    }

                ServerPickerView(servers: servers, selectedServer: $selectedServer)

                if isLoading {
                    ProgressView("Working...")
                }

                Spacer()
            }
            .padding()
            .navigationTitle("SecureWave")
            .task { await loadServers() }
        }
    }

    private func loadServers() async {
        guard let token = session.accessToken else { return }
        do {
            let results = try await APIClient.shared.fetchServers(token: token)
            await MainActor.run {
                servers = results
                selectedServer = results.first
            }
        } catch {
            await MainActor.run {
                statusMessage = "Failed to load servers"
            }
        }
    }

    private func toggleVPN(_ shouldConnect: Bool) async {
        guard let token = session.accessToken else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            if shouldConnect {
                statusMessage = "Connecting..."
                let response = try await APIClient.shared.connectVPN(token: token, serverId: selectedServer?.id)
                if let config = response["config"] as? String {
                    try await VPNService.shared.connect(using: config)
                }
                if let id = response["connection_id"] as? Int {
                    connectionId = id
                }
                statusMessage = "Connected"
            } else {
                statusMessage = "Disconnecting..."
                try await APIClient.shared.disconnectVPN(token: token, connectionId: connectionId)
                try await VPNService.shared.disconnect()
                connectionId = nil
                statusMessage = "Disconnected"
            }
        } catch {
            statusMessage = "Connection failed"
            await MainActor.run {
                isConnected = false
            }
        }
    }
}
