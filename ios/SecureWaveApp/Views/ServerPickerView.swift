import SwiftUI

struct ServerPickerView: View {
    let servers: [Server]
    @Binding var selectedServer: Server?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose Server")
                .font(.headline)
            Picker("Server", selection: $selectedServer) {
                ForEach(servers) { server in
                    Text(server.location).tag(Optional(server))
                }
            }
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
